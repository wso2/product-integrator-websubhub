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
import ballerina/mime;
import ballerina/websubhub;

import wso2/messagestore.api as storeapi;

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

public isolated function addUpdateMessage(string topicName, websubhub:UpdateMessage message, map<string|string[]>? metadata = (), string? messageId = ())
    returns error? {
    // Serialize the published content to bytes preserving its original type, and record the
    // effective Content-Type as a message-store user-property so subscribers receive the correct
    // `Content-Type` header regardless of whether the publisher sent JSON, XML, text, or raw bytes.
    byte[] payload = [];
    // effectiveContentType tracks the MIME type that matches the bytes we actually store.
    // It equals message.contentType for the byte[], string, and xml arms. For the json arm it is
    // always application/json: a `map<string|string[]>` from an application/x-www-form-urlencoded
    // publish also lands in the json arm (map<string[]> <: json) and is JSON-serialized here, so
    // storing "application/x-www-form-urlencoded" would make the HubClient attempt <map<string>>byte[]
    // at delivery time and panic the delivery strand (see design Gotcha G3).
    string effectiveContentType = message.contentType;
    match message.content {
        // IMPORTANT (Gotcha G1): byte[] and string MUST be matched before json. In Ballerina both
        // string and byte[] are subtypes of json (string <: json; byte <: int <: json, so byte[] <: json[]),
        // so a leading `c is json` arm would consume all four types and JSON-serialize everything —
        // quoting text and turning binary into a JSON integer array.
        var c if c is byte[] => {
            payload = c;
        }
        var c if c is string => {
            payload = c.toBytes();
        }
        var c if c is xml => {
            payload = c.toString().toBytes();
        }
        var c if c is json => {
            payload = c.toJsonString().toBytes();
            effectiveContentType = mime:APPLICATION_JSON;
        }
        _ => {
            // content is () — nothing to deliver (e.g. an EVENT/thin-ping with no body)
            return;
        }
    }

    // Guard against empty payloads. A zero-length message cannot be persisted safely: the broker
    // adapter (xlibb/solace 0.4.1) throws on receive of a zero-length message ("Cannot read the
    // array length because 'values' is null"), which poisons the queue. There is nothing to deliver
    // for an empty body, so treat it like nil content and skip.
    if payload.length() == 0 {
        log:printWarn("Skipping update message with empty payload — nothing to deliver",
                topic = topicName, contentType = message.contentType);
        return;
    }

    // Inject the effective Content-Type into the metadata map that is round-tripped through the broker.
    // Construct a fresh map<string|string[]> rather than cloning the incoming value: getMetadata() in
    // hub_service.bal yields a map<string[]>, whose inherent type rejects a bare string insertion at
    // runtime (InherentTypeViolation — Gotcha G4).
    map<string|string[]> enrichedMetadata = {};
    if metadata is map<string|string[]> {
        foreach var [k, v] in metadata.entries() {
            enrichedMetadata[k] = v;
        }
    }
    enrichedMetadata[common:CONTENT_TYPE_METADATA_KEY] = effectiveContentType;

    check produceMessage(topicName, payload, enrichedMetadata, messageId);
}

isolated function produceMessage(string topic, byte[] payload, map<string|string[]>? metadata = (), string? messageId = ()) returns error? {
    storeapi:Message message = {id: messageId, payload, metadata};
    return (check conn:getMessageProducer(topic))->send(topic, message);
}
