// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
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

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/lang.value;
import ballerina/test;
import ballerina/uuid;

// End-to-end tracing. The hub joins the trace of whoever published a message, so that one trace covers the publisher,
// the hub and the subscriber instead of breaking at the broker. Each test publishes under a trace context of its own,
// which is what lets it look the resulting trace up and assert on it.
//
// Two ways of publishing are covered:
//   - straight to the broker over its REST messaging gateway, as an upstream system such as an API gateway does;
//   - through the publish API of the hub.
// Both are run with the telemetry of the broker turned on and off, as the broker contributes spans of its own only
// when its telemetry is on, and because the trace context the hub sees comes from a different field of the message in
// each case.

// ========================================
// Published straight to the broker
// ========================================

@test:Config {groups: ["tracing"]}
function testTracingWhenPublishedToBrokerWithoutBrokerTelemetry() returns error? {
    check setBrokerTelemetry(false);
    Trace trace = check runBrokerPublishScenario(false);
    printTrace("published to the broker, telemetry off", trace);

    test:assertFalse(hasBrokerSpans(trace),
            string `With its telemetry off the broker should not contribute spans to the trace of the publisher, ` +
                    string `but the trace has ${servicesOf(trace).toString()}`);
}

@test:Config {groups: ["tracing"]}
function testTracingWhenPublishedToBrokerWithBrokerTelemetry() returns error? {
    check setBrokerTelemetry(true);
    Trace trace = check runBrokerPublishScenario(true);
    printTrace("published to the broker, telemetry on", trace);

    test:assertTrue(hasBrokerSpans(trace),
            string `With its telemetry on the broker should contribute spans to the trace of the publisher, ` +
                    string `but the trace only has ${servicesOf(trace).toString()}`);
}

// ========================================
// Published through the hub
// ========================================

@test:Config {groups: ["tracing"]}
function testTracingWhenPublishedThroughHubWithoutBrokerTelemetry() returns error? {
    check setBrokerTelemetry(false);
    Trace trace = check runHubPublishScenario(false);
    printTrace("published through the hub, telemetry off", trace);

    test:assertFalse(hasBrokerSpans(trace),
            string `With its telemetry off the broker should not contribute spans to the trace of the publisher, ` +
                    string `but the trace has ${servicesOf(trace).toString()}`);
}

@test:Config {groups: ["tracing"]}
function testTracingWhenPublishedThroughHubWithBrokerTelemetry() returns error? {
    check setBrokerTelemetry(true);
    Trace trace = check runHubPublishScenario(true);
    printTrace("published through the hub, telemetry on", trace);

    test:assertTrue(hasBrokerSpans(trace),
            string `With its telemetry on the broker should contribute spans to the trace of the publisher, ` +
                    string `but the trace only has ${servicesOf(trace).toString()}`);
}

@test:AfterGroups {value: ["tracing"]}
function resetBrokerTelemetry() returns error? {
    check setBrokerTelemetry(false);
}

// ========================================
// Scenarios
// ========================================

# Publishes straight to the broker under a trace context of its own and waits until the content reaches the
# subscriber and the delivery shows up in the same trace.
#
# + withBrokerTelemetry - Whether the telemetry of the broker is on, which decides what the trace is awaited for
# + return - The trace of the publisher, or an `error` if the content is not delivered or not traced in time
isolated function runBrokerPublishScenario(boolean withBrokerTelemetry) returns Trace|error {
    final string topic = newTopic();
    final string id = uuid:createType4AsString();
    int delivered = check subscribeAndWaitForDelivery(topic, id);
    var [traceId, traceParent] = newTraceContext();
    json content = {"event": "published-to-broker", "id": id};

    http:Response response = check publishToBroker(topic, content, traceParent);
    test:assertTrue(response.statusCode < 300,
            string `The broker should accept the published content, but responded with ${response.statusCode}`);
    return assertDeliveredAndTraced(id, delivered, content, traceId, withBrokerTelemetry);
}

