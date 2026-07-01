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
    # Configuration for the content-unaware (passthrough) publish endpoint
    PublishEndpointConfig publishEndpoint = {};
|};

# Defines configuration for the content-unaware (passthrough) publish endpoint. This endpoint reads the
# request body as raw bytes without parsing, preserving any `Content-Type`, so publishers can send
# arbitrary content (e.g. `image/png`, `application/pdf`) and large payloads with a single in-memory copy.
# It is additive to the standard WebSub publish endpoint on `/hub` (`hub.mode=publish`).
public type PublishEndpointConfig record {|
    # When `true`, the raw-bytes passthrough publish endpoint is attached to the hub listener
    boolean enabled = true;
    # The path on which the passthrough publish endpoint is hosted. Must differ from the hub path (`/hub`)
    string path = "/hub/publish";
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
    # Configurations for state-sync retries.
    record {|
        # Number of maximum retries for state-sync
        int maxRetries = 5;
        # State sync retry interval
        decimal retryInterval = 3.0;
    |} sync = {};
|};

# Defines configurations for an HTTP client.
public type HttpClientConfig record {|
    # The maximum time (in seconds) to wait for a response before the request times out
    decimal timeout = 60;
    # Automatic retry settings for failed HTTP requests
    http:RetryConfig 'retry?;
    # SSL/TLS configurations for the HTTP client
    http:ClientSecureSocket secureSocket?;
|};

# # Defines configurations for content delivery client.
public type ContentDeliveryClientConfig record {|
    # When `true` (default), the stored payload bytes are delivered to subscribers verbatim with the
    # recorded `Content-Type`, skipping the JSON parse/re-encode on the delivery path (content-unaware
    # passthrough). Set to `false` to restore the legacy content-aware behaviour for JSON payloads.
    boolean contentPassthrough = true;
    # The maximum time (in seconds) to wait for a response before the request times out
    decimal timeout = 60;
    # Automatic retry settings for failed content delivery requests
    record {|
        *MessageStoreRetryConfig;
        *HttpRetryConfig;
    |} 'retry?;
    # SSL/TLS configurations for the HTTP client
    http:ClientSecureSocket secureSocket?;
|};

# Provides configurations for controlling the retrying behavior in failure scenarios.
public type HttpRetryConfig record {|
    *http:RetryConfig;
    # When set to `true`, the internal retry counter is reset to zero after the count attempts are exhausted
    boolean resetOnExhaust = false;
|};

# Provides configurations for controlling the retrying behavior in failure scenarios using message-store acknowledgements.
public type MessageStoreRetryConfig record {|
    # Delay in seconds before retrying a failed message delivery
    decimal delay = 30;
    # HTTP status for which should trigger broker redelivery
    int[] redeliver?;
    # HTTP status for that should route the message to the DLQ
    int[] deadLetter?;
    # Action to take when the derived response does not match any entry in `redeliver` or `deadLetter`
    RetryAction defaultAction = "fail";
    # Action to take when delivery fails due to a network-level failure
    RetryAction networkFailureAction = "fail";
|};

public type RetryAction "redeliver"|"deadLetter"|"fail";
