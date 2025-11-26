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

import ballerina/websubhub;

import wso2/messaging.store;

type StateUpdateEvent websubhub:TopicRegistration|websubhub:TopicDeregistration|
    websubhub:VerifiedSubscription|websubhub:VerifiedUnsubscription|common:StaleSubscription;

public isolated function addRegsiteredTopic(websubhub:TopicRegistration message) returns error? {
    check updateHubState(message);
}

public isolated function removeRegsiteredTopic(websubhub:TopicDeregistration message) returns error? {
    check updateHubState(message);
}

public isolated function addSubscription(websubhub:VerifiedSubscription message) returns error? {
    check updateHubState(message);
}

public isolated function addStaleSubscription(common:StaleSubscription message) returns error? {
    check updateHubState(message);
}

public isolated function removeSubscription(websubhub:VerifiedUnsubscription message) returns error? {
    check updateHubState(message);
}

isolated function updateHubState(StateUpdateEvent message) returns error? {
    do {
        json jsonData = message.toJson();
        byte[] payload = jsonData.toJsonString().toBytes();
        return produceMessage(config:state.events.topic, payload);
    } on fail error e {
        return error(string `Failed to send updates for hub-state: ${e.message()}`, cause = e);
    }
}

public isolated function addUpdateMessage(string topicName, websubhub:UpdateMessage message, map<string|string[]>? metadata = ())
    returns error? {
    json jsonData = <json>message.content;
    byte[] payload = jsonData.toJsonString().toBytes();
    check produceMessage(topicName, payload, metadata);
}

isolated function produceMessage(string topic, byte[] payload, map<string|string[]>? metadata = ()) returns error? {
    store:Message message = {payload, metadata};
    return (check conn:getMessageProducer(topic))->send(topic, message);
}
