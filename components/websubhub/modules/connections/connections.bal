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

import websubhub.admin;
import websubhub.common;
import websubhub.config;

import ballerina/lang.value;
import ballerina/log;
import ballerina/websubhub;

import wso2/messagestore as store;
import wso2/messagestore.api as storeapi;

// Producer which persist the current in-memory state of the Hub 
final storeapi:Producer statePersistProducer = check initStatePersistProducer();

function initStatePersistProducer() returns storeapi:Producer|error {
    string clientId = string `state-persist-${config:serverId}`;
    return store:createProducer(clientId, config:store);
}

// Consumer which reads the persisted subscriber details
public final storeapi:Consumer websubEventsConsumer = check initWebSubEventsConsumer();

function initWebSubEventsConsumer() returns storeapi:Consumer|error {
    log:printInfo("Initializing WebSub events consumer");
    string consumerIdPostfix = config:state.events.consumerIdPostfix ?: "";
    string websubEventsConsumerId = string `${config:state.events.consumerIdPrefix}-${config:serverId}${consumerIdPostfix}`;
    check admin:createWebSubEventsSubscription(config:state.events.topic, websubEventsConsumerId);
    log:printDebug("Created WebSub events subscription", consumerId = websubEventsConsumerId);
    return store:createConsumer(config:state.events.topic, websubEventsConsumerId, config:store, true);
}

# Initialize a `store:Consumer` for a WebSub subscriber.
#
# + subscription - The WebSub subscriber details
# + return - A `store:Consumer` for the message store, or else return an `error` if the operation fails
public isolated function createConsumer(websubhub:VerifiedSubscription subscription) returns storeapi:Consumer|error {
    string topic = subscription.hubTopic;
    string defaultConsumerId = check constructDefaultConsumerId(subscription);
    return store:createConsumer(topic, defaultConsumerId, config:store, false, subscription);
}

isolated function constructDefaultConsumerId(websubhub:VerifiedSubscription subscription) returns string|error {
    string timestamp = check value:ensureType(subscription[common:SUBSCRIPTION_TIMESTAMP]);
    string subscriberId = string `${subscription.hubTopic}___${subscription.hubCallback}___${timestamp}`;
    int constructedId = 0;
    foreach var [idx, val] in subscriberId.toCodePointInts().enumerate() {
        constructedId += (idx + 1) * val;
    }
    return string `${constructedId}`;
}

# Retrieves a message producer per topic.
#
# + topic - The message store topic
# + return - A `store:Producer` for the message store, or else an `error` if the operation fails
public isolated function getMessageProducer(string topic) returns storeapi:Producer|error {
    return statePersistProducer;
}
