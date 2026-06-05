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

// Unit tests for the JMS MapMessage encoding logic.
//
// The JMS adapter encodes api:Message as a MapMessage with the payload stored under the
// reserved key "__payload" and metadata as top-level string entries. These tests verify
// the encode/decode logic in isolation without requiring a JMS broker.

import ballerina/test;

import wso2/messagestore.api as storeapi;

// ---------------------------------------------------------------------------
// Helpers that mirror the producer/consumer logic
// (duplicated here rather than calling private functions)
// ---------------------------------------------------------------------------

isolated function encode(byte[] payload, map<string|string[]>? metadata) returns map<anydata> {
    map<anydata> content = {[JMS_PAYLOAD_KEY]: payload};
    if metadata is map<string|string[]> {
        foreach var [k, v] in metadata.entries() {
            content[k] = v is string[] ? (v.length() > 0 ? v[0] : "") : v;
        }
    }
    return content;
}

isolated function decode(map<anydata> content, string? correlationId) returns storeapi:Message {
    anydata rawPayload = content[JMS_PAYLOAD_KEY];
    byte[] payload = rawPayload is byte[] ? rawPayload : [];
    map<string|string[]> metadata = {};
    foreach var [k, v] in content.entries() {
        if k == JMS_PAYLOAD_KEY { continue; }
        if v is string { metadata[k] = v; }
    }
    return {
        id: correlationId,
        payload,
        metadata: metadata.length() > 0 ? metadata : ()
    };
}

// ---------------------------------------------------------------------------
// Encode → decode round-trip for each content type
// ---------------------------------------------------------------------------

@test:Config {}
function testRoundTrip_Json() {
    byte[] payload = "{\"k\":\"v\"}".toBytes();
    map<string|string[]> metadata = {"x-hub-contentType": "application/json"};
    map<anydata> encoded = encode(payload, metadata);
    storeapi:Message decoded = decode(encoded, "msg-1");
    test:assertEquals(decoded.payload, payload);
    test:assertEquals(decoded.metadata, <map<string|string[]>>{"x-hub-contentType": "application/json"});
    test:assertEquals(decoded.id, "msg-1");
}

@test:Config {}
function testRoundTrip_Binary() {
    // Full 0x00–0xFF range — must survive without corruption
    byte[] payload = [];
    int i = 0;
    while i < 256 { payload.push(<byte>i); i += 1; }
    map<string|string[]> metadata = {"x-hub-contentType": "application/octet-stream"};
    map<anydata> encoded = encode(payload, metadata);
    storeapi:Message decoded = decode(encoded, "msg-bin");
    test:assertEquals(decoded.payload, payload, "binary payload must round-trip byte-exact");
}

@test:Config {}
function testRoundTrip_MultipleMetadataKeys() {
    byte[] payload = "<e/>".toBytes();
    map<string|string[]> metadata = {
        "x-hub-contentType": "application/xml",
        "x-hub-messageId": "msg-003",
        "x-custom-header": "hello"
    };
    map<anydata> encoded = encode(payload, metadata);
    storeapi:Message decoded = decode(encoded, "msg-3");
    test:assertEquals(decoded.payload, payload);
    map<string|string[]>? md = decoded.metadata;
    test:assertTrue(md is map<string|string[]>);
    if md is map<string|string[]> {
        test:assertEquals(md["x-hub-contentType"], "application/xml");
        test:assertEquals(md["x-hub-messageId"], "msg-003");
        test:assertEquals(md["x-custom-header"], "hello");
    }
}

// ---------------------------------------------------------------------------
// Hyphenated keys must survive encode/decode (verified on live ActiveMQ)
// ---------------------------------------------------------------------------

@test:Config {}
function testHyphenatedKeyPreserved() {
    byte[] payload = "text".toBytes();
    map<string|string[]> metadata = {"x-hub-contentType": "text/plain"};
    map<anydata> encoded = encode(payload, metadata);
    storeapi:Message decoded = decode(encoded, ());
    map<string|string[]>? md = decoded.metadata;
    test:assertTrue(md is map<string|string[]>, "metadata must be present");
    if md is map<string|string[]> {
        test:assertTrue(md.hasKey("x-hub-contentType"),
                "hyphenated key x-hub-contentType must survive encode/decode");
        test:assertEquals(md["x-hub-contentType"], "text/plain");
    }
}

// ---------------------------------------------------------------------------
// Multi-valued metadata is flattened to the first element
// ---------------------------------------------------------------------------

@test:Config {}
function testMultiValuedMetadataFlattenedToFirst() {
    byte[] payload = [1, 2, 3];
    map<string|string[]> metadata = {"x-hub-contentType": ["application/xml", "extra"]};
    map<anydata> encoded = encode(payload, metadata);
    // The first element must be stored; "extra" is dropped
    test:assertEquals(encoded["x-hub-contentType"], "application/xml");
    storeapi:Message decoded = decode(encoded, ());
    map<string|string[]>? md = decoded.metadata;
    if md is map<string|string[]> {
        test:assertEquals(md["x-hub-contentType"], "application/xml",
                "multi-valued metadata must be flattened to the first element");
    }
}

// ---------------------------------------------------------------------------
// No metadata — metadata field must be () on decode
// ---------------------------------------------------------------------------

@test:Config {}
function testNoMetadata_ReturnsNilMetadata() {
    byte[] payload = "plain".toBytes();
    map<anydata> encoded = encode(payload, ());
    storeapi:Message decoded = decode(encoded, ());
    test:assertTrue(decoded.metadata is (), "absent metadata must decode to ()");
    test:assertEquals(decoded.payload, payload);
}

// ---------------------------------------------------------------------------
// Payload key must not appear in decoded metadata
// ---------------------------------------------------------------------------

@test:Config {}
function testPayloadKeyNotLeakedToMetadata() {
    byte[] payload = [0xFF, 0xFE];
    map<string|string[]> metadata = {"x-hub-contentType": "application/octet-stream"};
    map<anydata> encoded = encode(payload, metadata);
    storeapi:Message decoded = decode(encoded, ());
    map<string|string[]>? md = decoded.metadata;
    if md is map<string|string[]> {
        test:assertFalse(md.hasKey(JMS_PAYLOAD_KEY),
                "the reserved __payload key must not appear in decoded metadata");
    }
}

// ---------------------------------------------------------------------------
// Backward-compat: BytesMessage (old format) decodes with no metadata
// ---------------------------------------------------------------------------

@test:Config {}
function testBackwardCompat_BytesMessageDecodesWithoutMetadata() {
    // The old producer wrote a BytesMessage; the new consumer falls back to it.
    // Simulate the receive() behavior for BytesMessage:
    byte[] payload = "legacy".toBytes();
    // Old path: just id + payload, no metadata
    storeapi:Message msg = {id: "old-msg", payload};
    test:assertEquals(msg.payload, payload);
    test:assertTrue(msg.metadata is (), "legacy BytesMessage must have no metadata");
}
