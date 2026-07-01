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

// Unit tests for `buildContentDistMsg` — converts a stored storeapi:Message back into a
// websubhub:ContentDistributionMessage, choosing the delivery Content-Type from the
// `x-hub-contentType` metadata key written at ingest. The `contentPassthrough` parameter selects
// the mode under test directly (production sources it from `config:delivery.contentPassthrough`):
//
//   - contentPassthrough = false → legacy content-aware: JSON is parsed/re-encoded; other types
//     are forwarded as raw bytes.
//   - contentPassthrough = true  → content-unaware passthrough: ALL types (including JSON) are
//     forwarded as the raw stored bytes with the recorded Content-Type, no parsing.
//
// Ballerina type-system note (why these tests matter):
//   - string <: json and byte[] <: json[]. For any passthrough/non-JSON case the delivered
//     `content` MUST be the raw byte[] payload — a decoded string would be re-JSON-serialized by
//     the HubClient (adding quotes). The binary and text tests below lock that in.
//   - An absent x-hub-contentType key must fall back to application/json (backward compatibility
//     for messages stored before this feature shipped).

import websubhub.common;

import ballerina/mime;
import ballerina/test;
import ballerina/websubhub;

import wso2/messagestore.api as storeapi;

// Builds a storeapi:Message with the given payload bytes and optional metadata.
isolated function makeStoredMessage(byte[] payload, map<string|string[]>? metadata) returns storeapi:Message {
    return {payload, metadata};
}

isolated function assertNoError(websubhub:ContentDistributionMessage|error result, string label) {
    if result is error {
        test:assertFail(string `${label}: unexpected error — ${result.message()}`);
    }
}

// ===========================================================================
// Legacy content-aware mode (contentPassthrough = false)
// ===========================================================================

// ---------------------------------------------------------------------------
// application/json — explicit metadata key
// ---------------------------------------------------------------------------
@test:Config {}
function testConstructContentDist_Json_WithMetadataKey() returns error? {
    json payload = {"event": "order.created", "id": 42};
    byte[] payloadBytes = payload.toJsonString().toBytes();
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: mime:APPLICATION_JSON};

    websubhub:ContentDistributionMessage|error result = buildContentDistMsg(makeStoredMessage(payloadBytes, metadata), false);
    assertNoError(result, "JSON with metadata key");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, mime:APPLICATION_JSON);
    test:assertEquals(dist.content, payload, "content must be the parsed JSON value");
}

// ---------------------------------------------------------------------------
// application/json — absent metadata key (backward compat for legacy messages)
// ---------------------------------------------------------------------------
@test:Config {}
function testConstructContentDist_Json_NoMetadata_BackwardCompat() returns error? {
    json payload = {"event": "legacy"};
    byte[] payloadBytes = payload.toJsonString().toBytes();

    websubhub:ContentDistributionMessage|error result = buildContentDistMsg(makeStoredMessage(payloadBytes, ()), false);
    assertNoError(result, "JSON backward compat (no metadata)");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, mime:APPLICATION_JSON);
    test:assertEquals(dist.content, payload);
}

// ---------------------------------------------------------------------------
// application/json — metadata present but key absent → still JSON
// ---------------------------------------------------------------------------
@test:Config {}
function testConstructContentDist_Json_MetadataPresentKeyAbsent() returns error? {
    json payload = 99;
    byte[] payloadBytes = payload.toJsonString().toBytes();
    map<string|string[]> metadata = {"x-hub-messageId": "abc"};

    websubhub:ContentDistributionMessage|error result = buildContentDistMsg(makeStoredMessage(payloadBytes, metadata), false);
    assertNoError(result, "JSON — metadata present, key absent");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, mime:APPLICATION_JSON);
    test:assertEquals(dist.content, payload);
}

// ---------------------------------------------------------------------------
// application/xml — raw bytes forwarded unchanged
// ---------------------------------------------------------------------------
@test:Config {}
function testConstructContentDist_Xml_PassThrough() returns error? {
    byte[] payloadBytes = "<root><item>hello</item></root>".toBytes();
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: mime:APPLICATION_XML};

    websubhub:ContentDistributionMessage|error result = buildContentDistMsg(makeStoredMessage(payloadBytes, metadata), false);
    assertNoError(result, "application/xml passthrough");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, mime:APPLICATION_XML);
    test:assertEquals(dist.content, payloadBytes, "XML must be forwarded as raw bytes, not parsed");
}

