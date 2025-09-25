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
import websubhub.consolidator.config;
import websubhub.consolidator.connections as conn;

import ballerina/log;

public isolated function persistWebsubEventsSnapshot(common:SystemStateSnapshot systemStateSnapshot) returns error? {
    log:printDebug("Persisting system state snapshot", topicCount = systemStateSnapshot.topics.length(), subscriptionCount = systemStateSnapshot.subscriptions.length());
    json payload = systemStateSnapshot.toJson();
    check produceKafkaMessage(config:state.snapshot.topic, payload);
    log:printDebug("System state snapshot persisted successfully", targetTopic = config:state.snapshot.topic);
}

isolated function produceKafkaMessage(string topicName, json payload) returns error? {
    log:printDebug("Producing Kafka message", targetTopic = topicName);
    byte[] serializedContent = payload.toJsonString().toBytes();
    check conn:statePersistProducer->send({topic: topicName, value: serializedContent});
    check conn:statePersistProducer->'flush();
    log:printDebug("Message successfully sent to Kafka", topic = topicName);
}
