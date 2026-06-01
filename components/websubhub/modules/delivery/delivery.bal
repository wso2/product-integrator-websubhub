// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.org).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import websubhub.admin;
import websubhub.common;
import websubhub.config;
import websubhub.connections as conn;
import websubhub.persistence as persist;
import websubhub.state;

import ballerina/http;
import ballerina/lang.'runtime as runtime;
import ballerina/log;
import ballerina/websubhub;

import wso2/messagestore.api as storeapi;

# Backoff applied after a failed `receive()` before polling again. Bounds the redelivery loop for an
# unreadable (e.g. zero-length) message so it does not spin the CPU while the broker counts down
# max-redelivery and routes the poison message to the DMQ.
const decimal RECEIVE_ERROR_BACKOFF = 1;

# Distributes a content notification to the specified subscriber using an async worker.
# This function delivers the published content update associated with the
# subscription to the subscriber endpoint using the configured content
# delivery mechanism.
#
# + subscription - Verified subscription details
# + return - An error if the content notification distribution fails
public isolated function distributeContentNotification(websubhub:VerifiedSubscription subscription) returns error? {
    string subscriberId = common:generateSubscriberId(subscription.hubTopic, subscription.hubCallback);
    string topic = subscription.hubTopic;
    storeapi:Consumer consumerEp = check conn:createConsumer(subscription);
    websubhub:HubClient clientEp = check new (subscription, {
        httpVersion: http:HTTP_2_0,
        secureSocket: common:extractClientSecureSocketConfig(config:delivery.secureSocket),
        retryConfig: common:extractHttpRetryConfig(config:delivery.'retry),
        timeout: config:delivery.timeout
    });
    do {
        while true {
            if !isValidConsumer(subscription.hubTopic, subscriberId) {
                fail error common:InvalidSubscriptionError(
                    string `Subscription or the topic is invalid`, topic = topic, subscriberId = subscriberId
                );
            }
            // deliverNextNotification returns () for a handled/skipped message (loop continues) and an
            // error only for fatal conditions that must stop the consumer (e.g. delivery exhausted →
            // stale). A receive() failure is treated as recoverable inside it (logged + skipped), so a
            // single unreadable message never reaches this `check` and never halts the subscriber.
            check deliverNextNotification(consumerEp, clientEp, topic, subscription.hubCallback);
        }
    } on fail var e {
        common:logRecoverableError("Error occurred while sending notification to subscriber", e);

        if e is common:InvalidSubscriptionError {
            error? result = consumerEp->close(storeapi:PERMANENT);
            if result is error {
                common:logRecoverableError("Error occurred while gracefully closing message store consumer", result);
            }
            return;
        }

        if !isValidConsumer(subscription.hubTopic, subscriberId) {
            // In some cases a messaging consumer will be attached to an entity in the message store (queue or topic) and that
            // entity will be removed when unsubscribing, hence it is appropriate to stop the consumer in those cases
            error? result = consumerEp->close(storeapi:PERMANENT);
            if result is error {
                common:logRecoverableError("Error occurred while gracefully closing message store consumer", result);
            }
            return;
        }

        // If subscription-deleted error received, remove the subscription
        if e is websubhub:SubscriptionDeletedError {
            error? result = consumerEp->close(storeapi:PERMANENT);
            if result is error {
                common:logRecoverableError("Error occurred while gracefully closing message store consumer", result);
            }

            websubhub:VerifiedUnsubscription unsubscription = {
                hubMode: "unsubscribe",
                hubTopic: subscription.hubTopic,
                hubCallback: subscription.hubCallback,
                hubSecret: subscription.hubSecret
            };

            error? subscriptionDeletion = admin:deleteSubscription(subscription);
            if subscriptionDeletion is error {
                common:logRecoverableError(
                        "Error occurred while removing the subscription", subscriptionDeletion, subscription = unsubscription);
            }

            error? persistResult = persist:removeSubscription(unsubscription);
            if persistResult is error {
                common:logRecoverableError(
                        "Error occurred while removing the subscription", persistResult, subscription = unsubscription);
            }
            return;
        }

        error? result = consumerEp->close(storeapi:TEMPORARY);
        if result is error {
            common:logRecoverableError("Error occurred while gracefully closing message store consumer", result);
        }
        // Persist the subscription as a `stale` subscription whenever the content delivery fails
        common:StaleSubscription staleSubscription = {
            ...subscription
        };
        error? persistResult = persist:addStaleSubscription(staleSubscription);
        if persistResult is error {
            common:logRecoverableError(
                    "Error occurred while persisting the stale subscription", persistResult, subscription = staleSubscription);
        }
    }
}

# Polls for and delivers a single notification.
#
# Returns `()` when the iteration was handled and the caller should continue polling — this includes
# the recoverable cases: nothing received, an unreadable message (receive error → skipped so the
# broker can redeliver/DMQ it), and a deserialization failure (message dead-lettered).
#
# Returns an `error` ONLY for fatal conditions that must stop the consumer (e.g. delivery retries
# exhausted), which the caller propagates to mark the subscription stale. Keeping receive-error
# handling here (rather than letting it propagate) is what prevents one unreadable message from
# halting the whole subscriber.
#
# + consumerEp - The message-store consumer to poll
# + clientEp - The subscriber HubClient
# + topic - The hub topic
# + callbackUrl - The subscriber callback URL
# + return - `()` to continue polling, or an `error` for a fatal (stale-triggering) delivery failure
isolated function deliverNextNotification(storeapi:Consumer consumerEp, websubhub:HubClient clientEp,
        string topic, string callbackUrl) returns error? {
    storeapi:Message|error? received = consumerEp->receive();
    if received is error {
        // Recoverable: a single unreadable message (e.g. a zero-length payload that the broker adapter
        // cannot deserialize) must NOT halt the subscriber. Log and back off; the message stays
        // unacked, so the broker redelivers it and ultimately routes it to the DMQ once max-redelivery
        // is exceeded. The brief sleep prevents a hot loop while the broker counts down redeliveries.
        common:logRecoverableError(
                "Error occurred while receiving a message; skipping it so the broker can redeliver/DMQ it",
                received, topic = topic);
        runtime:sleep(RECEIVE_ERROR_BACKOFF);
        return;
    }
    storeapi:Message? message = received;
    if message is () {
        return;
    }

    websubhub:ContentDistributionMessage|error notification = constructContentDistMsg(message);
    if notification is error {
        log:printWarn("Error occurred while deserializing the message, hence pushing the message to DLQ", 'error = notification);
        return consumerEp->deadLetter(message);
    }

    error? result = deliverWithRetryReset(clientEp, notification);
    if result is error {
        check consumerEp->nack(message);
        return result;
    }
    common:logContentDelivery(topic, callbackUrl, message.id);
    return consumerEp->ack(message);
}

isolated function deliverWithRetryReset(websubhub:HubClient clientEp, websubhub:ContentDistributionMessage notification) returns error? {
    common:RetryConfig? 'retry = config:delivery.'retry;
    if 'retry is () || !'retry.resetOnExhaust {
        _ = check clientEp->notifyContentDistribution(notification);
        return;
    }

    while true {
        websubhub:ContentDistributionSuccess|websubhub:Error result = clientEp->notifyContentDistribution(notification);
        if result is websubhub:ContentDistributionSuccess {
            return;
        }

        // Check whether the returned status code is a retryable status-code, if not return the error
        int statusCode = result.detail().statusCode;
        if 'retry.statusCodes.indexOf(statusCode) is () {
            return result;
        }
    }
}

isolated function isValidConsumer(string topicName, string subscriberId) returns boolean {
    return state:isTopicAvailable(topicName) && state:isSubscriptionAvailable(subscriberId);
}
