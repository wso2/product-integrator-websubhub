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

import websubhub.common;

import ballerina/test;
import ballerina/websubhub;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Constructs a websubhub:Error whose detail() carries the given status code and
// optional response fields.  Defaults produce the "real HTTP response" fingerprint
// (non-nil body/headers/mediaType) so tests only set what they need.
isolated function makeDeliveryError(
        int statusCode,
        (string|byte[]|json|xml|map<string>)? body = "stub",
        map<string|string[]>? headers = {"X-Stub": "true"},
        string? mediaType = "text/plain") returns websubhub:Error {
    return error websubhub:Error("delivery error",
            statusCode = statusCode,
            body = body,
            headers = headers,
            mediaType = mediaType);
}

// Returns a base config with all fields at their defaults and interval=0.0.
isolated function baseConfig() returns common:BrokerRetryConfig {
    return {
        ackStatusCodes: [200, 201, 202, 204],
        recoverableStatusCodes: [500, 502, 503, 504],
        nonRecoverableStatusCodes: [400, 401, 403, 404, 410],
        unknownStatusCodes: "recoverable",
        timeoutError: "recoverable",
        networkError: "recoverable",
        interval: 0.0
    };
}

// Constructs a config with timeoutError overridden — avoids duplicate-key spread errors.
isolated function configWithTimeout(common:FailureBehavior timeoutBehavior) returns common:BrokerRetryConfig {
    return {
        ackStatusCodes: [200, 201, 202, 204],
        recoverableStatusCodes: [500, 502, 503, 504],
        nonRecoverableStatusCodes: [400, 401, 403, 404, 410],
        unknownStatusCodes: "recoverable",
        timeoutError: timeoutBehavior,
        networkError: "recoverable",
        interval: 0.0
    };
}

// Constructs a config with networkError overridden.
isolated function configWithNetwork(common:FailureBehavior networkBehavior) returns common:BrokerRetryConfig {
    return {
        ackStatusCodes: [200, 201, 202, 204],
        recoverableStatusCodes: [500, 502, 503, 504],
        nonRecoverableStatusCodes: [400, 401, 403, 404, 410],
        unknownStatusCodes: "recoverable",
        timeoutError: "recoverable",
        networkError: networkBehavior,
        interval: 0.0
    };
}

// Constructs a config with unknownStatusCodes overridden.
isolated function configWithUnknown(common:FailureBehavior unknownBehavior) returns common:BrokerRetryConfig {
    return {
        ackStatusCodes: [200, 201, 202, 204],
        recoverableStatusCodes: [500, 502, 503, 504],
        nonRecoverableStatusCodes: [400, 401, 403, 404, 410],
        unknownStatusCodes: unknownBehavior,
        timeoutError: "recoverable",
        networkError: "recoverable",
        interval: 0.0
    };
}

// ---------------------------------------------------------------------------
// Rule 1 — statusCode == 0  →  timeoutError behavior
// ---------------------------------------------------------------------------

@test:Config {}
function testClassify_Timeout_ReturnsTimeoutErrorBehavior() {
    common:FailureBehavior result = classifyDeliveryError(
            makeDeliveryError(0), configWithTimeout("nonRecoverable"));
    test:assertEquals(result, "nonRecoverable",
            msg = "statusCode=0 must return the configured timeoutError behavior");
}

@test:Config {}
function testClassify_Timeout_RecoverableVariant() {
    common:FailureBehavior result = classifyDeliveryError(
            makeDeliveryError(0), configWithTimeout("recoverable"));
    test:assertEquals(result, "recoverable");
}

@test:Config {}
function testClassify_Timeout_DefaultsToRecoverableWhenConfigIsNil() {
    // retryConfig=() → timeoutError branch uses ?: fallback → "recoverable"
    common:FailureBehavior result = classifyDeliveryError(makeDeliveryError(0), ());
    test:assertEquals(result, "recoverable",
            msg = "statusCode=0 with nil retryConfig must default to recoverable");
}

// ---------------------------------------------------------------------------
// Rule 2 — retryConfig is ()  →  always "recoverable"
// ---------------------------------------------------------------------------

