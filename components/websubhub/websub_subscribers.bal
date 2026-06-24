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
import websubhub.delivery;
import websubhub.state;

import ballerina/log;
import ballerina/websubhub;

const SUBSCRIPTION_STALE_STATE = "stale";

isolated function processWebsubSubscriptionsSnapshotState(websubhub:VerifiedSubscription[] subscriptions) returns error? {
    log:printDebug("Received latest state-snapshot for websub subscriptions", newState = subscriptions);
    foreach websubhub:VerifiedSubscription subscription in subscriptions {
        check processSubscription(subscription);
    }
}

isolated function processSubscription(websubhub:VerifiedSubscription subscription) returns error? {
    log:printDebug("Subscription event received",
            topic = subscription.hubTopic, callback = subscription.hubCallback, 'type = "state-update", serverId = config:serverId);
    string subscriberId = common:generateSubscriberId(subscription.hubTopic, subscription.hubCallback);
    websubhub:VerifiedSubscription? existingSubscription = state:getSubscription(subscriberId);
    boolean isFreshSubscription = existingSubscription is ();
    boolean isRenewingStaleSubscription = false;
    if existingSubscription is websubhub:VerifiedSubscription {
        isRenewingStaleSubscription = existingSubscription.hasKey(common:SUBSCRIPTION_STATUS) && existingSubscription.get(common:SUBSCRIPTION_STATUS) is SUBSCRIPTION_STALE_STATE;
    }

    boolean isMarkingSubscriptionAsStale = subscription.hasKey(common:SUBSCRIPTION_STATUS) && subscription.get(common:SUBSCRIPTION_STATUS) is SUBSCRIPTION_STALE_STATE;
    // add the subscriber if subscription event received for a new subscription or a stale subscription, when renewing a stale subscription
    if isFreshSubscription || isRenewingStaleSubscription || isMarkingSubscriptionAsStale {
        state:addSubscription(subscription);
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

    error? result = delivery:distributeContentNotification(subscription.cloneReadOnly());
    if result is error {
        common:logRecoverableError("Error occurred while starting the async dispatcher for subscription", result, topic = subscription.hubTopic, callback = subscription.hubCallback);
    }
}

isolated function processUnsubscription(websubhub:VerifiedUnsubscription unsubscription) returns error? {
    log:printDebug("Unsubscription event received, hence removing the subscriber from the internal state",
            topic = unsubscription.hubTopic, callback = unsubscription.hubCallback, 'type = "state-update", serverId = config:serverId);
    state:removeSubscription(unsubscription);
}
