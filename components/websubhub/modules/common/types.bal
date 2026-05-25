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
import ballerina/os;
import ballerina/websubhub;

# Represents a snapshot of the WebSubHub's state, containing all topics and subscriptions.
public type SystemStateSnapshot record {|
    # An array of current topic registrations in the hub
    websubhub:TopicRegistration[] topics;
    # An array of all verified subscriptions in the hub
    websubhub:VerifiedSubscription[] subscriptions;
|};

public type StaleSubscription record {|
    *websubhub:VerifiedSubscription;
    string status = "stale";
|};

public type SubscriptionDetails record {|
    string topic;
    string subscriberId;
|};

public type InvalidSubscriptionError distinct error<SubscriptionDetails>;

# Defines the configuration for the WebSubHub server endpoint.
public type ServerConfig record {|
    # The port on which the WebSubHub service will listen
    int port;
    # A unique identifier for this WebSubHub server instance
    string id = "websubhub-1";
    # Authentication configurations for securing the hub's endpoints
    JwtValidatorConfig auth?;
    # SSL/TLS configurations for the service endpoint
    http:ListenerSecureSocket secureSocket?;
|};

# Represents JWT validator configurations for JWT-based authentication.
public type JwtValidatorConfig record {|
    # The key used to extract the 'scope' claim from the JWT payload
    string scopeKey = "scope";
    # The expected issuer of the JWT, corresponding to the `iss` claim
    string issuer;
    # The expected audience for the JWT, corresponding to the `aud` claim
    string|string[] audience;
    # JWKS-based signature validation configurations
    JwksConfig signature?;
|};

# Represents the JWKS (JSON Web Key Set) configurations for JWT signature validation.
public type JwksConfig record {|
    # The URL of the JWKS endpoint
    string url;
    # SSL/TLS configurations for the JWKS client
    jwt:SecureSocket secureSocket?;
|};

# Defines configurations for retrieving and maintaining the server's state.
public type ServerStateConfig record {|
    # Configurations for retrieving the initial state snapshot from a consolidator service.
    record {|
        # The HTTP endpoint URL of the consolidator to get the state snapshot
        string url = os:getEnv("WEBSUBHUB_CONSOLIDATOR_URL");
        # Client configurations for the HTTP call to the consolidator
        HttpClientConfig config?;
    |} snapshot;
    # Configurations for consuming state update events from a message store.
    record {|
        # The message store topic that stores WebSub events for this server
        string topic;
        # The prefix used for the message-store consumer ID when handling state update events.
        # The full consumer ID is formed by concatenating `<consumerIdPrefix>` with `<server-id>`
        # (for example, `websub-events-consumer-hub-1`).
        string consumerIdPrefix;
    |} events;
|};

# Delivery mode — controls whether WSH or the broker owns the retry loop.
# WSH_RETRY: WSH applies its own HTTP retry loop (original behaviour, default).
# BROKER_RETRY: WSH delivers once per broker redelivery, then ACK/NACK/REJECTED signals the broker.
public enum DeliveryMode {
    WSH_RETRY,
    BROKER_RETRY
}

# Defines configurations for an HTTP client.
public type HttpClientConfig record {|
    # The maximum time (in seconds) to wait for a response before the request times out
    decimal timeout = 60;
    # Delivery mode: WSH_RETRY (default) keeps WSH HTTP retry loops; BROKER_RETRY delegates retry ownership to the broker
    DeliveryMode deliveryMode = WSH_RETRY;
    # Automatic HTTP retry settings used in WSH_RETRY mode
    RetryConfig 'retry?;
    # Broker signal and classification settings used in BROKER_RETRY mode
    BrokerRetryConfig brokerRetry?;
    # SSL/TLS configurations for the HTTP client
    http:ClientSecureSocket secureSocket?;
|};

# Automatic HTTP retry configuration for WSH_RETRY mode.
public type RetryConfig record {|
    *http:RetryConfig;
    # If true, the retry loop restarts indefinitely instead of stopping after `count` retries
    boolean resetOnExhaust = false;
|};

# Failure classification behavior — controls how WSH signals the broker in BROKER_RETRY mode.
public type FailureBehavior "recoverable"|"nonRecoverable";

# Controls how WSH classifies HTTP responses and signals the Solace broker in BROKER_RETRY mode.
# The broker owns max-redelivery counts, DMQ routing, and TTL.
public type BrokerRetryConfig record {|
    # HTTP status codes treated as successful delivery → broker ACK (message removed from queue)
    int[] ackStatusCodes = [200, 201, 202, 204];
    # HTTP status codes treated as temporary failures → broker NACK/FAILED (broker retries)
    int[] recoverableStatusCodes = [500, 502, 503, 504];
    # HTTP status codes treated as permanent failures → broker NACK/REJECTED (routed to DMQ)
    int[] nonRecoverableStatusCodes = [400, 401, 403, 404, 410];
    # Behavior when the status code is not in any of the above lists
    FailureBehavior unknownStatusCodes = "recoverable";
    # Behavior on request timeout (no HTTP response received)
    FailureBehavior timeoutError = "recoverable";
    # Behavior on network/connection-level errors (e.g. connection refused)
    FailureBehavior networkError = "recoverable";
    # Delay in seconds before NACKing to broker — controls redelivery rate (Solace redelivery is otherwise immediate)
    decimal interval = 3.0;
|};
