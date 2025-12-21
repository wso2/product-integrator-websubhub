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
import websubhub.config;

import ballerina/websubhub;

import wso2/messagestore as store;

// Producer which persist the current in-memory state of the Hub 
final store:Producer statePersistProducer = check initStatePersistProducer();

function initStatePersistProducer() returns store:Producer|error {
    var {kafka, solace} = config:store;
    if solace is store:SolaceConfig {
        return store:createSolaceProducer(solace, "state-persist");
    }
    if kafka is store:KafkaConfig {
        return store:createKafkaProducer(kafka, "state-persist");
    }
    return error("Error occurred while reading the message store configurations when creating the store producer");
}

// Consumer which reads the persisted subscriber details
public final store:Consumer websubEventsConsumer = check initWebSubEventsConsumer();

final string websubEventsConsumerId = string `${config:state.events.consumerIdPrefix}-${config:server.id}`;

function initWebSubEventsConsumer() returns store:Consumer|error {
    check admin:createWebSubEventsSubscription(config:state.events.topic, websubEventsConsumerId);
    var {kafka, solace} = config:store;
    if solace is store:SolaceConfig {
        return store:createSolaceConsumer(
                solace,
                websubEventsConsumerId,
                false
        );
    }
    if kafka is store:KafkaConfig {
        return store:createKafkaConsumer(
                kafka,
                websubEventsConsumerId,
                config:state.events.topic,
                autoCommit = false
        );
    }
    return error("Error occurred while reading the message store configurations when creating the store consumer");
}

# Initialize a `store:Consumer` for a WebSub subscriber.
#
# + subscription - The WebSub subscriber details
# + return - A `store:Consumer` for the message store, or else return an `error` if the operation fails
public isolated function createConsumer(websubhub:VerifiedSubscription subscription) returns store:Consumer|error {
    var {kafka, solace} = config:store;
    if solace is store:SolaceConfig {
        return createSolaceConsumerForSubscriber(solace, subscription);
    }
    if kafka is store:KafkaConfig {
        return createKafkaConsumerForSubscriber(kafka, subscription);
    }
    return error("Error occurred while reading the message store configurations when creating the store consumer");
}

# Retrieves a message producer per topic.
#
# + topic - The message store topic
# + return - A `store:Producer` for the message store, or else an `error` if the operation fails
public isolated function getMessageProducer(string topic) returns store:Producer|error {
    return statePersistProducer;
}