// ---------------------------------------------------------------------------
// text/plain — raw bytes forwarded (NOT a decoded string → no JSON quoting)
// ---------------------------------------------------------------------------
@test:Config {}
function testConstructContentDist_TextPlain_PassThrough() returns error? {
    byte[] payloadBytes = "Hello, subscriber!".toBytes();
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: mime:TEXT_PLAIN};

    websubhub:ContentDistributionMessage|error result = buildContentDistMsg(makeStoredMessage(payloadBytes, metadata), false);
    assertNoError(result, "text/plain passthrough");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, mime:TEXT_PLAIN);
    test:assertEquals(dist.content, payloadBytes, "text must be byte[] so HubClient sends it unquoted");
}

// ---------------------------------------------------------------------------
// text/plain — multibyte UTF-8 (exact byte fidelity)
// ---------------------------------------------------------------------------
@test:Config {}
function testConstructContentDist_TextPlain_MultibyteUtf8() returns error? {
    byte[] payloadBytes = "héllo wörld 日本語 — 149.99 CHF".toBytes();
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: mime:TEXT_PLAIN};

    websubhub:ContentDistributionMessage|error result = buildContentDistMsg(makeStoredMessage(payloadBytes, metadata), false);
    assertNoError(result, "text/plain multibyte UTF-8");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, mime:TEXT_PLAIN);
    test:assertEquals(dist.content, payloadBytes, "multibyte UTF-8 bytes must be preserved exactly");
}

// ---------------------------------------------------------------------------
// application/octet-stream — raw bytes forwarded unchanged
// ---------------------------------------------------------------------------
@test:Config {}
function testConstructContentDist_OctetStream_PassThrough() returns error? {
    byte[] payloadBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]; // PNG header
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: mime:APPLICATION_OCTET_STREAM};

    websubhub:ContentDistributionMessage|error result = buildContentDistMsg(makeStoredMessage(payloadBytes, metadata), false);
    assertNoError(result, "octet-stream passthrough");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, mime:APPLICATION_OCTET_STREAM);
    test:assertEquals(dist.content, payloadBytes);
}

// ---------------------------------------------------------------------------
// binary regression — full 0x00..0xFF range must survive as exact octets
// ---------------------------------------------------------------------------
@test:Config {}
function testConstructContentDist_Binary_FullByteRange() returns error? {
    byte[] payloadBytes = [];
    int i = 0;
    while i < 256 {
        payloadBytes.push(<byte>i);
        i += 1;
    }
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: mime:APPLICATION_OCTET_STREAM};

    websubhub:ContentDistributionMessage|error result = buildContentDistMsg(makeStoredMessage(payloadBytes, metadata), false);
    assertNoError(result, "binary full 0x00..0xFF");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, mime:APPLICATION_OCTET_STREAM);
    test:assertEquals(dist.content, payloadBytes,
        "all 256 byte values must be delivered as the original octets, not a JSON integer array");
}

// ---------------------------------------------------------------------------
// custom MIME type — passed through as-is
// ---------------------------------------------------------------------------
@test:Config {}
function testConstructContentDist_CustomMime_PassThrough() returns error? {
    byte[] payloadBytes = "custom payload".toBytes();
    string customMime = "application/vnd.example+protobuf";
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: customMime};

    websubhub:ContentDistributionMessage|error result = buildContentDistMsg(makeStoredMessage(payloadBytes, metadata), false);
    assertNoError(result, "custom MIME passthrough");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, customMime);
    test:assertEquals(dist.content, payloadBytes);
}

// ---------------------------------------------------------------------------
// content-type stored as string[] (multi-valued header) → first value used
// ---------------------------------------------------------------------------
@test:Config {}
function testConstructContentDist_ContentTypeAsStringArray_FirstValueUsed() returns error? {
    byte[] payloadBytes = "<a/>".toBytes();
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: [mime:APPLICATION_XML, "extra"]};

    websubhub:ContentDistributionMessage|error result = buildContentDistMsg(makeStoredMessage(payloadBytes, metadata), false);
    assertNoError(result, "content-type as string[]");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, mime:APPLICATION_XML, "first element of string[] must be used");
    test:assertEquals(dist.content, payloadBytes);
}

// ---------------------------------------------------------------------------
// malformed JSON payload with json content-type → error (caller deadLetters)
// ---------------------------------------------------------------------------
@test:Config {}
function testConstructContentDist_Json_MalformedPayload_ReturnsError() {
    byte[] payloadBytes = "not valid json {{{".toBytes();
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: mime:APPLICATION_JSON};

    websubhub:ContentDistributionMessage|error result = buildContentDistMsg(makeStoredMessage(payloadBytes, metadata), false);
    test:assertTrue(result is error,
        "malformed JSON must return an error so the delivery loop can deadLetter the message");
}

