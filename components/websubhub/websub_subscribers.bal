// Copyright (c) 2025, WSO2 LLC. (http://www.wso2.org).
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

import ballerina/http;
import ballerina/lang.'runtime as runtime;
import ballerina/lang.value;
import ballerina/log;
import ballerina/mime;
import ballerina/websubhub;

import wso2/messagestore.api as storeapi;

isolated map<websubhub:VerifiedSubscription> subscribersCache = {};

const SUBSCRIPTION_STALE_STATE = "stale";

isolated function processWebsubSubscriptionsSnapshotState(websubhub:VerifiedSubscription[] subscriptions) returns error? {
    log:printDebug("Received latest state-snapshot for websub subscriptions", newState = subscriptions);
    foreach websubhub:VerifiedSubscription subscription in subscriptions {
        check processSubscription(subscription);
    }
}

isolated function processSubscription(websubhub:VerifiedSubscription subscription) returns error? {
    log:printDebug("Subscription event received", topic = subscription.hubTopic, callback = subscription.hubCallback);
    string subscriberId = common:generateSubscriberId(subscription.hubTopic, subscription.hubCallback);
    websubhub:VerifiedSubscription? existingSubscription = getSubscription(subscriberId);
    boolean isFreshSubscription = existingSubscription is ();
    boolean isRenewingStaleSubscription = false;
    if existingSubscription is websubhub:VerifiedSubscription {
        isRenewingStaleSubscription = existingSubscription.hasKey(common:SUBSCRIPTION_STATUS) && existingSubscription.get(common:SUBSCRIPTION_STATUS) is SUBSCRIPTION_STALE_STATE;
    }
    boolean isMarkingSubscriptionAsStale = subscription.hasKey(common:SUBSCRIPTION_STATUS) && subscription.get(common:SUBSCRIPTION_STATUS) is SUBSCRIPTION_STALE_STATE;

    lock {
        // add the subscriber if subscription event received for a new subscription or a stale subscription, when renewing a stale subscription
        if isFreshSubscription || isRenewingStaleSubscription || isMarkingSubscriptionAsStale {
            subscribersCache[subscriberId] = subscription.cloneReadOnly();
        }
    }

    if !isFreshSubscription && !isRenewingStaleSubscription {
        log:printDebug(string `Subscriber ${subscriberId} is already available in the 'hub', hence not starting the consumer`);
        return;
    }
    if isMarkingSubscriptionAsStale {
        log:printDebug(string `Subscriber ${subscriberId} has been marked as stale, hence not starting the consumer`);
        return;
    }

    string serverId = check subscription[common:SUBSCRIPTION_SERVER_ID].ensureType();
    // if the subscription already exists in the `hub` instance, or the given subscription
    // does not belong to the `hub` instance do not start the consumer
    if serverId != config:serverId {
        log:printDebug(
                string `Subscriber ${subscriberId} does not belong to the current server, hence not starting the consumer`,
                subscriberServerId = serverId
        );
        return;
    }

    _ = start pollForNewUpdates(subscriberId, subscription.cloneReadOnly());
}

isolated function processUnsubscription(websubhub:VerifiedUnsubscription unsubscription) returns error? {
    log:printDebug("Unsubscription event received, hence removing the subscriber from the internal state",
            topic = unsubscription.hubTopic, callback = unsubscription.hubCallback);
    string subscriberId = common:generateSubscriberId(unsubscription.hubTopic, unsubscription.hubCallback);
    lock {
        _ = subscribersCache.removeIfHasKey(subscriberId);
    }
}

