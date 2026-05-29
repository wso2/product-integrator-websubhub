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
//
// Test strategy
// -------------
// Each test uses one of three mock consumers from mock_types.bal:
//   consumerExpectingAck()        — ack→(), nack/deadLetter→error
//   consumerExpectingNack()       — nack→(), ack/deadLetter→error
//   consumerExpectingDeadLetter() — deadLetter→(), ack/nack→error
//
// Asserting `test:assertEquals(result, ())` implicitly verifies the correct ACK method
// was called: if the wrong method fires, the stub returns an error that propagates out
// of deliverAndAcknowledge() and the assertion fails.
//
// HubClient is mocked via test:mock(websubhub:HubClient) + stubHubClient() from mock_types.bal.

import ballerina/mime;
import ballerina/test;
import ballerina/websubhub;

import wso2/messagestore.api as storeapi;

// ---------------------------------------------------------------------------
// Constants & test fixtures
// ---------------------------------------------------------------------------

const TEST_TOPIC    = "test-topic";
const TEST_CALLBACK = "http://subscriber.example.com/callback";

// Minimal valid ContentDistributionMessage used across all delivery tests.
final websubhub:ContentDistributionMessage TEST_NOTIFICATION = {
    content: "{\"event\":\"test\"}",
    contentType: mime:APPLICATION_JSON
};

// A genuine 2xx success return value from notifyContentDistribution.
final websubhub:ContentDistributionSuccess SUCCESS_2XX = {statusCode: 200};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Constructs a storeapi:Message with sensible defaults.
function makeMessage(string? id = "msg-001", int? deliveryCount = 1) returns storeapi:Message {
    return {
        payload: "test".toBytes(),
        id: id,
        deliveryCount: deliveryCount
    };
}

// Constructs a websubhub:Error with the given status code.
// body/headers/mediaType default to non-nil values so the network-error fingerprint
// (rule 3 in classifyDeliveryError) does NOT fire unless explicitly passed as ().
isolated function makeError(
        int statusCode,
        (string|byte[]|json|xml|map<string>)? body = "stub-body",
        map<string|string[]>? headers = {"X-Stub": "true"},
        string? mediaType = "text/plain") returns websubhub:Error {
    return error websubhub:Error("delivery error",
            statusCode = statusCode,
            body = body,
            headers = headers,
            mediaType = mediaType);
}

// Constructs the network-error fingerprint: statusCode=500, all nullable fields nil.
// Matches the Ballerina websubhub library's behaviour on connection-refused failures.
isolated function makeNetworkError() returns websubhub:Error {
    return error websubhub:Error("connection refused",
            statusCode = 500,
            body = (),
            headers = (),
            mediaType = ());
}

// ---------------------------------------------------------------------------
// SUCCESS PATHS
// ---------------------------------------------------------------------------

@test:Config {}
function testDeliver_Genuine2xx_Acks() returns error? {
    storeapi:Consumer mockConsumer = consumerExpectingAck();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, SUCCESS_2XX);

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(), mockClient, TEST_NOTIFICATION, TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, (), msg = "genuine 2xx must call ack and return ()");
}

@test:Config {}
function testDeliver_Genuine2xx_WithDeliveryCount3_Acks() returns error? {
    // deliveryCount=3 means the third broker delivery; must still ACK on success.
    storeapi:Consumer mockConsumer = consumerExpectingAck();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, SUCCESS_2XX);

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(deliveryCount = 3), mockClient, TEST_NOTIFICATION,
            TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, ());
}

// ---------------------------------------------------------------------------
// CONCERN A — ackStatusCodes bypass (2xx status codes raised as websubhub:Error)
// ---------------------------------------------------------------------------

@test:Config {}
function testDeliver_ConcernA_202AsError_Acks() returns error? {
    // Library quirk: 202 Accepted sometimes surfaces as websubhub:Error.
    // The ackStatusCodes guard must intercept this and ACK instead of classifying it.
    storeapi:Consumer mockConsumer = consumerExpectingAck();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, makeError(202));

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(), mockClient, TEST_NOTIFICATION, TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, (), msg = "Concern A: 202-as-error must call ack (treated as success)");
}

@test:Config {}
function testDeliver_ConcernA_204AsError_Acks() returns error? {
    storeapi:Consumer mockConsumer = consumerExpectingAck();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, makeError(204));

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(), mockClient, TEST_NOTIFICATION, TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, (), msg = "Concern A: 204-as-error must call ack (treated as success)");
}

@test:Config {}
function testDeliver_ConcernA_201AsError_Acks() returns error? {
    storeapi:Consumer mockConsumer = consumerExpectingAck();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, makeError(201));

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(), mockClient, TEST_NOTIFICATION, TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, (), msg = "Concern A: 201-as-error must call ack (treated as success)");
}

// ---------------------------------------------------------------------------
// NON-RECOVERABLE PATHS  →  deadLetter  (immediate DMQ routing, no sleep)
// ---------------------------------------------------------------------------

@test:Config {}
function testDeliver_400_DeadLetters() returns error? {
    storeapi:Consumer mockConsumer = consumerExpectingDeadLetter();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, makeError(400));

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(), mockClient, TEST_NOTIFICATION, TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, (), msg = "400 must call deadLetter (route to DMQ)");
}

