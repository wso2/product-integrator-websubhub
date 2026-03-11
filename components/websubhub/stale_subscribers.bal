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
import websubhub.persistence as persist;

import ballerina/http;
import ballerina/log;
import ballerina/websubhub;
import ballerina/lang.runtime;
import websubhub.config;

isolated map<common:StaleSubscription> staleSubscribersCache = {};

isolated function addStaleSubscription(common:StaleSubscription subscription) {
    string subscriberId = common:generateSubscriberId(subscription.hubTopic, subscription.hubCallback);
    lock {
        staleSubscribersCache[subscriberId] = subscription.cloneReadOnly();
    }
}

isolated function removeStaleSubscription(common:StaleSubscription subscription) {
    string subscriberId = common:generateSubscriberId(subscription.hubTopic, subscription.hubCallback);
    lock {
        _ = staleSubscribersCache.removeIfHasKey(subscriberId);
    }
}

isolated function getStaleSubscribers() returns common:StaleSubscription[] {
    lock {
        return staleSubscribersCache.toArray().cloneReadOnly();
    }
}

function refreshStaleSubscribers() returns error? {
    while true {
        foreach var staleSubscriber in getStaleSubscribers() {
            string subscriberId = common:generateSubscriberId(staleSubscriber.hubTopic, staleSubscriber.hubCallback);

            http:Response|error pingResponse = pingSubscriber(staleSubscriber);
            if pingResponse is error {
                log:printWarn("Error occurred while pinging the subscriber", subscriberId = subscriberId, 'error = pingResponse);
                continue;
            }

            int statusCode = pingResponse.statusCode;
            if statusCode == http:STATUS_GONE {
                removeSubscriptionPermanently(staleSubscriber);
                continue;
            }

            if 200 <= statusCode && statusCode < 300 {
                _ = staleSubscriber.removeIfHasKey(common:SUBSCRIPTION_STATUS);
                error? persistResult = persist:addSubscription(staleSubscriber);
                if persistResult is error {
                    string errorMessage = string `Failed to register subscription for topic ${staleSubscriber.hubTopic} and subscriber ${staleSubscriber.hubCallback}: ${persistResult.message()}`;
                    common:logRecoverableError(errorMessage, persistResult);
                } else {
                    removeStaleSubscription(staleSubscriber);
                }
                continue;
            }
        }
        runtime:sleep(config:server.staleSubscriptionRefreshInterval);
    }
}

// todo: implement this properly by improving the `websubhub:HubClient`
isolated function pingSubscriber(websubhub:VerifiedSubscription subscriber) returns http:Response|error {
    http:Client subscriberEp = check new(
        subscriber.hubCallback, secureSocket = config:delivery.secureSocket, timeout = config:delivery.timeout
    );
    return subscriberEp->/;
}

isolated function removeSubscriptionPermanently(websubhub:VerifiedSubscription subcription) {
    websubhub:VerifiedUnsubscription unsubscription = {
        hubMode: "unsubscribe",
        hubTopic: subcription.hubTopic,
        hubCallback: subcription.hubCallback,
        hubSecret: subcription.hubSecret
    };

    error? subscriptionDeletion = admin:deleteSubscription(subcription);
    if subscriptionDeletion is error {
        common:logRecoverableError(
                "Error occurred while removing the subscription", subscriptionDeletion, subscription = unsubscription);
    }

    error? persistResult = persist:removeSubscription(unsubscription);
    if persistResult is error {
        common:logRecoverableError(
                "Error occurred while removing the subscription", persistResult, subscription = unsubscription);
    }
}
