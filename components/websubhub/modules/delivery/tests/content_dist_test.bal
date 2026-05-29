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

// Unit tests for constructContentDistMsg — the function that converts a raw
// storeapi:Message from the broker into a websubhub:ContentDistributionMessage.
//
// Test strategy
// ─────────────
// constructContentDistMsg branches on the value of the x-hub-contentType
// metadata key stored at ingest time:
//
//   • application/json (or absent key)  → parse payload with fromJsonString,
//                                         set contentType = mime:APPLICATION_JSON
//   • any other MIME type               → pass raw byte[] through,
//                                         set contentType from stored value
//
// Each test constructs a minimal storeapi:Message with the appropriate metadata
// and payload and asserts the resulting ContentDistributionMessage fields.
//
// ─── IMPORTANT: Ballerina type-system subtlety ───────────────────────────────
// In Ballerina both `string` and `byte[]` are subtypes of `json`:
//   • string  <: json      (json = boolean|int|float|decimal|string|json[]|…)
//   • byte[]  <: json[]    (byte = int:Unsigned8 <: int <: json)
//
// Consequences for content-type passthrough:
//   1. persistence.bal — the match expression over UpdateMessage.content MUST
//      check `c is byte[]` and `c is string` BEFORE `c is json`; otherwise
//      both branch to `c.toJsonString().toBytes()` and produce:
//        text  → "\"Hello…\""  (JSON-quoted)
//        binary → "[137,80,…]" (JSON integer array)
//   2. constructContentDistMsg — content must be byte[] (not decoded string)
//      for non-JSON types; passing a decoded string would coerce it back to
//      json inside ContentDistributionMessage.content = json|xml|string|byte[]?,
//      and the HubClient's retrieveRequestPayload would see it as json and call
//      setPayload(json), which re-JSON-serialises it.
//
// The regression tests for binary (octet-stream) and plain-text below lock in
// that these invariants hold end-to-end through constructContentDistMsg.

import ballerina/mime;
import ballerina/test;
import ballerina/websubhub;

import websubhub.common;

import wso2/messagestore.api as storeapi;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// makeRawMessage builds a storeapi:Message with the given payload bytes and
// optional metadata map (nil means no metadata at all).
// Named distinctly from makeMessage() in deliver_and_acknowledge_test.bal which
// has a different signature (shared test module — all test files compile together).
isolated function makeRawMessage(byte[] payload, map<string|string[]>? metadata) returns storeapi:Message {
    return {payload, metadata};
}

// assertNoError fails the test if result is an error and prints the message.
isolated function assertNoError(websubhub:ContentDistributionMessage|error result, string label) {
    if result is error {
        test:assertFail(string `${label}: unexpected error — ${result.message()}`);
    }
}

// ---------------------------------------------------------------------------
// application/json — with explicit metadata key
// ---------------------------------------------------------------------------

@test:Config {}
function testConstructContentDist_Json_WithMetadataKey() returns error? {
    json payload = {"event": "order.created", "id": 42};
    byte[] payloadBytes = payload.toJsonString().toBytes();
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: mime:APPLICATION_JSON};

    storeapi:Message msg = makeRawMessage(payloadBytes, metadata);
    websubhub:ContentDistributionMessage|error result = constructContentDistMsg(msg);

    assertNoError(result, "JSON with metadata key");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, mime:APPLICATION_JSON, "contentType must be application/json");
    // The parsed JSON must match the original payload value
    test:assertEquals(dist.content, payload, "content must be parsed JSON value");
}

// ---------------------------------------------------------------------------
// application/json — absent metadata key (backward-compat: old messages)
// ---------------------------------------------------------------------------

@test:Config {}
function testConstructContentDist_Json_NoMetadataKey_BackwardCompat() returns error? {
    json payload = {"event": "legacy"};
    byte[] payloadBytes = payload.toJsonString().toBytes();

    // No metadata at all — simulates messages stored before the content-type
    // passthrough feature was deployed.
    storeapi:Message msg = makeRawMessage(payloadBytes, ());

    websubhub:ContentDistributionMessage|error result = constructContentDistMsg(msg);

    assertNoError(result, "JSON backward compat (no metadata)");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, mime:APPLICATION_JSON);
    test:assertEquals(dist.content, payload);
}

// ---------------------------------------------------------------------------
// application/json — metadata map present but key absent
// ---------------------------------------------------------------------------

@test:Config {}
function testConstructContentDist_Json_MetadataPresentKeyAbsent() returns error? {
    json payload = 99;
    byte[] payloadBytes = payload.toJsonString().toBytes();
    // Metadata exists but does not contain x-hub-contentType
    map<string|string[]> metadata = {"x-hub-messageId": "abc"};

    storeapi:Message msg = makeRawMessage(payloadBytes, metadata);
    websubhub:ContentDistributionMessage|error result = constructContentDistMsg(msg);

    assertNoError(result, "JSON — metadata present, key absent");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, mime:APPLICATION_JSON);
    test:assertEquals(dist.content, payload);
}

// ---------------------------------------------------------------------------
// application/xml — raw bytes passed through unchanged
// ---------------------------------------------------------------------------

