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
import websubhub.connections as conn;

import ballerina/http;
import ballerina/lang.value;
import ballerina/websubhub;

import wso2/messagestore as store;

final store:Administrator administrator = check conn:createAdministrator();

public isolated function createTopic(websubhub:TopicRegistration topicRegistration)
    returns websubhub:TopicRegistrationError|error? {

    error? result = administrator->createTopic(topicRegistration.topic);
    if result is store:TopicExists {
        string errorMessage = string `Topic ${topicRegistration.topic} already exists in the message store, deregister the topic first.`;
        return error websubhub:TopicRegistrationError(errorMessage, statusCode = http:STATUS_CONFLICT);
    }
    return result;
}

public isolated function deleteTopic(websubhub:TopicDeregistration topicDeregistration)
    returns websubhub:TopicDeregistrationError|error? {

    error? result = administrator->deleteTopic(topicDeregistration.topic);
    if result is store:TopicNotFound {
        string errorMessage = string `Topic ${topicDeregistration.topic} could not be found in the message store.`;
        return error websubhub:TopicDeregistrationError(errorMessage, statusCode = http:STATUS_NOT_FOUND);
    }
    return result;
}

public isolated function createSubscription(websubhub:VerifiedSubscription subscription)
    returns websubhub:InternalSubscriptionError|error? {

    string topic = subscription.hubTopic;
    string timestamp = check value:ensureType(subscription[common:SUBSCRIPTION_TIMESTAMP]);
    string subscriberId = string `${subscription.hubTopic}___${subscription.hubCallback}___${timestamp}`;
    error? result = administrator->createSubscription(topic, subscriberId);
    if result is store:SubscriptionExists {
        string errorMessage = string `Subscription for topic ${topic} and subscriber ${subscriberId} already exists in the message store.`;
        return error websubhub:InternalSubscriptionError(errorMessage, statusCode = http:STATUS_CONFLICT);
    }
    return result;
}

public isolated function deleteSubscription(websubhub:VerifiedUnsubscription unsubscription)
    returns websubhub:InternalUnsubscriptionError|error? {

    string topic = unsubscription.hubTopic;
    string timestamp = check value:ensureType(unsubscription[common:SUBSCRIPTION_TIMESTAMP]);
    string subscriberId = string `${unsubscription.hubTopic}___${unsubscription.hubCallback}___${timestamp}`;
    error? result = administrator->deleteSubscription(topic, subscriberId);
    if result is store:SubscriptionNotFound {
        string errorMessage = string `Subscription for topic ${topic} and subscriber ${subscriberId} can not be found in the message store.`;
        return error websubhub:InternalUnsubscriptionError(errorMessage, statusCode = http:STATUS_NOT_FOUND);
    }
    return result;
}
