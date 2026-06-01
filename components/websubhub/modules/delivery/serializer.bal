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

import ballerina/lang.value;
import ballerina/mime;
import ballerina/websubhub;

import wso2/messagestore.api as storeapi;

isolated function constructContentDistMsg(storeapi:Message message) returns websubhub:ContentDistributionMessage|error {
    // Recover the original publisher Content-Type stored at ingest as a broker user-property.
    // Fall back to application/json for messages stored before this feature shipped (the key is absent),
    // preserving the legacy behaviour for in-flight messages.
    string contentType = mime:APPLICATION_JSON;
    map<string|string[]>? metadata = message.metadata;
    if metadata is map<string|string[]> && metadata.hasKey(common:CONTENT_TYPE_METADATA_KEY) {
        string|string[] ctValue = metadata.get(common:CONTENT_TYPE_METADATA_KEY);
        contentType = ctValue is string ? ctValue : (ctValue.length() > 0 ? ctValue[0] : mime:APPLICATION_JSON);
    }

    websubhub:ContentDistributionMessage distributionMsg;
    if contentType == mime:APPLICATION_JSON {
        // JSON path (unchanged): parse and re-encode so the subscriber receives a structured JSON body.
        string payloadString = check string:fromBytes(message.payload);
        json payload = check value:fromJsonString(payloadString);
        distributionMsg = {
            content: payload,
            contentType: mime:APPLICATION_JSON,
            headers: constructDeliveryHeaders(message)
        };
    } else {
        // XML / text/plain / octet-stream / any other registered type: forward the raw bytes.
        // content MUST be the byte[] payload, never a decoded string: string is a json subtype in
        // Ballerina, so the HubClient would JSON-serialize it (adding quotes). byte[] is sent as-is
        // by setPayload (see design Gotcha G2).
        distributionMsg = {
            content: message.payload,
            contentType,
            headers: constructDeliveryHeaders(message)
        };
    }
    return distributionMsg;
}

isolated function constructDeliveryHeaders(storeapi:Message message) returns map<string|string[]>? {
    string? messageId = message.id;
    if messageId is () {
        return message.metadata;
    }

    map<string|string[]>? metadata = message.metadata;
    if metadata is () {
        return {
            "x-hub-messageId": messageId
        };
    }
    metadata["x-hub-messageId"] = messageId;
    return metadata;
}