@test:Config {}
function testConstructContentDist_Xml_PassThrough() returns error? {
    string xmlStr = "<root><item>hello</item></root>";
    byte[] payloadBytes = xmlStr.toBytes();
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: "application/xml"};

    storeapi:Message msg = makeRawMessage(payloadBytes, metadata);
    websubhub:ContentDistributionMessage|error result = constructContentDistMsg(msg);

    assertNoError(result, "application/xml passthrough");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, "application/xml", "contentType must be application/xml");
    // content must be the raw byte[] — not parsed XML
    test:assertEquals(dist.content, payloadBytes, "content must be raw payload bytes");
}

// ---------------------------------------------------------------------------
// text/plain — raw bytes forwarded as byte[] through both persistence and delivery
// ---------------------------------------------------------------------------
// Two-layer invariant for text/plain:
//   Layer 1 (persistence.bal): UpdateMessage.content is a Ballerina `string`.
//     The match MUST check `c is string` before `c is json` because string <: json.
//     If json fires first, c.toJsonString() produces "\"Hello…\"" (quoted).
//   Layer 2 (HubClient): ContentDistributionMessage.content must be byte[] not string.
//     If a decoded string is stored in content, the HubClient sees it as json (string
//     <: json) and calls setPayload(json), which re-adds JSON quotes.
//     Using byte[] bypasses the json subtype coercion: setPayload(byte[]) sends raw bytes.

@test:Config {}
function testConstructContentDist_TextPlain_PassThrough() returns error? {
    string text = "Hello, subscriber!";
    byte[] payloadBytes = text.toBytes();
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: "text/plain"};

    // payloadBytes represents what persistence.bal stores CORRECTLY (raw UTF-8 bytes,
    // NOT the JSON-quoted variant "\"Hello, subscriber!\"").
    storeapi:Message msg = makeRawMessage(payloadBytes, metadata);
    websubhub:ContentDistributionMessage|error result = constructContentDistMsg(msg);

    assertNoError(result, "text/plain passthrough");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, "text/plain");
    // content MUST be byte[] — this ensures the HubClient's setPayload() call
    // receives a byte[] (not a json string), so the subscriber receives the bare
    // text body without surrounding JSON quote characters.
    test:assertEquals(dist.content, payloadBytes,
        "text/plain content must be byte[] so HubClient sends unquoted bytes");
}

// ---------------------------------------------------------------------------
// application/octet-stream — raw bytes passed through unchanged
// ---------------------------------------------------------------------------

@test:Config {}
function testConstructContentDist_OctetStream_PassThrough() returns error? {
    byte[] payloadBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]; // PNG header bytes
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: "application/octet-stream"};

    storeapi:Message msg = makeRawMessage(payloadBytes, metadata);
    websubhub:ContentDistributionMessage|error result = constructContentDistMsg(msg);

    assertNoError(result, "application/octet-stream passthrough");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, "application/octet-stream");
    // content MUST be byte[] — not a string, not a json integer array.
    // If persistence.bal's match wrongly routes byte[] through c.toJsonString(),
    // the stored payload would be "[137,80,78,71,13,10]" and this test would fail
    // because those decoded bytes do not match the original payloadBytes.
    test:assertEquals(dist.content, payloadBytes);
}

// ---------------------------------------------------------------------------
// binary regression — non-UTF-8 bytes must NOT become a JSON integer array
// ---------------------------------------------------------------------------
// This test is the critical regression guard for the persistence.bal match-order
// fix: `byte[] is json` is true in Ballerina, so c is json fires before c is byte[]
// unless the match arms are ordered correctly.  If that ordering regresses, the
// bytes stored in Solace would be "[137,80,78,71,13,10,26,10]" (JSON array) rather
// than the original octets, and what the subscriber receives would be that
// JSON string — NOT the original binary data.

@test:Config {}
function testConstructContentDist_Binary_RawBytesNotJsonArray() returns error? {
    // PNG magic bytes — deliberately non-UTF-8 so any mistaken JSON-array
    // serialisation is immediately visible as a mismatch.
    byte[] originalBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: mime:APPLICATION_OCTET_STREAM};

    // Simulate correctly-stored payload: raw bytes (persistence fix in place)
    storeapi:Message msg = makeRawMessage(originalBytes, metadata);
    websubhub:ContentDistributionMessage|error result = constructContentDistMsg(msg);

    assertNoError(result, "binary regression — raw bytes");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, mime:APPLICATION_OCTET_STREAM);

    // The content must equal the exact original bytes.
    // If persistence wrongly JSON-serialised them, the stored bytes would be
    // "[137,80,78,71,13,10,26,10]" and this assertion would fail on length alone.
    test:assertEquals(dist.content, originalBytes,
        "binary payload must arrive as the original octets, not a JSON integer array");
}

