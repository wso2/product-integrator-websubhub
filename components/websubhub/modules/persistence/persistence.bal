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

import ballerina/log;
import ballerina/websubhub;
import ballerinax/kafka;

public isolated function addRegsiteredTopic(websubhub:TopicRegistration message) returns error? {
    log:printDebug("Adding registered topic to persistence", topic = message.topic);
    check updateHubState(message);
    log:printDebug("Registered topic added to persistence successfully", topic = message.topic);
}

public isolated function removeRegsiteredTopic(websubhub:TopicDeregistration message) returns error? {
    log:printDebug("Removing registered topic from persistence", topic = message.topic);
    check updateHubState(message);
    log:printDebug("Registered topic removed from persistence successfully", topic = message.topic);
}

public isolated function addSubscription(websubhub:VerifiedSubscription message) returns error? {
    log:printDebug("Adding subscription to persistence", topic = message.hubTopic, callback = message.hubCallback);
    check updateHubState(message);
    log:printDebug("Subscription added to persistence successfully", topic = message.hubTopic, callback = message.hubCallback);
}

public isolated function addStaleSubscription(common:StaleSubscription message) returns error? {
    log:printDebug("Adding stale subscription to persistence", topic = message.hubTopic, callback = message.hubCallback);
    check updateHubState(message);
    log:printDebug("Stale subscription added to persistence successfully", topic = message.hubTopic, callback = message.hubCallback);
}

public isolated function removeSubscription(websubhub:VerifiedUnsubscription message) returns error? {
    log:printDebug("Removing subscription from persistence", topic = message.hubTopic, callback = message.hubCallback);
    check updateHubState(message);
    log:printDebug("Subscription removed from persistence successfully", topic = message.hubTopic, callback = message.hubCallback);
}

isolated function updateHubState(websubhub:TopicRegistration|websubhub:TopicDeregistration|
                                websubhub:VerifiedSubscription|websubhub:VerifiedUnsubscription message) returns error? {
    log:printDebug("Converting message to JSON for hub state update");
    json jsonData = message.toJson();
    log:printDebug("Sending hub state update to Kafka", stateTopic = config:state.events.topic, messageSize = jsonData.toJsonString().length());
    do {
        check produceKafkaMessage(config:state.events.topic, jsonData);
        log:printDebug("Hub state update sent to Kafka successfully", stateTopic = config:state.events.topic);
    } on fail error e {
        log:printDebug("Failed to send hub state update to Kafka", stateTopic = config:state.events.topic, errorMsg = e.message());
        return error(string `Failed to send updates for hub-state: ${e.message()}`, cause = e);
    }
}

public isolated function addUpdateMessage(string topicName, websubhub:UpdateMessage message,
        map<string|string[]> headers = {}) returns error? {
    log:printDebug("Processing content update message", topic = topicName, contentType = message.contentType, headerCount = headers.length());
    json payload = <json>message.content;
    log:printDebug("Converted content to JSON for Kafka", topic = topicName, payloadSize = payload.toJsonString().length());
    check produceKafkaMessage(topicName, payload);
    log:printDebug("Content update message sent to Kafka successfully", topic = topicName);
}

isolated function produceKafkaMessage(string topicName, json payload,
        map<string|string[]> headers = {}) returns error? {
    log:printDebug("Preparing Kafka producer message", topic = topicName, hasHeaders = headers.length() > 0);
    kafka:AnydataProducerRecord message = getProducerMsg(topicName, payload, headers);
    log:printDebug("Sending message to Kafka producer", topic = topicName);
    check conn:statePersistProducer->send(message);
    log:printDebug("Message sent to Kafka, flushing producer", topic = topicName);
    check conn:statePersistProducer->'flush();
    log:printDebug("Kafka producer flushed successfully", topic = topicName);
}

isolated function getProducerMsg(string topic, json payload,
        map<string|string[]> headers) returns kafka:AnydataProducerRecord {
    log:printDebug("Converting JSON payload to bytes", topic = topic);
    byte[] value = payload.toJsonString().toBytes();
    log:printDebug("Creating Kafka producer record", topic = topic, valueSize = value.length(), headerCount = headers.length());
    log:printDebug("Kafka producer record created", topic = topic, hasHeaders = headers.length() > 0);
    return headers.length() == 0 ? {topic, value} : {topic, value, headers};
}
