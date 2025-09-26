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

import ballerina/lang.value;
import ballerina/log;
import ballerina/websubhub;

isolated map<websubhub:TopicRegistration> registeredTopicsCache = {};

isolated function refreshTopicCache(websubhub:TopicRegistration[] persistedTopics) {
    log:printDebug("Refreshing topic cache from persisted data", persistedTopicCount = persistedTopics.length());
    foreach var topic in persistedTopics.cloneReadOnly() {
        lock {
            registeredTopicsCache[topic.topic] = topic.cloneReadOnly();
        }
        log:printDebug("Added topic to cache during refresh", topicName = topic.topic);
    }
    log:printDebug("Topic cache refresh completed", totalCachedTopics = registeredTopicsCache.length());
}

isolated function processTopicRegistration(json payload) returns error? {
    log:printDebug("Processing topic registration event");
    websubhub:TopicRegistration registration = check value:cloneWithType(payload);
    log:printDebug("Deserialized topic registration", topicName = registration.topic);
    lock {
        // add the topic if topic-registration event received
        registeredTopicsCache[registration.topic] = registration.cloneReadOnly();
    }
    log:printDebug("Added topic to cache", topicName = registration.topic, totalTopics = registeredTopicsCache.length());
    check processStateUpdate();
    log:printDebug("Topic registration processing completed", topicName = registration.topic);
}

isolated function processTopicDeregistration(json payload) returns error? {
    log:printDebug("Processing topic deregistration event");
    websubhub:TopicDeregistration deregistration = check value:cloneWithType(payload);
    log:printDebug("Deserialized topic deregistration", topicName = deregistration.topic);
    boolean topicRemoved = false;
    lock {
        // remove the topic if topic-deregistration event received
        websubhub:TopicRegistration? removedTopic = registeredTopicsCache.removeIfHasKey(deregistration.topic);
        topicRemoved = removedTopic is websubhub:TopicRegistration;
    }
    log:printDebug("Removed topic from cache", topicName = deregistration.topic, wasRemoved = topicRemoved, totalTopics = registeredTopicsCache.length());
    check processStateUpdate();
    log:printDebug("Topic deregistration processing completed", topicName = deregistration.topic);
}

isolated function getTopics() returns websubhub:TopicRegistration[] {
    websubhub:TopicRegistration[] topics;
    lock {
        topics = registeredTopicsCache.toArray().cloneReadOnly();
    }
    log:printDebug("Retrieved topics from cache", topicCount = topics.length());
    return topics;
}
