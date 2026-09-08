// Copyright (c) 2025, WSO2 LLC. (http://www.wso2.org).
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

import websubhub.common;
import websubhub.config;

import ballerina/http;
import ballerina/lang.value;
import ballerina/log;
import ballerina/websubhub;

import wso2/messagestore as store;
import wso2/messagestore.api as storeapi;

final storeapi:Administrator administrator = check store:createAdministrator(config:store);

public isolated function createWebSubEventsSubscription(string topic, string consumerId) returns error? {
    error? result = administrator->createSubscription(topic, consumerId, true);
    if result is storeapi:SubscriptionExists {
        log:printWarn(string `Subscription for Topic [${topic}] and Subscriber [${consumerId}] exists`);
        return;
    }
    return result;
}

public isolated function createTopic(common:TopicRegistration topicRegistration)
    returns websubhub:TopicRegistrationError|error? {

    error? result = administrator->createTopic(topicRegistration.topic, false, topicRegistration);
    if result is storeapi:TopicExists {
        string errorMessage = string `Topic ${topicRegistration.topic} already exists in the message store, deregister the topic first.`;
        return error websubhub:TopicRegistrationError(errorMessage, statusCode = http:STATUS_CONFLICT);
    }
    return result;
}

public isolated function deleteTopic(websubhub:TopicDeregistration topicDeregistration)
    returns websubhub:TopicDeregistrationError|error? {

    error? result = administrator->deleteTopic(topicDeregistration.topic, false, topicDeregistration);
    if result is storeapi:TopicNotFound {
        string errorMessage = string `Topic ${topicDeregistration.topic} could not be found in the message store.`;
        return error websubhub:TopicDeregistrationError(errorMessage, statusCode = http:STATUS_NOT_FOUND);
    }
    return result;
}

public isolated function createSubscription(websubhub:VerifiedSubscription subscription)
    returns websubhub:InternalSubscriptionError|error? {

    string topic = subscription.hubTopic;
    string timestamp = check value:ensureType(subscription[common:SUBSCRIPTION_TIMESTAMP]);
    string consumerName = constructConsumerId(topic, subscription.hubCallback, timestamp);
    error? result = administrator->createSubscription(topic, consumerName, false, subscription);
    if result is storeapi:SubscriptionExists {
        string errorMessage = string `
            Subscription for topic ${topic} and callback ${subscription.hubCallback} with consumer-name ${consumerName} already exists in the message store.`;
        return error websubhub:InternalSubscriptionError(errorMessage, statusCode = http:STATUS_CONFLICT);
    }
    return result;
}

public isolated function deleteSubscription(websubhub:VerifiedSubscription subscription)
    returns websubhub:InternalUnsubscriptionError|error? {

    string topic = subscription.hubTopic;
    string timestamp = check value:ensureType(subscription[common:SUBSCRIPTION_TIMESTAMP]);
    string consumerName = constructConsumerId(topic, subscription.hubCallback, timestamp);
    error? result = administrator->deleteSubscription(topic, consumerName, false, subscription);
    if result is storeapi:SubscriptionNotFound {
        string errorMessage = string `
            Subscription for topic ${topic} and callback ${subscription.hubCallback} with consumer-name ${consumerName} can not be found in the message store.`;
        return error websubhub:InternalUnsubscriptionError(errorMessage, statusCode = http:STATUS_NOT_FOUND);
    }
    return result;
}

isolated function constructConsumerId(string topic, string hubCallback, string timestamp) returns string {
    string subscriberId = string `${topic}___${hubCallback}___${timestamp}`;
    int constructedId = 0;
    foreach var [idx, val] in subscriberId.toCodePointInts().enumerate() {
        constructedId += (idx + 1) * val;
    }
    return string `${constructedId}`;
}
