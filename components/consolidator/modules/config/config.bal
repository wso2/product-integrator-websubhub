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

import consolidator.common;

import ballerina/os;

# IP and Port of the Kafka bootstrap node
public configurable string kafkaBootstrapNode = "localhost:9092";

public final string kafkaUrl = os:getEnv("KAFKA_BOOTSTRAP_NODE") == "" ? kafkaBootstrapNode : os:getEnv("KAFKA_BOOTSTRAP_NODE");

# Kafka topic which stores websub-events for this server
public configurable string websubEventsTopic = "websub-events";

# Kafka topic which stores the current snapshot for the websub-events
public configurable string websubEventsSnapshotTopic = "websub-events-snapshot";

# The interval in which Kafka consumers wait for new messages
public configurable decimal pollingInterval = 10;

# The period in which Kafka close method waits to complete
public configurable decimal gracefulClosePeriod = 5;

# The MTLS configurations related to Kafka connection
public configurable common:KafkaMtlsConfig kafkaMtlsConfig = ?;

# The port that is used to start the HTTP endpoint for consolidator
public configurable int consolidatorHttpEndpointPort = 10001;

# Consumer group name for `websub-events` consumer
public final string websubEventsConsumerGroup = os:getEnv("WEBSUB_EVENTS_CONSUMER_GROUP") == "" ? constructSystemConsumerGroup("websub-events") : os:getEnv("WEBSUB_EVENTS_CONSUMER_GROUP");

# Consumer group name for `websub-events` consumer
public final string websubEventsSnapshotConsumerGroup = os:getEnv("WEBSUB_EVENTS_SNAPSHOT_CONSUMER_GROUP") == "" ? constructSystemConsumerGroup("websub-events-snapshot") : os:getEnv("WEBSUB_EVENTS_SNAPSHOT_CONSUMER_GROUP");

isolated function constructSystemConsumerGroup(string prefix) returns string {
    return string `${prefix}-receiver-consolidator-${common:generateRandomString()}`;
}
