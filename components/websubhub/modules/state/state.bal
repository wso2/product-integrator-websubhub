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

import websubhub.common;

import ballerina/lang.runtime;
import ballerina/websubhub;

isolated map<websubhub:TopicRegistration> registeredTopicsCache = {};

public isolated function isTopicAvailable(string topicName) returns boolean {
    lock {
        return registeredTopicsCache.hasKey(topicName);
    }
}

public isolated function isTopicAvailableWithRetry(string topicName, int maxRetries = 5, decimal retryInterval = 3) returns boolean {
    foreach int _ in 0 ..< maxRetries {
        if isTopicAvailable(topicName) {
            return true;
        }
        runtime:sleep(retryInterval);
    }
    return isTopicAvailable(topicName);
}

public isolated function addTopic(websubhub:TopicRegistration topicReg) {
    lock {
        registeredTopicsCache[topicReg.topic] = topicReg.cloneReadOnly();
    }
}

public isolated function removeTopic(websubhub:TopicDeregistration topicDereg) {
    lock {
        _ = registeredTopicsCache.removeIfHasKey(topicDereg.topic);
    }
}

isolated map<websubhub:VerifiedSubscription> subscribersCache = {};

public isolated function isSubscriptionAvailable(string subscriberId) returns boolean {
    lock {
        return subscribersCache.hasKey(subscriberId);
    }
}

public isolated function getSubscription(string subscriberId) returns websubhub:VerifiedSubscription? {
    lock {
        return subscribersCache[subscriberId].cloneReadOnly();
    }
}

public isolated function addSubscription(websubhub:VerifiedSubscription subscription) {
    string subscriberId = common:generateSubscriberId(subscription.hubTopic, subscription.hubCallback);
    lock {
        subscribersCache[subscriberId] = subscription.cloneReadOnly();
    }
}

public isolated function removeSubscription(websubhub:VerifiedUnsubscription unsubscription) {
    string subscriberId = common:generateSubscriberId(unsubscription.hubTopic, unsubscription.hubCallback);
    lock {
        _ = subscribersCache.removeIfHasKey(subscriberId);
    }
}