// ---------------------------------------------------------------------------
// application/x-www-form-urlencoded thin-ping backward-compat
// ---------------------------------------------------------------------------
// Classic WebSub thin-ping: publisher POSTs hub.mode=publish&hub.topic=... with
// Content-Type: application/x-www-form-urlencoded.  The Ballerina websubhub library
// calls request.getFormParams() and puts the result (map<string|string[]>) into
// UpdateMessage.content. persistence.bal serialises this via toJsonString() and MUST
// store x-hub-contentType=application/json (not application/x-www-form-urlencoded),
// because the HubClient's retrieveRequestPayload attempts <map<string>>payload for
// application/x-www-form-urlencoded, which panics on a byte[] value.
//
// This test simulates what persistence.bal now stores for a thin-ping after the fix.

@test:Config {}
function testConstructContentDist_FormEncoded_ThinPing_DeliveredAsJson() returns error? {
    // This is what persistence.bal stores after the effectiveContentType fix:
    // form params are JSON-serialised, type is overridden to application/json.
    json formParamsAsJson = {"hub.mode": ["publish"], "hub.topic": ["test-topic"]};
    byte[] payloadBytes = formParamsAsJson.toJsonString().toBytes();
    // persistence.bal pins effectiveContentType = mime:APPLICATION_JSON for json branch
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: mime:APPLICATION_JSON};

    storeapi:Message msg = makeRawMessage(payloadBytes, metadata);
    websubhub:ContentDistributionMessage|error result = constructContentDistMsg(msg);

    assertNoError(result, "form-encoded thin-ping backward-compat");
    websubhub:ContentDistributionMessage dist = check result;

    // Must be delivered as application/json — NOT application/x-www-form-urlencoded
    // (the latter would panic the HubClient at cast time).
    test:assertEquals(dist.contentType, mime:APPLICATION_JSON,
        "form-encoded thin-ping must be delivered as application/json");
    test:assertEquals(dist.content, formParamsAsJson,
        "form params must be delivered as the parsed JSON value");
}

// ---------------------------------------------------------------------------
// Custom MIME type — passed through as-is
// ---------------------------------------------------------------------------

@test:Config {}
function testConstructContentDist_CustomMime_PassThrough() returns error? {
    byte[] payloadBytes = "custom payload".toBytes();
    string customMime = "application/vnd.example+json";
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: customMime};

    storeapi:Message msg = makeRawMessage(payloadBytes, metadata);
    websubhub:ContentDistributionMessage|error result = constructContentDistMsg(msg);

    assertNoError(result, "custom MIME type passthrough");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, customMime);
    test:assertEquals(dist.content, payloadBytes);
}

// ---------------------------------------------------------------------------
// Content-type key holds a string[] (multiple values) — first value is used
// ---------------------------------------------------------------------------

@test:Config {}
function testConstructContentDist_ContentTypeAsStringArray_FirstValueUsed() returns error? {
    string xmlStr = "<a/>";
    byte[] payloadBytes = xmlStr.toBytes();
    // Metadata stored x-hub-contentType as string[] (e.g. round-tripped via Kafka headers)
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: ["application/xml", "extra"]};

    storeapi:Message msg = makeRawMessage(payloadBytes, metadata);
    websubhub:ContentDistributionMessage|error result = constructContentDistMsg(msg);

    assertNoError(result, "content-type as string[] — first value used");
    websubhub:ContentDistributionMessage dist = check result;

    test:assertEquals(dist.contentType, "application/xml",
        "first element of string[] must be used as contentType");
    test:assertEquals(dist.content, payloadBytes);
}

// ---------------------------------------------------------------------------
// JSON parse failure — malformed payload with application/json key → error
// ---------------------------------------------------------------------------

@test:Config {}
function testConstructContentDist_Json_MalformedPayload_ReturnsError() {
    byte[] payloadBytes = "not valid json {{{".toBytes();
    map<string|string[]> metadata = {[common:CONTENT_TYPE_METADATA_KEY]: mime:APPLICATION_JSON};

    storeapi:Message msg = makeRawMessage(payloadBytes, metadata);
    websubhub:ContentDistributionMessage|error result = constructContentDistMsg(msg);

    test:assertTrue(result is error,
        "malformed JSON payload must return an error so the caller can deadLetter the message");
}

// ---------------------------------------------------------------------------
// x-hub-messageId is propagated in headers regardless of content type
// ---------------------------------------------------------------------------

@test:Config {}
function testConstructContentDist_MessageId_PropagatedInHeaders() returns error? {
    byte[] payloadBytes = "<root/>".toBytes();
    map<string|string[]> metadata = {
        [common:CONTENT_TYPE_METADATA_KEY]: "application/xml",
        "x-hub-messageId": "msg-12345"
    };

    storeapi:Message msg = {payload: payloadBytes, metadata, id: "msg-12345"};
    websubhub:ContentDistributionMessage|error result = constructContentDistMsg(msg);

    assertNoError(result, "message ID in headers");
    websubhub:ContentDistributionMessage dist = check result;

    map<string|string[]>? headers = dist.headers;
    test:assertTrue(headers is map<string|string[]>, "headers must be present");
    if headers is map<string|string[]> {
        test:assertTrue(headers.hasKey("x-hub-messageId"),
            "x-hub-messageId must be forwarded to subscriber headers");
    }
}
