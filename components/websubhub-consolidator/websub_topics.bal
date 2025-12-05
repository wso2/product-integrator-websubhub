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

import ballerina/websubhub;

isolated map<websubhub:TopicRegistration> registeredTopicsCache = {};

isolated function refreshTopicCache(websubhub:TopicRegistration[] persistedTopics) {
    foreach var topic in persistedTopics.cloneReadOnly() {
        lock {
            registeredTopicsCache[topic.topic] = topic.cloneReadOnly();
        }
    }
}

isolated function processTopicRegistration(websubhub:TopicRegistration topicRegistration) returns error? {
    lock {
        // add the topic if topic-registration event received
        registeredTopicsCache[topicRegistration.topic] = topicRegistration.cloneReadOnly();
    }
    check processStateUpdate();
}

isolated function processTopicDeregistration(websubhub:TopicDeregistration topicDeregistration) returns error? {
    lock {
        // remove the topic if topic-deregistration event received
        _ = registeredTopicsCache.removeIfHasKey(topicDeregistration.topic);
    }
    check processStateUpdate();
}

isolated function getTopics() returns websubhub:TopicRegistration[] {
    lock {
        return registeredTopicsCache.toArray().cloneReadOnly();
    }
}