@test:Config {}
function testDeliver_401_DeadLetters() returns error? {
    storeapi:Consumer mockConsumer = consumerExpectingDeadLetter();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, makeError(401));

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(), mockClient, TEST_NOTIFICATION, TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, ());
}

@test:Config {}
function testDeliver_403_DeadLetters() returns error? {
    storeapi:Consumer mockConsumer = consumerExpectingDeadLetter();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, makeError(403));

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(), mockClient, TEST_NOTIFICATION, TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, ());
}

@test:Config {}
function testDeliver_404_DeadLetters() returns error? {
    storeapi:Consumer mockConsumer = consumerExpectingDeadLetter();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, makeError(404));

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(), mockClient, TEST_NOTIFICATION, TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, (), msg = "404 must call deadLetter (route to DMQ)");
}

@test:Config {}
function testDeliver_410_DeadLetters() returns error? {
    // 410 Gone — subscriber permanently removed; must go to DMQ immediately, never retry.
    storeapi:Consumer mockConsumer = consumerExpectingDeadLetter();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, makeError(410));

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(), mockClient, TEST_NOTIFICATION, TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, (), msg = "410 must call deadLetter (route to DMQ immediately)");
}

// ---------------------------------------------------------------------------
// RECOVERABLE PATHS  →  nack  (sleep applied; interval=0.0 in tests/Config.toml)
// ---------------------------------------------------------------------------

@test:Config {}
function testDeliver_500_Nacks() returns error? {
    // Real HTTP 500 — headers present, so rule 3 (network-error) does not fire.
    storeapi:Consumer mockConsumer = consumerExpectingNack();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, makeError(500));

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(), mockClient, TEST_NOTIFICATION, TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, (), msg = "500 must call nack (signal broker to retry)");
}

@test:Config {}
function testDeliver_502_Nacks() returns error? {
    storeapi:Consumer mockConsumer = consumerExpectingNack();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, makeError(502));

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(), mockClient, TEST_NOTIFICATION, TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, ());
}

@test:Config {}
function testDeliver_503_Nacks() returns error? {
    storeapi:Consumer mockConsumer = consumerExpectingNack();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, makeError(503));

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(), mockClient, TEST_NOTIFICATION, TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, ());
}

@test:Config {}
function testDeliver_504_Nacks() returns error? {
    storeapi:Consumer mockConsumer = consumerExpectingNack();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, makeError(504));

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(), mockClient, TEST_NOTIFICATION, TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, ());
}

@test:Config {}
function testDeliver_Timeout_Nacks() returns error? {
    // statusCode=0 → timeout / connection-level failure → timeoutError="recoverable" (test Config.toml)
    storeapi:Consumer mockConsumer = consumerExpectingNack();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient,
            error websubhub:Error("timeout", statusCode = 0, body = (), headers = (), mediaType = ()));

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(), mockClient, TEST_NOTIFICATION, TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, (), msg = "timeout (statusCode=0) must call nack");
}

@test:Config {}
function testDeliver_NetworkError_Nacks() returns error? {
    // statusCode=500, all fields nil → network-error fingerprint → networkError="recoverable"
    storeapi:Consumer mockConsumer = consumerExpectingNack();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, makeNetworkError());

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(), mockClient, TEST_NOTIFICATION, TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, (), msg = "network-error fingerprint must call nack");
}

@test:Config {}
function testDeliver_UnknownStatusCode_FollowsConfig() returns error? {
    // 418 not in any list; unknownStatusCodes="recoverable" in tests/Config.toml → nack
    storeapi:Consumer mockConsumer = consumerExpectingNack();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, makeError(418));

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(), mockClient, TEST_NOTIFICATION, TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, (), msg = "unknown statusCode must follow unknownStatusCodes config → nack");
}

// ---------------------------------------------------------------------------
// METADATA / deliveryCount
// ---------------------------------------------------------------------------

@test:Config {}
function testDeliver_DeliveryCountPresent_NoError() returns error? {
    // deliveryCount=5 → attempt=5 in log output; must not cause an error.
    storeapi:Consumer mockConsumer = consumerExpectingAck();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, SUCCESS_2XX);

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(deliveryCount = 5), mockClient, TEST_NOTIFICATION,
            TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, ());
}

@test:Config {}
function testDeliver_DeliveryCountNull_DefaultsToAttempt1() returns error? {
    // deliveryCount=() → `message.deliveryCount ?: 1` in implementation → attempt=1; no error.
    storeapi:Consumer mockConsumer = consumerExpectingAck();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, SUCCESS_2XX);

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(deliveryCount = ()), mockClient, TEST_NOTIFICATION,
            TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, (),
            msg = "nil deliveryCount must not cause an error — defaults to attempt=1");
}

@test:Config {}
function testDeliver_MessageIdNull_LoggedAsNone() returns error? {
    // id=() → `message.id ?: "(none)"` in implementation — logged as '(none)'; no error.
    storeapi:Consumer mockConsumer = consumerExpectingAck();
    websubhub:HubClient mockClient = test:mock(websubhub:HubClient);
    stubHubClient(mockClient, SUCCESS_2XX);

    error? result = deliverAndAcknowledge(
            mockConsumer, makeMessage(id = ()), mockClient, TEST_NOTIFICATION,
            TEST_TOPIC, TEST_CALLBACK);

    test:assertEquals(result, (),
            msg = "nil message id must not cause an error — logged as '(none)'");
}
