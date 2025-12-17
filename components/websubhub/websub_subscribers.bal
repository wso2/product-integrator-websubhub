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

import websubhub.common;
import websubhub.config;
import websubhub.connections as conn;
import websubhub.persistence as persist;

import ballerina/http;
import ballerina/lang.value;
import ballerina/log;
import ballerina/mime;
import ballerina/websubhub;

import wso2/messagestore as store;
import websubhub.admin;

isolated map<websubhub:VerifiedSubscription> subscribersCache = {};

const SUBSCRIPTION_STALE_STATE = "stale";

isolated function processWebsubSubscriptionsSnapshotState(websubhub:VerifiedSubscription[] subscriptions) returns error? {
    log:printDebug("Received latest state-snapshot for websub subscriptions", newState = subscriptions);
    foreach websubhub:VerifiedSubscription subscription in subscriptions {
        check processSubscription(subscription);
    }
}

isolated function processSubscription(websubhub:VerifiedSubscription subscription) returns error? {
    string subscriberId = common:generateSubscriberId(subscription.hubTopic, subscription.hubCallback);
    log:printDebug(string `Subscription event received for the subscriber ${subscriberId}`);
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
    if serverId != config:server.id {
        log:printDebug(
                string `Subscriber ${subscriberId} does not belong to the current server, hence not starting the consumer`,
                subscriberServerId = serverId
        );
        return;
    }

    _ = start pollForNewUpdates(subscriberId, subscription.cloneReadOnly());
}

isolated function processUnsubscription(websubhub:VerifiedUnsubscription unsubscription) returns error? {
    string subscriberId = common:generateSubscriberId(unsubscription.hubTopic, unsubscription.hubCallback);
    log:printDebug(string `Unsubscription event received for the subscriber ${subscriberId}, hence removing the subscriber from the internal state`);
    lock {
        _ = subscribersCache.removeIfHasKey(subscriberId);
    }
}

isolated function pollForNewUpdates(string subscriberId, websubhub:VerifiedSubscription subscription) returns error? {
    string topic = subscription.hubTopic;
    store:Consumer consumerEp = check conn:createConsumer(subscription);
    websubhub:HubClient clientEp = check new (subscription, {
        httpVersion: http:HTTP_2_0,
        retryConfig: config:delivery.'retry,
        timeout: config:delivery.timeout
    });
    do {
        while true {
            store:Message? message = check consumerEp->receive();
            if !isValidConsumer(subscription.hubTopic, subscriberId) {
                fail error common:InvalidSubscriptionError(
                    string `Subscription or the topic is invalid`, topic = topic, subscriberId = subscriberId
                );
            }
            if message is () {
                continue;
            }
            error? result = notifySubscriber(message, clientEp);
            if result is error {
                check consumerEp->nack(message);
                check result;
            } else {
                check consumerEp->ack(message);
            }
        }
    } on fail var e {
        common:logRecoverableError("Error occurred while sending notification to subscriber", e);
        error? result = consumerEp->close();
        if result is error {
            common:logRecoverableError("Error occurred while gracefully closing message store consumer", result);
        }

        if e is common:InvalidSubscriptionError {
            return;
        }
        if !isValidConsumer(subscription.hubTopic, subscriberId) {
            // In some cases a messaging consumer will be attached to an entity in the message store (queue or topic) and that
            // entity will be removed when unsubscribing, hence it is appropriate to stop the consumer in those cases
            return;
        }

        // If subscription-deleted error received, remove the subscription
        if e is websubhub:SubscriptionDeletedError {
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

isolated function notifySubscriber(store:Message message, websubhub:HubClient clientEp) returns error? {
    websubhub:ContentDistributionMessage notification = check constructContentDistMsg(message);
    _ = check clientEp->notifyContentDistribution(notification);
}

isolated function constructContentDistMsg(store:Message message) returns websubhub:ContentDistributionMessage|error {
    string payloadString = check string:fromBytes(message.payload);
    json payload = check value:fromJsonString(payloadString);
    websubhub:ContentDistributionMessage distributionMsg = {
        content: payload,
        contentType: mime:APPLICATION_JSON,
        headers: message.metadata
    };
    return distributionMsg;
}
