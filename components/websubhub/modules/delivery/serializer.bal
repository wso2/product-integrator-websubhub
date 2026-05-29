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
    // Retrieve the original publisher content-type stored at ingest time.
    // Falls back to application/json for messages already in-flight at deploy time
    // (i.e. messages that pre-date the x-hub-contentType metadata key).
    string contentType = mime:APPLICATION_JSON;
    map<string|string[]>? metadata = message.metadata;
    if metadata is map<string|string[]> && metadata.hasKey(common:CONTENT_TYPE_METADATA_KEY) {
        string|string[] ctValue = metadata.get(common:CONTENT_TYPE_METADATA_KEY);
        contentType = ctValue is string ? ctValue : ctValue[0];
    }

    websubhub:ContentDistributionMessage distributionMsg;
    if contentType == mime:APPLICATION_JSON {
        // JSON path: parse and re-encode so the subscriber receives a structured JSON body.
        string payloadString = check string:fromBytes(message.payload);
        json jsonPayload = check value:fromJsonString(payloadString);
        distributionMsg = {
            content: jsonPayload,
            contentType: mime:APPLICATION_JSON,
            headers: constructDeliveryHeaders(message)
        };
    } else {
        // XML, text/plain, octet-stream, and any other registered content type: forward raw bytes.
        // Using byte[] keeps the runtime type out of Ballerina's json subtype hierarchy,
        // so the HubClient's setPayload call sends raw bytes rather than JSON-serializing
        // the value. (string is a json subtype in Ballerina; byte[] is not.)
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
