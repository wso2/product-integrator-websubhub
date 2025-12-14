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

import xlibb/solace;
import ballerina/http;

# Defines the Solace message store configurations
public type SolaceMessageStore record {|
    # Configurations related to Solace message store connection    
    SolaceConfig solace;
|};

public type SolaceConfig record {|
    *SolaceConnectionConfig;
    # Solace consumer-specific configurations
    SolaceConsumerConfig consumer;
    SolaceAdminConfig admin;
|};

# Defines the configurations for establishing a connection to a Solace event broker.
public type SolaceConnectionConfig record {|
    # The broker URL with format: [protocol:]host[:port]
    string url;
    # The message VPN to connect to
    string messageVpn;
    # The maximum time in seconds for a connection attempt
    decimal connectionTimeout = 30.0;
    # The maximum time in seconds for reading connection replies
    decimal readTimeout = 10.0;
    # The SSL/TLS configuration for secure connections
    solace:SecureSocket secureSocket?;
    # The authentication configuration (basic, Kerberos, or OAuth2)
    solace:BasicAuthConfig|solace:KerberosConfig|solace:OAuth2Config auth?;
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

# Defines configurations for the Solace administrator.
public type SolaceAdminConfig record {|
    # The Solace Admin API URL
    string url;
    # The maximum time to wait (in seconds) for a response before closing the connection
    decimal timeout = 30;
    # The SSL/TLS configuration for secure connections
    http:ClientSecureSocket secureSocket?;
    # The authentication configuration
    http:CredentialsConfig auth;
    # Retry configuration
    http:RetryConfig retryConfig?;
|};
