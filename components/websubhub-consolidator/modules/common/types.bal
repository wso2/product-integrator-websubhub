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

import ballerina/crypto;
import ballerina/http;
import ballerina/websubhub;
import ballerinax/kafka;

# Represents a snapshot of the WebSubHub's state, containing all topics and subscriptions.
public type SystemStateSnapshot record {|
    # An array of current topic registrations in the hub
    websubhub:TopicRegistration[] topics;
    # An array of all verified subscriptions in the hub
    websubhub:VerifiedSubscription[] subscriptions;
|};

# Defines the configuration for the WebSubHub consolidator server endpoint.
public type ServerConfig record {|
    # The port on which the WebSubHub consolidator service will listen
    int port;
    # SSL/TLS configurations for the service endpoint
    http:ListenerSecureSocket secureSocket?;
|};

# Defines configurations for retrieving and maintaining the server's state.
public type ServerStateConfig record {|
    # Configurations related to state-snapshot Kafka topic
    KafkaTopicConfig snapshot;
    # Configurations related to state update events Kafka topic
    KafkaTopicConfig events;
|};

public type KafkaTopicConfig record {|
    string topic;
    string consumerGroup;
|};

public type KafkaMtlsConfig record {|
    crypto:TrustStore|string cert;
    record {|
        crypto:KeyStore keyStore;
        string keyPassword?;
    |}|kafka:CertKey key?;
|};

# Defines the complete set of Kafka configurations required for the application.
public type KafkaConfig record {|
    # Kafka connection configurations
    KafkaConnectionConfig connection;
    # Kafka consumer-specific configurations
    KafkaConsumerConfig consumer;
|};

# Defines the configurations for establishing a connection to a Kafka cluster.
public type KafkaConnectionConfig record {|
    # A list of remote server endpoints for the Kafka brokers (e.g., "localhost:9092")
    string|string[] bootstrapServers;
    # SSL/TLS configurations for the Kafka connection
    kafka:SecureSocket secureSocket?;
    # Authentication-related configurations for the Kafka connection
    kafka:AuthenticationConfiguration auth?;
    # The security protocol to use for the broker connection (e.g., PLAINTEXT, SSL)
    kafka:SecurityProtocol securityProtocol = kafka:PROTOCOL_PLAINTEXT;
|};

# Defines configurations for the Kafka consumer.
public type KafkaConsumerConfig record {|
    # The maximum number of records to return in a single call to `poll` function
    int maxPollRecords;
    # The polling interval in seconds for fetching new records
    decimal pollingInterval = 10;
    # The timeout duration (in seconds) for a graceful shutdown of the consumer
    decimal gracefulClosePeriod = 5;
|};
