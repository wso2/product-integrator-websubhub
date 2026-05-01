// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.org).
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
import ballerina/os;

import xlibb/solace;

public type Config record {|
    *SolaceConnectionConfig;
    # Solace consumer-specific configurations
    SolaceConsumerConfig consumer;
    SolaceAdminConfig admin;
    # Solace queue configurations
    SolaceQueueConfig queue;
|};

# Defines the configurations for establishing a connection to a Solace event broker.
public type SolaceConnectionConfig record {|
    # The broker URL with format: [protocol:]host[:port]
    string url = os:getEnv("SOLACE_BROKER_URL");
    # The message VPN to connect to
    string messageVpn;
    # The maximum time in seconds for a connection attempt
    decimal connectionTimeout = 30.0;
    # The maximum time in seconds for reading connection replies
    decimal readTimeout = 10.0;
    # The SSL/TLS configuration for secure connections
    solace:SecureSocket secureSocket?;
    # The authentication configuration (basic, Kerberos, or OAuth2)
    solace:BasicAuthConfig|solace:KerberosConfig|solace:OAuth2Config? auth = {
        username: os:getEnv("SOLACE_USERNAME"),
        password: os:getEnv("SOLACE_USER_PASSWORD")
    };
    # Retry configuration for connection attempts
    solace:RetryConfig retryConfig = {
        connectRetries: 3,
        connectRetriesPerHost: 2,
        reconnectRetries: 3,
        reconnectRetryWait: 5.0
    };
|};

# Defines configurations for the Solace consumer.
public type SolaceConsumerConfig record {|
    # The timeout to wait for one receive call to the Solace message store
    decimal receiveTimeout = 10;
|};

# Configuration for creating and managing a Solace queue.
public type SolaceQueueConfig record {|
    # Prefix used when generating the Solace queue name for consumer queues.
    string queueNamePrefix?;
    # DLQ additional configurations
    record {|
        # Prefix used when generating the Solace DLQ name.
        string prefix = "dlq-";
        # Delete the custom DLQ on unsubscription request. 
        boolean deleteCustomOnUbsubscription = true;
    |} dlq?;
    # Maximum message spool quota for the queue in MB.
    int messageQueueQuota = 5000;
    # Client username that owns the queue.
    string queueOwner;
    # Permission level granted to non-owner clients.
    string nonOwnerPermission = "no-access";
    # Enables tracking of message delivery attempts.
    boolean deliveryCountEnabled = true;
    # Indicates whether message TTL should be respected.
    boolean respectTtl = false;
    # Maximum allowed TTL for messages in seconds. A value of `0` indicates no explicit maximum.
    int maxTtl = 0;
    # Redelivery configuration.
    record {|
        # Maximum number of redelivery attempts.
        int maxCount;
    |}|record {|
        # Indicates whether messages should be retried indefinitely.
        boolean tryForever = true;
    |} redeliver?;
|};

# Defines configurations for the Solace administrator.
public type SolaceAdminConfig record {|
    # The Solace Admin API URL
    string url = os:getEnv("SOLACE_SEMP_URL");
    # The maximum time to wait (in seconds) for a response before closing the connection
    decimal timeout = 30;
    # The SSL/TLS configuration for secure connections
    http:ClientSecureSocket secureSocket?;
    # The authentication configuration
    http:CredentialsConfig auth = {
        username: os:getEnv("SOLACE_SEMP_USERNAME"),
        password: os:getEnv("SOLACE_SEMP_USER_PASSWORD")
    };
    # Retry configuration
    http:RetryConfig retryConfig?;
|};
