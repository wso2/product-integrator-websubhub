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

import websubhub.consolidator.admin as _;
import websubhub.consolidator.config;

import ballerina/uuid;

import wso2/messagestore as store;
import wso2/messagestore.api as storeapi;

// Producer which persist the current consolidated in-memory state of the system
public final storeapi:Producer statePersistProducer = check initStatePersistProducer();

function initStatePersistProducer() returns storeapi:Producer|error {
    string clientId = string `consolidated-state-persist-${uuid:createRandomUuid()}`;
    return store:createProducer(clientId, config:store);
}

// Consumer which reads the persisted topic-registration/topic-deregistration/subscription/unsubscription events
public final storeapi:Consumer websubEventsConsumer = check initWebSubEventsConsumer();

function initWebSubEventsConsumer() returns storeapi:Consumer|error {
    var [consumer, _] = check store:createConsumer(config:state.events.topic, config:state.events.consumerId, config:store, true);
    return consumer;
}

# Initializes the WebSub event snapshot consumer.
#
# + return - A `store:Consumer` for the message store, or else return an `error` if the operation fails
public isolated function initWebSubEventSnapshotConsumer() returns storeapi:Consumer|error {
    var [consumer, _] = check store:createConsumer(config:state.snapshot.topic, config:state.snapshot.consumerId, config:store, true);
    return consumer;
}

# Retrieves a message producer per topic.
#
# + topic - The message store topic
# + return - A `store:Producer` for the message store, or else an `error` if the operation fails
public isolated function getMessageProducer(string topic) returns storeapi:Producer|error {
    return statePersistProducer;
}
