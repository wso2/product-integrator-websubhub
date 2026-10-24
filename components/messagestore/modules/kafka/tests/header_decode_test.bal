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

// Unit tests for toMetadata / decodeHeaderValue — the Kafka header decoding helpers.
// These are pure unit tests (no broker required).

import ballerina/test;

// ---------------------------------------------------------------------------
// byte[] — single header value deserialised by Kafka as raw bytes
// ---------------------------------------------------------------------------
@test:Config {}
function testToMetadata_ByteArrayDecodedToString() returns error? {
    map<byte[]|byte[][]|string|string[]> headers = {
        "x-hub-contentType": "application/xml".toBytes()
    };
    map<string|string[]>? md = toMetadata(headers);
    test:assertTrue(md is map<string|string[]>, "metadata must be present");
    map<string|string[]> m = check (<map<string|string[]>?>md).ensureType();
    test:assertEquals(m["x-hub-contentType"], "application/xml",
            "byte[] header must be decoded to a string");
}

// ---------------------------------------------------------------------------
// byte[][] — multi-valued header (Kafka can carry repeated header keys)
// ---------------------------------------------------------------------------
@test:Config {}
function testToMetadata_ByteArrayArrayDecodedToStringArray() returns error? {
    map<byte[]|byte[][]|string|string[]> headers = {
        "multi": ["a".toBytes(), "b".toBytes()]
    };
    map<string|string[]>? md = toMetadata(headers);
    map<string|string[]> m = check (<map<string|string[]>?>md).ensureType();
    test:assertEquals(m["multi"], ["a", "b"],
            "byte[][] header must be decoded to a string[]");
}

// ---------------------------------------------------------------------------
// string / string[] — already decoded, should pass through unchanged
// ---------------------------------------------------------------------------
@test:Config {}
function testToMetadata_StringAndStringArrayPassThrough() returns error? {
    map<byte[]|byte[][]|string|string[]> headers = {
        "s": "v",
        "arr": ["x", "y"]
    };
    map<string|string[]> m = check (<map<string|string[]>?>toMetadata(headers)).ensureType();
    test:assertEquals(m["s"], "v");
    test:assertEquals(m["arr"], ["x", "y"]);
}

// ---------------------------------------------------------------------------
// empty headers → ()
// ---------------------------------------------------------------------------
@test:Config {}
function testToMetadata_EmptyHeaders_ReturnsNil() {
    map<byte[]|byte[][]|string|string[]> headers = {};
    test:assertTrue(toMetadata(headers) is (),
            "empty headers must yield ()");
}

// ---------------------------------------------------------------------------
// bad-UTF-8 byte[] — skipped with a warning, not fatal
// ---------------------------------------------------------------------------
@test:Config {}
function testToMetadata_UndecodableHeaderSkipped_NotFatal() returns error? {
    byte[] badUtf8 = [255, 254];    // not valid UTF-8
    map<byte[]|byte[][]|string|string[]> headers = {
        "good": "ok".toBytes(),
        "bad": badUtf8
    };
    map<string|string[]> m = check (<map<string|string[]>?>toMetadata(headers)).ensureType();
    test:assertEquals(m["good"], "ok", "decodable header must be preserved");
    test:assertFalse(m.hasKey("bad"),
            "undecodable header must be skipped, not fail the whole receive");
}

// ---------------------------------------------------------------------------
// decodeHeaderValue — all four input shapes
// ---------------------------------------------------------------------------
@test:Config {}
function testDecodeHeaderValue_AllShapes() returns error? {
    test:assertEquals(check decodeHeaderValue("plain"), "plain");
    test:assertEquals(check decodeHeaderValue(["a", "b"]), ["a", "b"]);
    test:assertEquals(check decodeHeaderValue("bytes".toBytes()), "bytes");
    test:assertEquals(check decodeHeaderValue(["a".toBytes(), "b".toBytes()]), ["a", "b"]);
}
