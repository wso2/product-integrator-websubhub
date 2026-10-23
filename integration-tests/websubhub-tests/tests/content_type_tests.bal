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
import ballerina/test;
import ballerina/uuid;

// A topic declares its content type at registration, and the hub delivers content published to
// that topic using the declared type. These tests assert on the `Content-Type` the SUBSCRIBER
// receives, because that is the only thing that distinguishes passthrough from a default: a hub
// that rewrote every delivery to `application/json` would still deliver successfully and pass
// every other assertion in this suite.
//
// The hub under test runs with the default `strictContentTypeValidation`, which is `true`, so a
// publish whose content type disagrees with the declaration is rejected rather than delivered.

// ========================================
// Declaring a content type
// ========================================

@test:Config {groups: ["content-type"]}
function testTopicDefaultsToJsonWhenNoContentTypeDeclared() returns error? {
    final string topic = newTopic();
    check registerAndWaitForTopic(topic);

    test:assertEquals(check declaredContentType(topic), DEFAULT_CONTENT_TYPE,
            "A topic registered without a content type should default to " + DEFAULT_CONTENT_TYPE);
}

@test:Config {groups: ["content-type"], dataProvider: supportedContentTypes}
function testDeclaredContentTypeIsRecorded(string contentType, string payload) returns error? {
    final string topic = newTopic();
    check registerAndWaitForTopic(topic, contentType);

    test:assertEquals(check declaredContentType(topic), contentType,
            "The consolidator should report the content type declared for the topic");
}

@test:Config {groups: ["content-type", "negative"], dataProvider: unsupportedContentTypes}
function testUnsupportedContentTypeIsRejected(string contentType) returns error? {
    final string topic = newTopic();

    http:Response response = check registerTopic(topic, contentType);
    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST,
            string `Registering a topic with content type '${contentType}' should be rejected`);
    test:assertFalse(check isTopicRegistered(topic),
            "A topic whose content type was rejected should not be registered");
}

// ========================================
// Delivery
// ========================================

@test:Config {groups: ["content-type", "publish"], dataProvider: supportedContentTypes}
function testContentTypeIsPassedThroughToSubscriber(string contentType, string payload) returns error? {
    final string topic = newTopic();
    final string id = uuid:createType4AsString();
    check subscribeAndWaitWithContentType(topic, id, contentType);

    http:Response response = check publishAs(topic, payload, contentType);
    test:assertEquals(response.statusCode, http:STATUS_OK,
            string `Publishing ${contentType} content to a topic declaring it should be accepted`);
    check waitUntil(isolated function() returns boolean|error => deliveriesOf(id).length() > 0,
            string `the ${contentType} content to be delivered to the subscriber`);

    ContentDelivery delivery = deliveriesOf(id)[0];
    test:assertEquals(delivery.contentType, contentType,
            "The subscriber should receive the content type declared for the topic");
    test:assertEquals(delivery.payload, payload,
            "The subscriber should receive the published payload unchanged");
}

@test:Config {groups: ["content-type", "publish"]}
function testJsonIsDeliveredWhenNoContentTypeDeclared() returns error? {
    final string topic = newTopic();
    final string id = uuid:createType4AsString();
    check subscribeAndWait(topic, id);

    http:Response response = check publish(topic, {"event": "order-created"});
    test:assertEquals(response.statusCode, http:STATUS_OK, "Content publishing should be accepted");
    check waitUntil(isolated function() returns boolean|error => deliveriesOf(id).length() > 0,
            "the content to be delivered to the subscriber");

    test:assertEquals(deliveriesOf(id)[0].contentType, DEFAULT_CONTENT_TYPE,
            "A topic that declares no content type should deliver as " + DEFAULT_CONTENT_TYPE);
}

@test:Config {groups: ["content-type", "publish", "negative"]}
function testMismatchedContentTypeIsRejected() returns error? {
    final string topic = newTopic();
    final string id = uuid:createType4AsString();
    check subscribeAndWaitWithContentType(topic, id, "application/xml");

    http:Response response = check publishAs(topic, "{\"event\":\"order-created\"}", "application/json");
    test:assertEquals(response.statusCode, http:STATUS_UNSUPPORTED_MEDIA_TYPE,
            "Publishing content whose type disagrees with the topic declaration should be rejected");

    // A rejected publish must not reach the subscriber at all. There is no state change to wait
    // for here, so allow the delivery path the time it would have needed before asserting that
    // nothing arrived.
    runtime:sleep(5);
    test:assertEquals(deliveriesOf(id).length(), 0,
            "Content rejected at publish should never be delivered");
}

// ========================================
// Data providers
// ========================================

# The content types a topic may declare, each with a payload that is valid for it.
#
# The hub parses a published payload against its content type and rejects a malformed one with
# `400` before delivery, so a single generic body cannot be reused across these cases.
#
# + return - The content type and a payload valid for it
function supportedContentTypes() returns [string, string][] => [
    ["application/json", "{\"event\":\"order-created\"}"],
    ["application/xml", "<order><id>1</id></order>"],
    ["text/plain", "order-created"],
    ["application/octet-stream", "order-created-bytes"]
];

# Content types a topic may not declare.
#
# Includes a parameterised form of a supported type: the hub matches the declaration against the
# full header, so `text/plain; charset=utf-8` is refused even though `text/plain` is supported.
# Asserted explicitly because it is the case most likely to surprise a publisher being migrated.
#
# + return - The unsupported content type
function unsupportedContentTypes() returns [string][] => [
    ["text/csv"],
    ["application/vnd.acme+json"],
    ["text/plain; charset=utf-8"]
];

// ========================================
// Helpers
// ========================================

# Registers a topic declaring a content type, subscribes a test subscriber to it, and waits until
# the subscription is active.
#
# The counterpart of `subscribeAndWait` for topics that declare a content type. It cannot reuse
# that helper, because the readiness probe there publishes JSON, which a topic declaring another
# type rejects with `415`.
#
# + topic - The topic to subscribe to
# + id - The identifier of the test subscriber
# + contentType - The content type to declare for the topic
# + return - An `error` if the subscription fails or is not processed in time
isolated function subscribeAndWaitWithContentType(string topic, string id, string contentType) returns error? {
    final string callback = callbackUrl(id);
    check registerAndWaitForTopic(topic, contentType);
    http:Response response = check subscribe(topic, callback);
    test:assertEquals(response.statusCode, http:STATUS_ACCEPTED, "Subscription should be accepted");
    check waitUntil(isolated function() returns boolean|error => isSubscribed(topic, callback),
            "the subscription to be added to the consolidator");
}

# A payload the hub accepts for a content type, used to probe that a topic is ready.
#
# + contentType - The content type declared for the topic
# + return - A payload valid for that content type
isolated function probePayload(string contentType) returns string {
    match contentType {
        "application/xml" => {
            return "<probe/>";
        }
        "text/plain"|"application/octet-stream" => {
            return "probe";
        }
    }
    return "{\"probe\":true}";
}