isolated function pollForNewUpdates(string subscriberId, websubhub:VerifiedSubscription subscription) returns error? {
    string topic = subscription.hubTopic;
    storeapi:Consumer consumerEp = check conn:createConsumer(subscription);
    common:DeliveryMode deliveryMode = config:delivery.deliveryMode;

    log:printDebug("Starting subscriber polling strand", subscriberId = subscriberId, topic = topic, deliveryMode = deliveryMode);
    // In WSH_RETRY mode the HubClient carries the HTTP retry config so the Ballerina WebSub library
    // handles transparent HTTP-level retries. In BROKER_RETRY mode no HTTP retry is set — WSH delivers
    // once per broker redelivery and then signals the outcome via ACK / NACK / REJECTED.
    websubhub:HubClient clientEp;
    if deliveryMode == common:WSH_RETRY {
        clientEp = check new (subscription, {
            httpVersion: http:HTTP_2_0,
            secureSocket: common:extractClientSecureSocketConfig(config:delivery.secureSocket),
            retryConfig: common:extractHttpRetryConfig(config:delivery.'retry),
            timeout: config:delivery.timeout
        });
    } else {
        clientEp = check new (subscription, {
            httpVersion: http:HTTP_2_0,
            secureSocket: common:extractClientSecureSocketConfig(config:delivery.secureSocket),
            timeout: config:delivery.timeout
        });
    }

    do {
        while true {
            storeapi:Message? message = check consumerEp->receive();
            if !isValidConsumer(subscription.hubTopic, subscriberId) {
                fail error common:InvalidSubscriptionError(
                    string `Subscription or the topic is invalid`, topic = topic, subscriberId = subscriberId
                );
            }
            if message is () {
                continue;
            }

            websubhub:ContentDistributionMessage|error notification = constructContentDistMsg(message);
            if notification is error {
                log:printWarn("Error occurred while deserializing the message, hence pushing the message to DLQ", 'error = notification);
                check consumerEp->deadLetter(message);
                continue;
            }

            if deliveryMode == common:BROKER_RETRY {
                check deliverAndAcknowledge(consumerEp, message, clientEp, notification, topic, subscription.hubCallback);
            } else {
                error? result = deliverWithRetryReset(clientEp, notification);
                if result is error {
                    check consumerEp->nack(message);
                    check result;
                } else {
                    common:logContentDelivery(topic, subscription.hubCallback, message.id);
                    check consumerEp->ack(message);
                }
            }
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

        if deliveryMode == common:WSH_RETRY {
            // WSH_RETRY: delivery retries exhausted — mark subscription as stale so the operator
            // can investigate. The consumer is closed permanently.
            common:StaleSubscription staleSubscription = {...subscription};
            error? persistResult = persist:addStaleSubscription(staleSubscription);
            if persistResult is error {
                common:logRecoverableError("Error occurred while marking the subscription as stale", persistResult);
            }
            error? result = consumerEp->close(storeapi:PERMANENT);
            if result is error {
                common:logRecoverableError("Error occurred while gracefully closing message store consumer", result);
            }
        } else {
            // BROKER_RETRY: the broker owns retry/DMQ — subscription stays active for future messages.
            // Close temporarily so the polling loop can be restarted.
            error? result = consumerEp->close(storeapi:TEMPORARY);
            if result is error {
                common:logRecoverableError("Error occurred while gracefully closing message store consumer", result);
            }
        }
    }
}

# Classifies a delivery error as recoverable or non-recoverable based on the HTTP status code.
# - Recoverable  → broker will NACK/FAILED and redeliver (e.g. 500, timeout)
# - Non-recoverable → broker will NACK/REJECTED and route to DMQ (e.g. 400, 404)
isolated function classifyDeliveryError(
        websubhub:Error deliveryError,
        common:BrokerRetryConfig? retryConfig) returns common:FailureBehavior {
    var detail = deliveryError.detail();
    int statusCode = detail.statusCode;

    // statusCode == 0 indicates a timeout or connection-level failure (no HTTP response)
    if statusCode == 0 {
        return retryConfig?.timeoutError ?: "recoverable";
    }
    if retryConfig is () {
        return "recoverable";
    }
    // Detect network/connection errors (e.g. connection refused): Ballerina websubhub library
    // maps transport-level failures to statusCode=500 with no HTTP response body, headers, or mediaType.
    // A real HTTP 500 will have at least headers populated.
    if statusCode == 500 && detail.body is () && detail.headers is () && detail.mediaType is () {
        return retryConfig.networkError;
    }
    if retryConfig.recoverableStatusCodes.indexOf(statusCode) !is () {
        return "recoverable";
    }
    if retryConfig.nonRecoverableStatusCodes.indexOf(statusCode) !is () {
        return "nonRecoverable";
    }
    // Status code not in either explicit list — use configured fallback
    return retryConfig.unknownStatusCodes;
}

# Delivers a message to the subscriber and signals the correct outcome to the broker (BROKER_RETRY mode).
# - Success (2xx)           → consumer.ack()          Message removed from queue
# - Recoverable failure     → sleep(interval) then consumer.nack()   Broker retries
# - Non-recoverable failure → consumer.deadLetter()   Message routed to DMQ
isolated function deliverAndAcknowledge(
        storeapi:Consumer consumerEp,
        storeapi:Message message,
        websubhub:HubClient clientEp,
        websubhub:ContentDistributionMessage notification,
        string topic,
        string callbackUrl) returns error? {
    common:BrokerRetryConfig? retryConfig = config:delivery.brokerRetry;
    // deliveryCount is 1-based (1 = first attempt). Default to 1 if broker does not populate it.
    int attempt = message.deliveryCount ?: 1;
    string messageId = message.id ?: "(none)";

    websubhub:ContentDistributionSuccess|websubhub:Error deliveryResult =
            clientEp->notifyContentDistribution(notification);

    if deliveryResult is websubhub:ContentDistributionSuccess {
        common:logContentDelivery(topic, callbackUrl, message.id, attempt);
        return consumerEp->ack(message);
    }

    // Concern A: the websubhub library can raise websubhub:Error even when the subscriber
    // responded with a 2xx status code (e.g. 202 Accepted treated as error by library internals).
    // Check ackStatusCodes before classifying — treat matched codes as delivery success.
    if retryConfig is common:BrokerRetryConfig {
        int statusCode = deliveryResult.detail().statusCode;
        if retryConfig.ackStatusCodes.indexOf(statusCode) !is () {
            log:printDebug("Delivery error carries an ack-listed status code — treating as success",
                    topic = topic, callback = callbackUrl, messageId = messageId,
                    attempt = attempt, statusCode = statusCode);
            common:logContentDelivery(topic, callbackUrl, message.id, attempt);
            return consumerEp->ack(message);
        }
    }

    common:FailureBehavior behavior = classifyDeliveryError(deliveryResult, retryConfig);

    if behavior == "nonRecoverable" {
        log:printWarn("Non-recoverable delivery failure — routing message to DMQ",
                topic = topic, callback = callbackUrl, messageId = messageId,
                attempt = attempt, statusCode = deliveryResult.detail().statusCode,
                'error = deliveryResult);
        return consumerEp->deadLetter(message);
    }

    // Apply delay before NACKing — Solace redelivery is immediate without this
    if retryConfig is common:BrokerRetryConfig && retryConfig.interval > 0d {
        runtime:sleep(retryConfig.interval);
    }
    log:printWarn("Recoverable delivery failure — signalling broker to retry",
            topic = topic, callback = callbackUrl, messageId = messageId,
            attempt = attempt, statusCode = deliveryResult.detail().statusCode,
            'error = deliveryResult);
    return consumerEp->nack(message);
}

# Delivers a message to the subscriber with WSH-managed HTTP retry (WSH_RETRY mode).
# If `resetOnExhaust` is true the retry loop restarts indefinitely.
# Returns an `error` only when delivery fails for a non-retryable status code or when `resetOnExhaust=false`
# and retries are exhausted — the caller then NACKs the message and propagates the error to trigger
# stale-subscription marking.
isolated function deliverWithRetryReset(
        websubhub:HubClient clientEp,
        websubhub:ContentDistributionMessage notification) returns error? {
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
        int statusCode = result.detail().statusCode;
        if 'retry.statusCodes.indexOf(statusCode) is () {
            return result;
        }
    }
}

isolated function isValidConsumer(string topicName, string subscriberId) returns boolean {
    return isValidTopic(topicName) && isValidSubscription(subscriberId);
}

isolated function isValidSubscription(string subscriberId) returns boolean {
    lock {
        return subscribersCache.hasKey(subscriberId);
    }
}

isolated function getSubscription(string subscriberId) returns websubhub:VerifiedSubscription? {
    lock {
        return subscribersCache[subscriberId].cloneReadOnly();
    }
}

isolated function constructContentDistMsg(storeapi:Message message) returns websubhub:ContentDistributionMessage|error {
    string payloadString = check string:fromBytes(message.payload);
    json payload = check value:fromJsonString(payloadString);
    websubhub:ContentDistributionMessage distributionMsg = {
        content: payload,
        contentType: mime:APPLICATION_JSON,
        headers: constructDeliveryHeaders(message)
    };
    return distributionMsg;
}

isolated function constructDeliveryHeaders(storeapi:Message message) returns map<string|string[]>? {
    string? messageId = message.id;
    if messageId is () {
        return message.metadata;
    }

    map<string|string[]>? metadata = message.metadata;
    if metadata is () {
        return {
            "x-hub-messageId": messageId
        };
    }
    metadata["x-hub-messageId"] = messageId;
    return metadata;
}
