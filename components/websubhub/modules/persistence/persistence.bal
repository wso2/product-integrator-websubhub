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
    // Serialize content to bytes preserving the original type.
    // The content-type is stored as a Solace user property so subscribers receive
    // the correct Content-Type header regardless of whether the publisher sent JSON,
    // XML, plain text, or raw bytes.
    byte[] payload = [];
    // effectiveContentType tracks the MIME type that matches the bytes we actually stored.
    // It equals message.contentType for byte[], string, and xml branches.
    // For the json branch it is always application/json regardless of message.contentType,
    // because map<string|string[]> from form-encoded publishes also lands in the json branch
    // (map<string[]> <: json) — the bytes are JSON-serialised, so the stored type must be
    // application/json. Storing "application/x-www-form-urlencoded" would cause the
    // HubClient's retrieveRequestPayload to attempt <map<string>>byte[] at delivery time,
    // which panics the polling strand silently (Ballerina runtime type-cast panic).
    string effectiveContentType = message.contentType;
    match message.content {
        // IMPORTANT: byte[] and string must be checked BEFORE json.
        // In Ballerina's type system both string and byte[] are subtypes of json
        // (string <: json; byte <: int <: json, so byte[] <: json[]).
        // Checking json first would therefore consume all four types and serialize
        // everything with toJsonString(), adding unwanted quotes around text and
        // converting binary to a JSON integer array.
        var c if c is byte[] => {
            payload = c;
            // effectiveContentType unchanged — message.contentType is the correct MIME type
        }
        var c if c is string => {
            payload = c.toBytes();
            // effectiveContentType unchanged
        }
        var c if c is xml => {
            payload = c.toString().toBytes();
            // effectiveContentType unchanged
        }
        var c if c is json => {
            // Pure JSON values (numbers, booleans, objects, arrays) that are not
            // string or byte[] — includes map<string|string[]> from form-encoded publishes.
            // The bytes stored are always valid JSON, so pin the effective type to JSON.
            payload = c.toJsonString().toBytes();
            effectiveContentType = mime:APPLICATION_JSON;
        }
        _ => {
            // content is () — nothing to deliver
            return;
        }
    }

    // Inject the effective content-type into metadata so it survives the broker round-trip.
    // Construct a fresh map<string|string[]> rather than cloning — the runtime type of the
    // incoming `metadata` value is map<string[]> (from getMetadata in hub_service.bal), so
    // cloning preserves that inherent type and rejects a bare string insertion at runtime.
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