@test:Config {}
function testClassify_NilRetryConfig_AlwaysRecoverable() {
    // Non-zero statusCode so rule 1 does not fire; retryConfig=() triggers rule 2.
    common:FailureBehavior result = classifyDeliveryError(makeDeliveryError(500), ());
    test:assertEquals(result, "recoverable",
            msg = "nil retryConfig must always classify as recoverable");
}

@test:Config {}
function testClassify_NilRetryConfig_NonRecoverableCode() {
    common:FailureBehavior result = classifyDeliveryError(makeDeliveryError(404), ());
    test:assertEquals(result, "recoverable",
            msg = "nil retryConfig must classify even 404 as recoverable");
}

// ---------------------------------------------------------------------------
// Rule 3 — statusCode==500 AND body/headers/mediaType all ()  →  networkError
// ---------------------------------------------------------------------------

@test:Config {}
function testClassify_NetworkError_AllFieldsNil_NonRecoverable() {
    // All three nullable fields explicitly nil — matches the network-error fingerprint.
    common:FailureBehavior result = classifyDeliveryError(
            makeDeliveryError(500, body = (), headers = (), mediaType = ()),
            configWithNetwork("nonRecoverable"));
    test:assertEquals(result, "nonRecoverable",
            msg = "statusCode=500 with null body/headers/mediaType must use networkError behavior");
}

@test:Config {}
function testClassify_NetworkError_AllFieldsNil_Recoverable() {
    common:FailureBehavior result = classifyDeliveryError(
            makeDeliveryError(500, body = (), headers = (), mediaType = ()),
            configWithNetwork("recoverable"));
    test:assertEquals(result, "recoverable");
}

@test:Config {}
function testClassify_NetworkError_NotTriggered_WhenHeadersPresent() {
    // statusCode=500 but headers populated → real HTTP 500, not a transport error.
    // Rule 3 must NOT fire; falls through to rule 4 (recoverableStatusCodes).
    common:FailureBehavior result = classifyDeliveryError(
            makeDeliveryError(500, headers = {"Content-Type": "application/json"}),
            baseConfig());
    test:assertEquals(result, "recoverable",
            msg = "statusCode=500 with headers must not be classified as network error");
}

@test:Config {}
function testClassify_NetworkError_NotTriggered_WhenBodyPresent() {
    common:FailureBehavior result = classifyDeliveryError(
            makeDeliveryError(500, body = "Internal Server Error"),
            baseConfig());
    test:assertEquals(result, "recoverable",
            msg = "statusCode=500 with body must not be classified as network error");
}

// ---------------------------------------------------------------------------
// Rule 4 — statusCode in recoverableStatusCodes  →  "recoverable"
// ---------------------------------------------------------------------------

@test:Config {}
function testClassify_RecoverableStatusCode_500() {
    // Must use headers to avoid rule 3 (network-error check).
    common:FailureBehavior result = classifyDeliveryError(
            makeDeliveryError(500, headers = {"X-Real": "true"}), baseConfig());
    test:assertEquals(result, "recoverable");
}

@test:Config {}
function testClassify_RecoverableStatusCode_502() {
    common:FailureBehavior result = classifyDeliveryError(makeDeliveryError(502), baseConfig());
    test:assertEquals(result, "recoverable");
}

@test:Config {}
function testClassify_RecoverableStatusCode_503() {
    common:FailureBehavior result = classifyDeliveryError(makeDeliveryError(503), baseConfig());
    test:assertEquals(result, "recoverable");
}

@test:Config {}
function testClassify_RecoverableStatusCode_504() {
    common:FailureBehavior result = classifyDeliveryError(makeDeliveryError(504), baseConfig());
    test:assertEquals(result, "recoverable");
}

// ---------------------------------------------------------------------------
// Rule 5 — statusCode in nonRecoverableStatusCodes  →  "nonRecoverable"
// ---------------------------------------------------------------------------

@test:Config {}
function testClassify_NonRecoverable_400() {
    common:FailureBehavior result = classifyDeliveryError(makeDeliveryError(400), baseConfig());
    test:assertEquals(result, "nonRecoverable");
}

