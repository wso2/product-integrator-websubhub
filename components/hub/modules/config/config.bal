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

import ballerina/os;

# Flag to check whether to enable/disable security
public configurable boolean securityOn = true;

# Server ID is used to uniquely identify each server 
# Each server must have a unique ID
public configurable string serverId = "server-1";

public final string serverIdentifier = os:getEnv("SERVER_ID") == "" ? serverId : os:getEnv("SERVER_ID");

# IP and Port of the Kafka bootstrap node
public configurable string kafkaBootstrapNode = "localhost:9092";

public final string kafkaUrl = os:getEnv("KAFKA_BOOTSTRAP_NODE") == "" ? kafkaBootstrapNode : os:getEnv("KAFKA_BOOTSTRAP_NODE");

# Maximum number of records returned in a single call to consumer-poll
public configurable int kafkaConsumerMaxPollRecords = ?;

public final int consumerMaxPollRecords = os:getEnv("KAFKA_CONSUMER_MAX_POLL_RECORDS") == "" ?
    kafkaConsumerMaxPollRecords : check int:fromString(os:getEnv("KAFKA_CONSUMER_MAX_POLL_RECORDS"));

# Kafka topic which is stores websub-events for this server
public configurable string websubEventsTopic = "websub-events";

# Consolidator HTTP endpoint to be used to retrieve current state-snapshot
public configurable string stateSnapshotEndpoint = "http://localhost:10001";

public final string stateSnapshotEndpointUrl = os:getEnv("STATE_SNAPSHOT_ENDPOINT") == "" ? stateSnapshotEndpoint : os:getEnv("STATE_SNAPSHOT_ENDPOINT");

# The interval in which Kafka consumers wait for new messages
public configurable decimal pollingInterval = 10;

# The period in which Kafka close method waits to complete
public configurable decimal gracefulClosePeriod = 5;

# The port that is used to start the hub
public configurable int hubPort = 9000;

# SSL keystore file path
public configurable string sslKeystorePath = "./resources/hub.keystore.jks";

# SSL keystore password
public configurable string sslKeystorePassword = "password";

# The period between retry requests
public configurable decimal messageDeliveryRetryInterval = 3;

# The maximum retry count
public configurable int messageDeliveryCount = 3;

# The message delivery timeout
public configurable decimal messageDeliveryTimeout = 10;

# The HTTP status codes for which the client should retry
public configurable int[] messageDeliveryRetryableStatusCodes = [500, 502, 503];

public final readonly & int[] retryableStatusCodes = check getRetryableStatusCodes(messageDeliveryRetryableStatusCodes).cloneReadOnly();

# The Oauth2 authorization related configurations
public configurable common:OAuth2Config oauth2Config = ?;

# The MTLS configurations related to Kafka connection
public configurable common:KafkaMtlsConfig kafkaMtlsConfig = ?;

# Consumer group name for `websub-events` consumer
public final string websubEventsConsumerGroup = os:getEnv("WEBSUB_EVENTS_CONSUMER_GROUP") == "" ? constructSystemConsumerGroup() : os:getEnv("WEBSUB_EVENTS_CONSUMER_GROUP");

isolated function constructSystemConsumerGroup() returns string {
    return string `websub-events-receiver-${serverIdentifier}-${common:generateRandomString()}`;
}

isolated function getRetryableStatusCodes(int[] configuredCodes) returns int[]|error {
    if os:getEnv("RETRYABLE_STATUS_CODES") is "" {
        return configuredCodes;
    }
    string[] statusCodes = re `,`.split(os:getEnv("RETRYABLE_STATUS_CODES"));
    return statusCodes.'map(i => check int:fromString(i.trim()));
}