# Publishes through the hub under a trace context of its own and waits until the content reaches the subscriber and
# both the publish and the delivery show up in the same trace.
#
# + withBrokerTelemetry - Whether the telemetry of the broker is on, which decides what the trace is awaited for
# + return - The trace of the publisher, or an `error` if the content is not delivered or not traced in time
isolated function runHubPublishScenario(boolean withBrokerTelemetry) returns Trace|error {
    final string topic = newTopic();
    final string id = uuid:createType4AsString();
    int delivered = check subscribeAndWaitForDelivery(topic, id);
    var [traceId, traceParent] = newTraceContext();
    json content = {"event": "published-through-hub", "id": id};

    http:Response response = check publish(topic, content, traceParent);
    test:assertEquals(response.statusCode, http:STATUS_OK, "Content publishing should be accepted");
    Trace trace = check assertDeliveredAndTraced(id, delivered, content, traceId, withBrokerTelemetry);
    // Publishing through the hub puts the hub itself upstream of the broker, so the trace also covers the publish
    test:assertTrue(trace.spans.length() > 1,
            string `The trace should cover the publish as well as the delivery, but only has ` +
                    operationsOf(trace).toString());
    return trace;
}

// ========================================
// Helpers
// ========================================

# Subscribes a test subscriber and waits until the hub actually delivers to it, so that a later publish cannot race
# the hub creating the queue of the subscriber and starting to dispatch from it.
#
# + topic - The topic to subscribe to
# + id - The identifier of the test subscriber
# + return - The number of deliveries made while warming up, or an `error` if the subscriber never receives content
isolated function subscribeAndWaitForDelivery(string topic, string id) returns int|error {
    check subscribeAndWait(topic, id);
    http:Response response = check publish(topic, {"warmup": id});
    test:assertEquals(response.statusCode, http:STATUS_OK, "The warm-up publish should be accepted");
    check waitUntil(isolated function() returns boolean|error => deliveriesOf(id).length() > 0,
            string `the hub to start delivering to the subscriber ${id}`);
    return deliveriesOf(id).length();
}

# Asserts that the content reaches the subscriber and that the hub reports its delivery in the trace of the
# publisher, which together is what makes the trace end-to-end.
#
# + id - The identifier of the test subscriber
# + delivered - The number of deliveries made before the content was published
# + content - The published content
# + traceId - The identifier of the trace of the publisher
# + withBrokerTelemetry - Whether the spans of the broker are expected in the trace as well
# + return - The trace of the publisher, or an `error` if the content is not delivered or not traced in time
isolated function assertDeliveredAndTraced(string id, int delivered, json content, string traceId,
        boolean withBrokerTelemetry) returns Trace|error {
    check waitUntil(isolated function() returns boolean|error => deliveriesOf(id).length() > delivered,
            string `the content to be delivered to the subscriber ${id}`);
    ContentDelivery delivery = deliveriesOf(id)[delivered];
    test:assertEquals(check value:fromJsonString(delivery.payload), content,
            "The subscriber should receive the published content");

    // The spans of the hub and those of the broker reach the tracing backend over different paths, so the trace is
    // awaited for everything it is expected to carry rather than for the delivery alone
    Trace trace = check waitForTrace(traceId, isolated function(Trace candidate) returns boolean =>
                    hasSpan(candidate, DELIVERY_SPAN) && (!withBrokerTelemetry || hasBrokerSpans(candidate)),
            withBrokerTelemetry
                ? "the hub and the broker to report the delivery in the trace of the publisher"
                : "the hub to report the delivery in the trace of the publisher");
    test:assertEquals(trace.traceID, traceId,
            "The hub should report the delivery in the trace of the publisher, not in a trace of its own");

    if !withBrokerTelemetry {
        // Absence cannot be awaited, so the spans of the broker are given the time they would need to turn up before
        // the test concludes that there are none, and the trace is read once more
        runtime:sleep(telemetrySettleTime);
        Trace? settled = check getTrace(traceId);
        return settled ?: trace;
    }
    return trace;
}