@test:Config {}
function testClassify_NonRecoverable_401() {
    common:FailureBehavior result = classifyDeliveryError(makeDeliveryError(401), baseConfig());
    test:assertEquals(result, "nonRecoverable");
}

@test:Config {}
function testClassify_NonRecoverable_403() {
    common:FailureBehavior result = classifyDeliveryError(makeDeliveryError(403), baseConfig());
    test:assertEquals(result, "nonRecoverable");
}

@test:Config {}
function testClassify_NonRecoverable_404() {
    common:FailureBehavior result = classifyDeliveryError(makeDeliveryError(404), baseConfig());
    test:assertEquals(result, "nonRecoverable");
}

@test:Config {}
function testClassify_NonRecoverable_410() {
    common:FailureBehavior result = classifyDeliveryError(makeDeliveryError(410), baseConfig());
    test:assertEquals(result, "nonRecoverable");
}

// ---------------------------------------------------------------------------
// Rule 6 — fallback  →  unknownStatusCodes behavior
// ---------------------------------------------------------------------------

@test:Config {}
function testClassify_UnknownStatusCode_DefaultsToRecoverable() {
    // 418 I'm a Teapot — not in either list; unknownStatusCodes="recoverable"
    common:FailureBehavior result = classifyDeliveryError(
            makeDeliveryError(418), configWithUnknown("recoverable"));
    test:assertEquals(result, "recoverable",
            msg = "unknown statusCode must fall back to unknownStatusCodes config value");
}

@test:Config {}
function testClassify_UnknownStatusCode_ConfiguredNonRecoverable() {
    common:FailureBehavior result = classifyDeliveryError(
            makeDeliveryError(418), configWithUnknown("nonRecoverable"));
    test:assertEquals(result, "nonRecoverable");
}

@test:Config {}
function testClassify_UnknownStatusCode_301Redirect() {
    // 301 is not in either list — falls through to unknownStatusCodes
    common:FailureBehavior result = classifyDeliveryError(
            makeDeliveryError(301), configWithUnknown("nonRecoverable"));
    test:assertEquals(result, "nonRecoverable");
}

// ---------------------------------------------------------------------------
// Boundary / edge cases
// ---------------------------------------------------------------------------

@test:Config {}
function testClassify_EmptyStatusCodeLists_FallsBackToUnknown() {
    // Both lists empty → rules 4 and 5 never match → falls to rule 6.
    common:BrokerRetryConfig cfg = {
        ackStatusCodes: [],
        recoverableStatusCodes: [],
        nonRecoverableStatusCodes: [],
        unknownStatusCodes: "nonRecoverable",
        timeoutError: "recoverable",
        networkError: "recoverable",
        interval: 0.0
    };
    // headers present so rule 3 (network error) does not fire
    common:FailureBehavior result = classifyDeliveryError(
            makeDeliveryError(500, headers = {"X-H": "v"}), cfg);
    test:assertEquals(result, "nonRecoverable",
            msg = "empty status-code lists must fall through to unknownStatusCodes");
}

@test:Config {}
function testClassify_Rule3_BeforeRule4_Priority() {
    // Verifies that rule 3 (network error) fires before rule 4 (recoverableStatusCodes)
    // when statusCode=500 and all response fields are nil.
    // networkError="nonRecoverable" would produce nonRecoverable.
    // If rule 4 ran first, 500 ∈ recoverableStatusCodes → would produce recoverable (wrong).
    common:BrokerRetryConfig cfg = {
        ackStatusCodes: [200, 201, 202, 204],
        recoverableStatusCodes: [500, 502, 503, 504],
        nonRecoverableStatusCodes: [400, 401, 403, 404, 410],
        unknownStatusCodes: "recoverable",
        timeoutError: "recoverable",
        networkError: "nonRecoverable",
        interval: 0.0
    };
    common:FailureBehavior result = classifyDeliveryError(
            makeDeliveryError(500, body = (), headers = (), mediaType = ()), cfg);
    test:assertEquals(result, "nonRecoverable",
            msg = "rule 3 (network error) must take priority over rule 4 (recoverableStatusCodes)");
}
