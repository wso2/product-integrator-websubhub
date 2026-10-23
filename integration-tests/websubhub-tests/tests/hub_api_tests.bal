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
import ballerina/lang.value;
import ballerina/test;
import ballerina/uuid;

// ========================================
// Topic registration
// ========================================

@test:Config {groups: ["topics"]}
function testRegisterTopic() returns error? {
    final string topic = newTopic();

    http:Response response = check registerTopic(topic);
    test:assertEquals(response.statusCode, http:STATUS_OK, "Topic registration should be accepted");
    check waitUntil(isolated function() returns boolean|error => isTopicRegistered(topic),
            string `topic ${topic} to be registered in the consolidator`);
}

@test:Config {groups: ["topics", "negative"]}
function testRegisterDuplicateTopic() returns error? {
    final string topic = newTopic();
    check registerAndWaitForTopic(topic);

    http:Response response = check registerTopic(topic);
    test:assertEquals(response.statusCode, http:STATUS_CONFLICT, "A duplicate topic registration should be rejected");
}

@test:Config {groups: ["topics"]}
function testDeregisterTopic() returns error? {
    final string topic = newTopic();
    check registerAndWaitForTopic(topic);

    http:Response response = check deregisterTopic(topic);
    test:assertEquals(response.statusCode, http:STATUS_OK, "Topic deregistration should be accepted");
    check waitUntil(isolated function() returns boolean|error => !check isTopicRegistered(topic),
            string `topic ${topic} to be removed from the consolidator`);
}

@test:Config {groups: ["topics", "negative"]}
function testDeregisterUnregisteredTopic() returns error? {
    http:Response response = check deregisterTopic(newTopic());
    test:assertEquals(response.statusCode, http:STATUS_NOT_FOUND,
            "Deregistering a topic that is not registered should fail");
}

// ========================================
// Subscription
// ========================================

@test:Config {groups: ["subscriptions"]}
function testSubscribe() returns error? {
    final string topic = newTopic();
    final string id = uuid:createType4AsString();
    final string callback = callbackUrl(id);
    check registerAndWaitForTopic(topic);

    http:Response response = check subscribe(topic, callback);
    test:assertEquals(response.statusCode, http:STATUS_ACCEPTED, "Subscription should be accepted");
    check waitUntil(isolated function() returns boolean|error => hasVerification(id, "subscribe"),
            "the hub to verify the subscription intent");
    VerificationRequest verification = verificationsOf(id).filter(request => request.mode == "subscribe")[0];
    test:assertEquals(verification.topic, topic, "Intent verification should be for the subscribed topic");
    check waitUntil(isolated function() returns boolean|error => isSubscribed(topic, callback),
            "the subscription to be added to the consolidator");
}

@test:Config {groups: ["subscriptions", "negative"]}
function testSubscribeToUnregisteredTopic() returns error? {
    final string topic = newTopic();
    final string id = uuid:createType4AsString();

    http:Response response = check subscribe(topic, callbackUrl(id));
    test:assertEquals(response.statusCode, http:STATUS_ACCEPTED, "Subscription request should be accepted");
    check waitUntil(isolated function() returns boolean|error => hasVerification(id, "denied"),
            "the hub to deny the subscription");
    test:assertFalse(hasVerification(id, "subscribe"), "A subscription to an unregistered topic should not be verified");
}

@test:Config {groups: ["subscriptions"]}
function testUnsubscribe() returns error? {
    final string topic = newTopic();
    final string id = uuid:createType4AsString();
    final string callback = callbackUrl(id);
    check subscribeAndWait(topic, id);

    http:Response response = check unsubscribe(topic, callback);
    test:assertEquals(response.statusCode, http:STATUS_ACCEPTED, "Unsubscription should be accepted");
    check waitUntil(isolated function() returns boolean|error => hasVerification(id, "unsubscribe"),
            "the hub to verify the unsubscription intent");
    check waitUntil(isolated function() returns boolean|error => !check isSubscribed(topic, callback),
            "the subscription to be removed from the consolidator");
}

// ========================================
// Content publishing and delivery
// ========================================

@test:Config {groups: ["publish"]}
function testPublishContent() returns error? {
    final string topic = newTopic();
    final string id = uuid:createType4AsString();
    check subscribeAndWait(topic, id, "integration-test-secret");
    json content = {"event": "order-created", "id": id};

    http:Response response = check publish(topic, content);
    test:assertEquals(response.statusCode, http:STATUS_OK, "Content publishing should be accepted");
    check waitUntil(isolated function() returns boolean|error => deliveriesOf(id).length() > 0,
            "the content to be delivered to the subscriber");
    ContentDelivery delivery = deliveriesOf(id)[0];
    test:assertEquals(check value:fromJsonString(delivery.payload), content,
            "The subscriber should receive the published content");
    test:assertTrue(delivery.signature is string, "The hub should sign the content delivered to a subscriber with a secret");
}

@test:Config {groups: ["publish", "negative"]}
function testPublishToUnregisteredTopic() returns error? {
    http:Response response = check publish(newTopic(), {"event": "order-created"});
    test:assertEquals(response.statusCode, http:STATUS_NOT_FOUND,
            "Publishing to a topic that is not registered should fail");
}

// ========================================
// Helpers
// ========================================

isolated function newTopic() returns string => string `websubhub-it/topic-${uuid:createType4AsString()}`;

# Registers a topic and waits until both the consolidator and the hub have processed the registration.
#
# + topic - The topic to register
# + contentType - The content type to declare for the topic. When not given, the hub applies its default.
# + return - An `error` if the registration fails or is not processed in time
isolated function registerAndWaitForTopic(string topic, string? contentType = ()) returns error? {
    http:Response response = check registerTopic(topic, contentType);
    test:assertEquals(response.statusCode, http:STATUS_OK, "Topic registration should be accepted");
    check waitUntil(isolated function() returns boolean|error => isTopicRegistered(topic),
            string `topic ${topic} to be registered in the consolidator`);
    // The hub updates its state asynchronously from the same events, so wait until it accepts content for the topic.
    // The probe has to match the declared content type: with strict validation a topic declaring, say, XML rejects a
    // JSON probe with 415, which would never become 200 and would time out here rather than in the test itself.
    final string probeType = contentType ?: DEFAULT_CONTENT_TYPE;
    check waitUntil(isolated function() returns boolean|error {
        http:Response publishResponse = check publishAs(topic, probePayload(probeType), probeType);
        return publishResponse.statusCode == http:STATUS_OK;
    }, string `topic ${topic} to be registered in the hub`);
}

# Registers a topic, subscribes a test subscriber to it, and waits until the subscription is active.
#
# + topic - The topic to subscribe to
# + id - The identifier of the test subscriber
# + secret - The secret used by the hub to sign the content delivered to the subscriber
# + return - An `error` if the subscription fails or is not processed in time
isolated function subscribeAndWait(string topic, string id, string? secret = ()) returns error? {
    final string callback = callbackUrl(id);
    check registerAndWaitForTopic(topic);
    http:Response response = check subscribe(topic, callback, secret);
    test:assertEquals(response.statusCode, http:STATUS_ACCEPTED, "Subscription should be accepted");
    check waitUntil(isolated function() returns boolean|error => isSubscribed(topic, callback),
            "the subscription to be added to the consolidator");
}
