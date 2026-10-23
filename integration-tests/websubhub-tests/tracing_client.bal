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
import ballerina/io;
import ballerina/lang.runtime;
import ballerina/url;
import ballerina/uuid;

# The URL of the tracing backend the hub and the broker report to, e.g. `http://localhost:16680`
public configurable string jaegerUrl = ?;
# The URL of the REST messaging gateway of the broker, used to publish without going through the hub
public configurable string brokerRestUrl = ?;
# The base URL of the SEMP API of the broker, e.g. `http://localhost:18580/SEMP/v2`
public configurable string brokerSempUrl = ?;
# The name of the telemetry profile provisioned on the broker by the integration-tests Gradle build
public configurable string brokerTelemetryProfile = "trace";
# The name of the trace filter of that telemetry profile, which decides which messages the broker traces
public configurable string brokerTraceFilter = "all";

# The name of the span the hub opens in the trace of the publisher while it delivers a message to a subscriber.
# It is defined by `websubhub.observability`, and is what makes the delivery visible in the trace of the publisher.
public const string DELIVERY_SPAN = "wso2/websubhub.delivery/consume";

# The name the spans of the broker are reported under. The broker itself reports the host name of its container,
# which differs on every run, so the collector renames it - see `resources/otel-collector.yaml`.
public const string BROKER_SERVICE = "solace-broker";

# Whether to print the spans of every trace the tests assert on. Off by default, as only a diagnosis needs them.
public configurable boolean printTraces = false;

# The time in seconds to allow the broker to apply a change to its telemetry, and to allow spans that should not be
# there to turn up before a test concludes that they are absent
public configurable decimal telemetrySettleTime = 10;

final http:Client jaegerClient = check new (jaegerUrl);
// The message VPN authenticates its clients against its own user store, which the telemetry receiver of the
// collector needs, so both the REST messaging gateway and SEMP have to be addressed with credentials
final http:Client brokerRestClient = check new (brokerRestUrl, auth = {username: "admin", password: "admin"});
final http:Client brokerSempClient = check new (brokerSempUrl, auth = {username: "admin", password: "admin"});

# A reference from one span of a trace to another, which is how the tracing backend reports parentage.
public type SpanReference record {
    # The kind of the reference, e.g. `CHILD_OF`
    string refType;
    # The identifier of the referenced span
    string spanID;
};

# A span of a trace, as reported by the query API of the tracing backend.
public type Span record {
    # The identifier of the trace the span belongs to
    string traceID;
    # The identifier of the span
    string spanID;
    # The name of the operation the span represents
    string operationName;
    # The identifier of the process that reported the span, a key of `Trace.processes`
    string processID;
    # The duration of the span in microseconds
    int duration;
    # The spans this span refers to, which carry its parent
    SpanReference[] references?;
};

# A trace, as reported by the query API of the tracing backend.
public type Trace record {
    # The identifier of the trace
    string traceID;
    # The spans of the trace
    Span[] spans;
    # The processes that reported the spans, keyed by `Span.processID`
    map<record {string serviceName;}> processes;
};

# Creates a W3C trace context that identifies a trace of its own, as an instrumented publisher upstream of the broker
# would send. Returning the trace identifier separately is what lets a test look the trace up afterwards.
#
# + return - A tuple of the trace identifier and the `traceparent` header carrying it
public isolated function newTraceContext() returns [string, string] {
    string traceId = re `-`.replaceAll(uuid:createType4AsString(), "");
    string spanId = traceId.substring(0, 16);
    return [traceId, string `00-${traceId}-${spanId}-01`];
}

# Publishes content straight to the broker over its REST messaging gateway, bypassing the hub. The hub picks the
# message up from the queue of the subscriber, exactly as it does for content published by an upstream system.
#
# + topic - The topic to publish to, which is also the topic the hub subscribes the queue of a subscriber to
# + content - The content to publish
# + traceParent - The `traceparent` header of the publisher, which the broker carries on the message
# + return - The response of the broker, or an `error` if the request fails
public isolated function publishToBroker(string topic, json content, string traceParent)
        returns http:Response|error {
    http:Request request = new;
    request.setJsonPayload(content);
    request.setHeader("traceparent", traceParent);
    return brokerRestClient->post(string `/TOPIC/${check url:encode(topic, "UTF-8")}`, request);
}

# Turns the telemetry of the broker on or off, which is what distinguishes a run with the broker contributing spans
# of its own from one without it. The telemetry profile itself is provisioned by the Gradle build.
#
# The trace filter is what is toggled, rather than the telemetry profile, for two reasons. It is the setting that
# decides per message whether the broker traces it, so it covers the spans of both directions - whereas
# `traceSendSpanGenerationEnabled` only governs the send spans and leaves the receive spans flowing. And it leaves
# the profile up, so the receiver of the collector stays connected across the toggle.
#
# + enabled - Whether the broker should trace the messages it handles
# + return - An `error` if the broker rejects the change
public isolated function setBrokerTelemetry(boolean enabled) returns error? {
    http:Response response = check brokerSempClient->patch(
            string `/config/msgVpns/default/telemetryProfiles/${brokerTelemetryProfile}` +
                    string `/traceFilters/${brokerTraceFilter}`,
            {enabled});
    if response.statusCode != http:STATUS_OK {
        return error(string `Failed to turn the telemetry of the broker ${enabled ? "on" : "off"}: ` +
                check response.getTextPayload());
    }
    // The broker applies the change to the connections that are already established, but not instantly
    runtime:sleep(telemetrySettleTime);
}

