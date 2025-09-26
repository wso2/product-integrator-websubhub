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

import websubhub.consolidator.common;

import ballerina/log;
import ballerina/websubhub;

isolated map<websubhub:VerifiedSubscription> subscribersCache = {};

isolated function refreshSubscribersCache(websubhub:VerifiedSubscription[] persistedSubscribers) {
    log:printDebug("Refreshing subscribers cache from persisted data", persistedSubscriberCount = persistedSubscribers.length());
    foreach var subscriber in persistedSubscribers {
        string groupName = common:generatedSubscriberId(subscriber.hubTopic, subscriber.hubCallback);
        lock {
            subscribersCache[groupName] = subscriber.cloneReadOnly();
        }
        log:printDebug("Added subscriber to cache during refresh", subscriberId = groupName, topic = subscriber.hubTopic, callback = subscriber.hubCallback);
    }
    log:printDebug("Subscribers cache refresh completed", totalCachedSubscribers = subscribersCache.length());
}

isolated function processSubscription(json payload) returns error? {
    log:printDebug("Processing subscription event");
    websubhub:VerifiedSubscription subscription = check payload.cloneWithType(websubhub:VerifiedSubscription);
    string subscriberId = common:generatedSubscriberId(subscription.hubTopic, subscription.hubCallback);
    log:printDebug("Deserialized subscription", subscriberId = subscriberId, topic = subscription.hubTopic, callback = subscription.hubCallback);
    boolean subscriptionAdded = false;
    lock {
        // add the subscriber if subscription event received
        if !subscribersCache.hasKey(subscriberId) {
            subscribersCache[subscriberId] = subscription.cloneReadOnly();
            subscriptionAdded = true;
            log:printDebug("Added new subscription to cache", subscriberId = subscriberId, totalSubscriptions = subscribersCache.length());
        } else {
            log:printDebug("Subscription already exists in cache, skipping", subscriberId = subscriberId);
        }
    }
    check processStateUpdate();
    log:printDebug("Subscription processing completed", subscriberId = subscriberId, wasAdded = subscriptionAdded);
}

isolated function processUnsubscription(json payload) returns error? {
    log:printDebug("Processing unsubscription event");
    websubhub:VerifiedUnsubscription unsubscription = check payload.cloneWithType(websubhub:VerifiedUnsubscription);
    string subscriberId = common:generatedSubscriberId(unsubscription.hubTopic, unsubscription.hubCallback);
    log:printDebug("Deserialized unsubscription", subscriberId = subscriberId, topic = unsubscription.hubTopic, callback = unsubscription.hubCallback);
    lock {
        // remove the subscriber if the unsubscription event received
        websubhub:VerifiedSubscription? removedSubscription = subscribersCache.removeIfHasKey(subscriberId);
        boolean subscriptionRemoved = removedSubscription is websubhub:VerifiedSubscription;
        log:printDebug("Removed subscription from cache", subscriberId = subscriberId, wasRemoved = subscriptionRemoved, totalSubscriptions = subscribersCache.length());
    }
    check processStateUpdate();
    log:printDebug("Unsubscription processing completed", subscriberId = subscriberId);
}

isolated function getSubscriptions() returns websubhub:VerifiedSubscription[] {
    websubhub:VerifiedSubscription[] subscriptions;
    lock {
        subscriptions = subscribersCache.toArray().cloneReadOnly();
    }
    log:printDebug("Retrieved subscriptions from cache", subscriptionCount = subscriptions.length());
    return subscriptions;
}
