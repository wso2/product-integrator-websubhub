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

import websubhub.consolidator.config;

import ballerinax/kafka;

// Producer which persist the current consolidated in-memory state of the system
kafka:ProducerConfiguration statePersistConfig = {
    clientId: "consolidated-state-persist",
    acks: "1",
    retryCount: 3,
    secureSocket: config:kafka.connection.secureSocket,
    securityProtocol: config:kafka.connection.securityProtocol
};
public final kafka:Producer statePersistProducer = check new (config:kafka.connection.bootstrapServers, statePersistConfig);

// Consumer which reads the persisted topic-registration/topic-deregistration/subscription/unsubscription events
public final kafka:ConsumerConfiguration websubEventConsumerConfig = {
    groupId: config:state.events.consumerGroup,
    offsetReset: "earliest",
    topics: [config:state.events.topic],
    secureSocket: config:kafka.connection.secureSocket,
    securityProtocol: config:kafka.connection.securityProtocol,
    maxPollRecords: config:kafka.consumer.maxPollRecords
};
public final kafka:Consumer websubEventConsumer = check new (config:kafka.connection.bootstrapServers, websubEventConsumerConfig);
