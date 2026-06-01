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
import websubhub.connections as conn;
import websubhub.persistence as persist;
import websubhub.state;

import ballerina/lang.'runtime as runtime;
import ballerina/websubhub;

import wso2/messagestore.api as storeapi;

# Backoff applied after a failed `receive()` before polling again. Bounds the redelivery loop for an
# unreadable (e.g. zero-length) message so it does not spin the CPU while the broker counts down
# max-redelivery and routes the poison message to the DMQ.
const decimal RECEIVE_ERROR_BACKOFF = 1;
const NUMBER_OF_DEFAULT_ASYNC_WORKERS = 1;

# Distributes a content notification to the specified subscriber using an async worker.
# This function delivers the published content update associated with the
# subscription to the subscriber endpoint using the configured content
# delivery mechanism.
#
# + subscription - Verified subscription details
# + return - An error if the content notification distribution fails
public isolated function distributeContentNotification(readonly & websubhub:VerifiedSubscription subscription) returns error? {
    foreach int i in 0 ..< NUMBER_OF_DEFAULT_ASYNC_WORKERS {
        _ = start startDispatchTask(subscription);
    }
}

isolated function startDispatchTask(websubhub:VerifiedSubscription subscription) returns error? {
    string subscriberId = common:generateSubscriberId(subscription.hubTopic, subscription.hubCallback);
    string topic = subscription.hubTopic;
    storeapi:Consumer consumerEp = check conn:createConsumer(subscription);
    Dispatcher contentDispatcher = check createDispatcher(subscription, consumerEp);
    do {
        while true {
            if !isValidConsumer(subscription.hubTopic, subscriberId) {
                fail error common:InvalidSubscriptionError(
                    string `Subscription or the topic is invalid`, topic = topic, subscriberId = subscriberId
                );
            }

            // A receive() failure (e.g. a zero-length poison message the broker adapter cannot
            // deserialize) must NOT halt the subscriber. Log it, back off, and keep polling; the
            // message stays unacked, so the broker redelivers it and ultimately routes it to the DMQ
            // once max-redelivery is exceeded.
            storeapi:Message|error? received = consumerEp->receive();
            if received is error {
                common:logRecoverableError(
                        "Error occurred while receiving a message; skipping it so the broker can redeliver/DMQ it",
                        received, topic = topic);
                runtime:sleep(RECEIVE_ERROR_BACKOFF);
                continue;
            }
            storeapi:Message? message = received;
            if message is () {
                continue;
            }

            // The dispatcher owns deserialization, HTTP delivery, and the ACK / NACK / dead-letter
            // signal. It returns an error only for a fatal delivery outcome, which propagates to the
            // on-fail block below to mark the subscription stale.
            check contentDispatcher->notifyContentDistribution(message);
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

isolated function isValidConsumer(string topicName, string subscriberId) returns boolean {
    return state:isTopicAvailable(topicName) && state:isSubscriptionAvailable(subscriberId);
}