// ---------------------------------------------------------------------------
// x-hub-messageId propagated to delivery headers
// ---------------------------------------------------------------------------
@test:Config {}
function testConstructContentDist_MessageId_PropagatedInHeaders() returns error? {
    byte[] payloadBytes = "<root/>".toBytes();
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: mime:APPLICATION_XML};
    storeapi:Message msg = {payload: payloadBytes, metadata, id: "msg-12345"};

    websubhub:ContentDistributionMessage|error result = buildContentDistMsg(msg, false);
    assertNoError(result, "message id in headers");
    websubhub:ContentDistributionMessage dist = check result;

    map<string|string[]>? headers = dist.headers;
    test:assertTrue(headers is map<string|string[]>, "headers must be present");
    if headers is map<string|string[]> {
        test:assertTrue(headers.hasKey("x-hub-messageId"), "x-hub-messageId must be forwarded");
        test:assertFalse(headers.hasKey(common:CONTENT_TYPE_METADATA_KEY),
                "broker-internal x-hub-contentType must NOT leak to subscriber headers");
    }
}

// ===========================================================================
// Content-unaware passthrough mode (contentPassthrough = true)
// ===========================================================================

// ---------------------------------------------------------------------------
// application/json — forwarded as raw bytes, NOT parsed into a json value
// ---------------------------------------------------------------------------
@test:Config {}
function testPassthrough_Json_ForwardsRawBytes() returns error? {
    json payload = {"event": "order.created", "id": 42};
    byte[] payloadBytes = payload.toJsonString().toBytes();
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: mime:APPLICATION_JSON};

    websubhub:ContentDistributionMessage|error result = buildContentDistMsg(makeStoredMessage(payloadBytes, metadata), true);
    assertNoError(result, "passthrough JSON");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, mime:APPLICATION_JSON);
    test:assertEquals(dist.content, payloadBytes,
        "passthrough must forward the stored JSON bytes verbatim, not a re-parsed json value");
}

// ---------------------------------------------------------------------------
// malformed JSON — passthrough never parses, so it must NOT error
// ---------------------------------------------------------------------------
@test:Config {}
function testPassthrough_MalformedJson_NoError() returns error? {
    byte[] payloadBytes = "not valid json {{{".toBytes();
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: mime:APPLICATION_JSON};

    websubhub:ContentDistributionMessage|error result = buildContentDistMsg(makeStoredMessage(payloadBytes, metadata), true);
    assertNoError(result, "passthrough must not parse, so malformed JSON is fine");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.content, payloadBytes, "bytes forwarded verbatim, no validation");
}

// ---------------------------------------------------------------------------
// arbitrary content type (image/png) — bytes forwarded with the exact type
// ---------------------------------------------------------------------------
@test:Config {}
function testPassthrough_ArbitraryContentType_PngBytes() returns error? {
    byte[] payloadBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]; // PNG signature
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: "image/png"};

    websubhub:ContentDistributionMessage|error result = buildContentDistMsg(makeStoredMessage(payloadBytes, metadata), true);
    assertNoError(result, "passthrough image/png");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, "image/png");
    test:assertEquals(dist.content, payloadBytes, "PNG bytes must be delivered exactly");
}

// ---------------------------------------------------------------------------
// passthrough still filters the broker-internal content-type key from headers
// ---------------------------------------------------------------------------
@test:Config {}
function testPassthrough_DoesNotLeakInternalContentTypeHeader() returns error? {
    byte[] payloadBytes = "%PDF-1.7".toBytes();
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: "application/pdf"};
    storeapi:Message msg = {payload: payloadBytes, metadata, id: "pdf-1"};

    websubhub:ContentDistributionMessage|error result = buildContentDistMsg(msg, true);
    assertNoError(result, "passthrough header filtering");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, "application/pdf");
    map<string|string[]>? headers = dist.headers;
    test:assertTrue(headers is map<string|string[]>, "headers must be present");
    if headers is map<string|string[]> {
        test:assertTrue(headers.hasKey("x-hub-messageId"), "x-hub-messageId must be forwarded");
        test:assertFalse(headers.hasKey(common:CONTENT_TYPE_METADATA_KEY),
                "broker-internal x-hub-contentType must NOT leak even in passthrough mode");
    }
}