# Checks whether the broker contributed spans of its own to a trace.
#
# + trace - The trace
# + return - `true` if the trace has spans reported by the broker
public isolated function hasBrokerSpans(Trace trace) returns boolean =>
    servicesOf(trace).indexOf(BROKER_SERVICE) !is ();

# Retrieves a trace from the tracing backend.
#
# + traceId - The identifier of the trace
# + return - The trace, `()` if the backend does not know it yet, or an `error` if the lookup fails
public isolated function getTrace(string traceId) returns Trace?|error {
    http:Response response = check jaegerClient->get(string `/api/traces/${traceId}`);
    if response.statusCode == http:STATUS_NOT_FOUND {
        return ();
    }
    if response.statusCode != http:STATUS_OK {
        return error(string `The tracing backend returned ${response.statusCode} for the trace ${traceId}`);
    }
    record {Trace[] data;} payload = check (check response.getJsonPayload()).cloneWithType();
    return payload.data.length() > 0 ? payload.data[0] : ();
}

# Waits until a trace satisfies a condition, as spans only reach the tracing backend once the reporters of the hub and
# of the collector have flushed them.
#
# + traceId - The identifier of the trace
# + condition - The condition the trace has to satisfy
# + description - The description of the condition, used in the error
# + return - The trace, or an `error` if it does not satisfy the condition in time
public isolated function waitForTrace(string traceId, isolated function (Trace trace) returns boolean condition,
        string description) returns Trace|error {
    decimal waited = 0;
    Trace? lastSeen = ();
    while waited < eventualTimeout {
        Trace? trace = check getTrace(traceId);
        if trace is Trace {
            lastSeen = trace;
            if condition(trace) {
                return trace;
            }
        }
        runtime:sleep(1);
        waited += 1d;
    }
    string seen = lastSeen is Trace
        ? string `it only has the spans ${operationsOf(lastSeen).toString()} from ${servicesOf(lastSeen).toString()}`
        : "it never reached the tracing backend";
    return error(string `Timed out after ${eventualTimeout}s waiting for ${description}: ${seen}`);
}

# Returns the operation names of the spans of a trace.
#
# + trace - The trace
# + return - The operation names, in the order the spans are reported
public isolated function operationsOf(Trace trace) returns string[] =>
    trace.spans.map(span => span.operationName);

# Returns the names of the services that reported the spans of a trace.
#
# + trace - The trace
# + return - The service names, without duplicates
public isolated function servicesOf(Trace trace) returns string[] {
    string[] services = [];
    foreach Span span in trace.spans {
        string? serviceName = trace.processes[span.processID]?.serviceName;
        if serviceName is string && services.indexOf(serviceName) is () {
            services.push(serviceName);
        }
    }
    return services;
}

# Checks whether a trace has a span of the given operation.
#
# + trace - The trace
# + operation - The name of the operation
# + return - `true` if the trace has such a span
public isolated function hasSpan(Trace trace, string operation) returns boolean =>
    trace.spans.some(span => span.operationName == operation);

# Prints the spans of a trace as a tree, to make what the hub reported visible while diagnosing a tracing failure.
# It is off unless `printTraces` is set, as a passing run has no use for it.
#
# + label - The scenario the trace belongs to
# + trace - The trace
public isolated function printTrace(string label, Trace trace) {
    if !printTraces {
        return;
    }
    io:println(string `${"\n"}--- ${label} ---`);
    io:println(string `trace ${trace.traceID}: ${trace.spans.length()} spans from ${servicesOf(trace).toString()}`);
    foreach Span span in trace.spans {
        // A span whose parent is not itself in the trace is a root here. The publisher of a test is not instrumented,
        // so the span it names in its `traceparent` never reaches the tracing backend, and the first span the hub
        // reports refers to a parent that is absent.
        string? parent = parentOf(span);
        if parent is () || !hasSpanId(trace, parent) {
            printSpanTree(trace, span, 0);
        }
    }
}

isolated function hasSpanId(Trace trace, string spanId) returns boolean {
    foreach Span span in trace.spans {
        if span.spanID == spanId {
            return true;
        }
    }
    return false;
}

isolated function printSpanTree(Trace trace, Span span, int depth) {
    string indent = "";
    foreach int _ in 0 ..< depth {
        indent += "    ";
    }
    string serviceName = trace.processes[span.processID]?.serviceName ?: "?";
    decimal milliseconds = <decimal>span.duration / 1000;
    io:println(string `${indent}${span.operationName}  [${serviceName}]  ${milliseconds}ms`);
    foreach Span candidate in trace.spans {
        if parentOf(candidate) == span.spanID {
            printSpanTree(trace, candidate, depth + 1);
        }
    }
}

isolated function parentOf(Span span) returns string? {
    foreach SpanReference reference in span.references ?: [] {
        if reference.refType == "CHILD_OF" {
            return reference.spanID;
        }
    }
    return ();
}
