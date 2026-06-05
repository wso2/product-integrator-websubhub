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

import websubhub.config;
import websubhub.state;

import ballerina/log;
import ballerina/websubhub;

isolated function processWebsubTopicsSnapshotState(websubhub:TopicRegistration[] topics) {
    log:printDebug("Received latest state-snapshot for websub topics", newState = topics);
    foreach websubhub:TopicRegistration topicReg in topics {
        processTopicRegistration(topicReg);
    }
}

isolated function processTopicRegistration(websubhub:TopicRegistration topicRegistration) {
    log:printDebug(string `Topic registration event received for topic ${topicRegistration.topic}, hence adding the topic to the internal state`,
            'type = "state-update", serverId = config:serverId);
    // add the topic if topic is not already available in the hub
    if state:isTopicAvailable(topicRegistration.topic) {
        return;
    }
    state:addTopic(topicRegistration);
}

isolated function processTopicDeregistration(websubhub:TopicDeregistration topicDeregistration) {
    log:printDebug(string `Topic deregistration event received for topic ${topicDeregistration.topic}, hence removing the topic from the internal state`,
            'type = "state-update", serverId = config:serverId);
    state:removeTopic(topicDeregistration);
}
