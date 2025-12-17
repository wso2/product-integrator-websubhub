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

import wso2/messagestore as store;

// Producer which persist the current consolidated in-memory state of the system
public final store:Producer statePersistProducer = check initStatePersistProducer();

function initStatePersistProducer() returns store:Producer|error {
    var storeConfig = config:store;
    if storeConfig is store:SolaceMessageStore {
        return store:createSolaceProducer(storeConfig.solace, "consolidated-state-persist");
    }
    return store:createKafkaProducer(storeConfig.kafka, "consolidated-state-persist");
}

// Consumer which reads the persisted topic-registration/topic-deregistration/subscription/unsubscription events
public final store:Consumer websubEventsConsumer = check initWebSubEventsConsumer();

function initWebSubEventsConsumer() returns store:Consumer|error {
    var storeConfig = config:store;
    if storeConfig is store:SolaceMessageStore {
        return store:createSolaceConsumer(
                storeConfig.solace,
                config:state.events.consumerId,
                false
        );
    }
    return store:createKafkaConsumer(
            storeConfig.kafka,
            config:state.events.consumerId,
            config:state.events.topic,
            autoCommit = false,
            offsetReset = "earliest"
    );
}

# Initializes the WebSub event snapshot consumer.
#
# + return - A `store:Consumer` for the message store, or else return an `error` if the operation fails
public isolated function initWebSubEventSnapshotConsumer() returns store:Consumer|error {
    var storeConfig = config:store;
    if storeConfig is store:SolaceMessageStore {
        return store:createSolaceConsumer(
                storeConfig.solace,
                config:state.snapshot.consumerId,
                false
        );
    }
    return store:createKafkaConsumer(
            storeConfig.kafka,
            config:state.snapshot.consumerId,
            config:state.snapshot.topic,
            autoCommit = false,
            offsetReset = "earliest"
    );
}

# Retrieves a message producer per topic.
#
# + topic - The message store topic
# + return - A `store:Producer` for the message store, or else an `error` if the operation fails
public isolated function getMessageProducer(string topic) returns store:Producer|error {
    return statePersistProducer;
}
