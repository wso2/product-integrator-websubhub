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
import ballerina/url;

# The URL of the hub under test, e.g. `http://localhost:9580`
public configurable string hubUrl = ?;
# The URL of the consolidator under test, e.g. `http://localhost:10580`
public configurable string consolidatorUrl = ?;
# The port on which the test subscriber receives intent verification and content delivery requests
public configurable int subscriberPort = ?;
# The maximum time in seconds to wait for an asynchronous state change to become visible
public configurable decimal eventualTimeout = 60;

final http:Client hubClient = check new (hubUrl);
final http:Client consolidatorClient = check new (consolidatorUrl);

# The header with which a publisher declares the content type of a topic at registration.
public const string CONTENT_TYPE_HEADER = "x-hub-content-type";

# The content type the hub delivers with when a topic declares none.
public const string DEFAULT_CONTENT_TYPE = "application/json";

# The system state reported by the consolidator.
public type SystemState record {
    # The registered topics
    record {string topic; string contentType?;}[] topics;
    # The verified subscriptions
    record {string hubTopic; string hubCallback;}[] subscriptions;
};

# Registers a topic in the hub.
#
# + topic - The topic to register
# + contentType - The content type to declare for the topic. When not given, the hub applies its default.
# + return - The response of the hub, or an `error` if the request fails
public isolated function registerTopic(string topic, string? contentType = ()) returns http:Response|error {
    map<string> headers = contentType is string ? {[CONTENT_TYPE_HEADER]: contentType} : {};
    return sendHubRequest({"hub.mode": "register", "hub.topic": topic}, headers);
}

# Deregisters a topic from the hub.
#
# + topic - The topic to deregister
# + return - The response of the hub, or an `error` if the request fails
public isolated function deregisterTopic(string topic) returns http:Response|error {
    return sendHubRequest({"hub.mode": "deregister", "hub.topic": topic});
}

# Subscribes a callback to a topic.
#
# + topic - The topic to subscribe to
# + callback - The callback URL of the subscriber
# + secret - The secret used by the hub to sign the content delivered to the subscriber
# + return - The response of the hub, or an `error` if the request fails
public isolated function subscribe(string topic, string callback, string? secret = ()) returns http:Response|error {
    map<string> params = {"hub.mode": "subscribe", "hub.topic": topic, "hub.callback": callback};
    if secret is string {
        params["hub.secret"] = secret;
    }
    return sendHubRequest(params);
}

# Unsubscribes a callback from a topic.
#
# + topic - The topic to unsubscribe from
# + callback - The callback URL of the subscriber
# + return - The response of the hub, or an `error` if the request fails
public isolated function unsubscribe(string topic, string callback) returns http:Response|error {
    return sendHubRequest({"hub.mode": "unsubscribe", "hub.topic": topic, "hub.callback": callback});
}

# Publishes JSON content to a topic.
#
# + topic - The topic to publish to
# + content - The content to publish
# + traceParent - The `traceparent` header of the publisher, if the publish is to be made under a known trace
# + return - The response of the hub, or an `error` if the request fails
public isolated function publish(string topic, json content, string? traceParent = ()) returns http:Response|error {
    string path = string `/hub?hub.mode=publish&hub.topic=${check url:encode(topic, "UTF-8")}`;
    http:Request request = new;
    request.setJsonPayload(content);
    if traceParent is string {
        request.setHeader("traceparent", traceParent);
    }
    return hubClient->post(path, request);
}

# Publishes content of an arbitrary content type to a topic.
#
# Separate from `publish`, which always sends JSON. The payload is sent verbatim with the given
# content type, so a test can publish a body that is valid for the type under test — the hub
# parses the payload against its content type and rejects a malformed one with `400` before
# delivery is ever attempted.
#
# + topic - The topic to publish to
# + payload - The content to publish
# + contentType - The `Content-Type` of the publish request
# + return - The response of the hub, or an `error` if the request fails
public isolated function publishAs(string topic, string payload, string contentType)
        returns http:Response|error {
    string path = string `/hub?hub.mode=publish&hub.topic=${check url:encode(topic, "UTF-8")}`;
    http:Request request = new;
    request.setTextPayload(payload, contentType);
    return hubClient->post(path, request);
}

# Returns the content type the consolidator reports for a topic.
#
# + topic - The topic
# + return - The declared content type, `()` if the topic is not registered or declares none,
# or an `error` if the state cannot be retrieved
public isolated function declaredContentType(string topic) returns string?|error {
    SystemState state = check getSystemState();
    foreach var registration in state.topics {
        if registration.topic == topic {
            return registration?.contentType;
        }
    }
    return ();
}

# Retrieves the system state from the consolidator.
#
# + return - The system state, or an `error` if the request fails
public isolated function getSystemState() returns SystemState|error {
    return consolidatorClient->get("/consolidator/state-snapshot");
}

# Checks whether the consolidator reports the given topic as registered.
#
# + topic - The topic
# + return - `true` if the topic is registered, or an `error` if the state cannot be retrieved
public isolated function isTopicRegistered(string topic) returns boolean|error {
    SystemState state = check getSystemState();
    return state.topics.some(registration => registration.topic == topic);
}

# Checks whether the consolidator reports the given subscription.
#
# + topic - The topic
# + callback - The callback URL of the subscriber
# + return - `true` if the subscription exists, or an `error` if the state cannot be retrieved
public isolated function isSubscribed(string topic, string callback) returns boolean|error {
    SystemState state = check getSystemState();
    return state.subscriptions.some(subscription =>
        subscription.hubTopic == topic && subscription.hubCallback == callback);
}

# Waits until a condition holds, as the state of the hub is updated asynchronously.
#
# + condition - The condition to wait for
# + description - The description of the condition, used in the error
# + return - An `error` if the condition does not hold within `eventualTimeout`
public isolated function waitUntil(isolated function () returns boolean|error condition, string description)
        returns error? {
    decimal waited = 0;
    while waited < eventualTimeout {
        boolean|error result = condition();
        if result is true {
            return;
        }
        runtime:sleep(0.5);
        waited += 0.5d;
    }
    return error(string `Timed out after ${eventualTimeout}s waiting for ${description}`);
}

# Returns the callback URL of a test subscriber.
#
# + id - The unique identifier of the subscriber
# + return - The callback URL
public isolated function callbackUrl(string id) returns string => string `http://localhost:${subscriberPort}/callback/${id}`;

isolated function sendHubRequest(map<string> params, map<string> headers = {}) returns http:Response|error {
    string[] fields = [];
    foreach [string, string] [name, value] in params.entries() {
        fields.push(string `${name}=${check url:encode(value, "UTF-8")}`);
    }
    http:Request request = new;
    request.setTextPayload(string:'join("&", ...fields), "application/x-www-form-urlencoded");
    foreach [string, string] [name, value] in headers.entries() {
        request.setHeader(name, value);
    }
    return hubClient->post("/hub", request);
}
