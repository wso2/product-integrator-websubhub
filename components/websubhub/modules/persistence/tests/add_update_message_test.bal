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
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

// Unit tests for the empty-payload guard in addUpdateMessage.
//
// An empty body must NOT be persisted: the broker adapter (xlibb/solace 0.4.1) throws on receive of
// a zero-length message ("Cannot read the array length because 'values' is null"), poisoning the
// queue. addUpdateMessage therefore returns early for empty/nil content — BEFORE produceMessage is
// reached — so these tests neither contact a broker nor raise an error.

import ballerina/test;
import ballerina/websubhub;

const TOPIC = "test-topic";

@test:Config {}
function testAddUpdateMessage_EmptyString_Skipped() returns error? {
    websubhub:UpdateMessage msg = {
        msgType: websubhub:PUBLISH,
        hubTopic: TOPIC,
        contentType: "text/plain",
        content: ""
    };
    error? result = addUpdateMessage(TOPIC, msg);
    test:assertTrue(result is (), "empty text/plain body must be skipped (return () without producing)");
}

@test:Config {}
function testAddUpdateMessage_EmptyBytes_Skipped() returns error? {
    byte[] empty = [];
    websubhub:UpdateMessage msg = {
        msgType: websubhub:PUBLISH,
        hubTopic: TOPIC,
        contentType: "application/octet-stream",
        content: empty
    };
    error? result = addUpdateMessage(TOPIC, msg);
    test:assertTrue(result is (), "empty octet-stream body must be skipped (the empty-payload guard)");
}

// NOTE on nil content: in Ballerina `() is json` is true, so nil content matches the `json` arm and
// serializes to the 4-byte string "null" (not empty) — it is NOT caught by the empty-payload guard.
// That is pre-existing behaviour and out of scope for this guard, which targets zero-length payloads.
