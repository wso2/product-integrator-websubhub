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

import ballerina/http;
import ballerina/jwt;
import ballerina/websubhub;
import ballerinax/kafka;

public type SystemStateSnapshot record {|
    websubhub:TopicRegistration[] topics;
    websubhub:VerifiedSubscription[] subscriptions;
|};

public type ServerConfig record {|
    int port;
    string serverId;
    JwtValidatorConfig auth?;
    http:ListenerSecureSocket secureSocket?;
|};

public type JwtValidatorConfig record {|
    string scopeKey;
    string issuer;
    string audience;
    jwt:ValidatorSignatureConfig signature?;
|};

public type ServerStateConfig record {|
    record {|
        string url;
        HttpClientConfig config?;
    |} snapshot;
    record {|
        string topic;
        string consumerGroup;
    |} events;
|};

public type KafkaConfig record {|
    KafkaConnectionConfig connection;
    KafkaConsumerConfig consumer;
|};

public type KafkaConnectionConfig record {|
    string|string[] bootstrapServers;
    kafka:SecureSocket secureSocket?;
    kafka:AuthenticationConfiguration auth?;
    kafka:SecurityProtocol securityProtocol = kafka:PROTOCOL_PLAINTEXT;
|};

public type KafkaConsumerConfig record {|
    int maxPollRecords;
    decimal pollingInterval = 10;
    decimal gracefulClosePeriod = 5;
|};

public type HttpClientConfig record {|
    decimal timeout = 60;
    http:RetryConfig 'retry?;
    http:ClientSecureSocket secureSocket?;
|};
