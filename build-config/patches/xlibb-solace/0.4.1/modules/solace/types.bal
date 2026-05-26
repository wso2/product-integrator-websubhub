// Copyright (c) 2025 WSO2 LLC. (http://www.wso2.org).
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

# The Solace service type.
public type Service distinct service object {
    // remote function onMessage(solace:Message message, solace:Caller caller) returns error?;
};

# Destination types - Topic and Queue
public type Topic record {|
    # The topic name
    string topicName;
|};

public type Queue record {|
    # The queue name
    string queueName;
|};

public type Destination Topic|Queue;

# Acknowledgement modes for message consumption
// Since we create this for session does it apply for producer? If so what does it do?
// Ans: It does not apply to producer. It is only for consumers and session level configuration
// in JCSMP is so that all consumers created on that session inherit the ack mode as a default
public enum AcknowledgementMode {
    AUTO_ACK,
    CLIENT_ACK
}

# Authentication configuration types
public type BasicAuthConfig record {|
    # The username for authentication
    string username;
    # The password for authentication (optional for some auth schemes)
    string password?;
|};

public type KerberosConfig record {|
    # The Kerberos service name used during authentication
    string serviceName = "solace";
    # The JAAS login context name to use for authentication
    string jaasLoginContext = "SolaceGSS";
    # Specifies whether to enable automatic reload of the JAAS configuration file
    boolean jaasConfigFileReloadEnabled = false;
|};

# OAuth2 Access Token authentication configuration
public type OAuth2AccessTokenAuth record {|
    # Issuer identifier URI for token validation
    string issuer;
    # The OAuth 2.0 access token for authentication
    string accessToken;
|};

# OpenID Connect (OIDC) ID Token authentication configuration
public type OidcIdTokenAuth record {|
    # Issuer identifier URI for token validation
    string issuer;
    # The OpenID Connect (OIDC) ID token for authentication
    string oidcToken;
|};

# OAuth2 authentication configuration (mutually exclusive - use either access token or ID token)
# When using OAuth2 authentication scheme, exactly one of OAuth2AccessTokenAuth or OidcIdTokenAuth must be provided
public type OAuth2Config OAuth2AccessTokenAuth|OidcIdTokenAuth;

# SSL/TLS certificate validation configuration
public type CertificateValidation record {|
    # Enable certificate validation
    // What if we disable validateDate and validateHostname but keep this enabled? Check JCSMP docs
    // Ans: We cannot do that as there are other validations like Certificate Chain Validation
    boolean enabled = true;
    # Validate the certificate's expiration date
    boolean validateDate = true;
    # Validate that the certificate's common name matches the broker hostname/IP
    boolean validateHostname = true;
|};

# Java KeyStore format
public const JKS = "jks";
# PKCS12 format
public const PKCS12 = "pkcs12";

# Represents the supported SSL store formats.
public type SslStoreFormat JKS|PKCS12;

# Trust store configuration for server certificate validation
public type TrustStore record {|
    # The URL or file path of the trust store
    string location;
    # The password for the trust store
    string password;
    # The format of the trust store file (JKS, PKCS12, etc.)
    SslStoreFormat format = JKS;
|};

# Key store configuration for client certificate authentication
public type KeyStore record {|
    # The URL or file path of the key store
    string location;
    # The password for the key store
    string password;
    # The password for the private key (if different from key store password)
    string keyPassword?;
    # The alias of the private key to use from the key store
    string keyAlias?;
    # The format of the key store file (JKS, PKCS12, etc.)
    SslStoreFormat format = JKS;
|};

# SSL protocol version 3.0
public const SSLv30 = "sslv3";
# TLS protocol version 1.0
public const TLSv10 = "tlsv1";
# TLS protocol version 1.1
public const TLSv11 = "tlsv11";
# TLS protocol version 1.2
public const TLSv12 = "tlsv12";
# SSL protocol version SSLv2Hello
public const SSLv2Hello = "SSLv2Hello";

# Represents the supported SSL/TLS protocol versions.
public type Protocol SSLv30|TLSv10|TLSv11|TLSv12|SSLv2Hello|string;

# SSL/TLS configuration for secure connections
public type SecureSocket record {|
    # The trust store configuration for server certificate validation
    TrustStore trustStore?;
    # The key store configuration for client certificate authentication
    KeyStore keyStore?;
    # The list of trusted common names for certificate validation
    string[] trustedCommonNames?;
    # The SSL protocols NOT to use
    Protocol[] excludedProtocols = [SSLv2Hello];
    # Certificate validation settings
    CertificateValidation validation = {};
|};

# Retry configuration for connection attempts
// Check if a backoff stragey is availble in JCSMP
// Ans: No backoff strategy is available in JCSMP
public type RetryConfig record {|
    # Number of times to retry connecting during initial connection (0 = no retries, -1 = infinite)
    int connectRetries = 0;
    # Number of connection retries per host when multiple hosts are specified
    int connectRetriesPerHost = 0;
    # Number of times to retry reconnecting after connection loss (-1 = infinite)
    int reconnectRetries = 3;
    # Time to wait between reconnection attempts in seconds
    decimal reconnectRetryWait = 3.0;
|};

# Common connection configuration shared between producer and consumer
public type CommonConnectionConfiguration record {|
    # The message VPN to connect to
    string vpnName = "default";
    # The authentication configuration (basic, Kerberos, or OAuth2)
    BasicAuthConfig|KerberosConfig|OAuth2Config auth?;
    # The SSL/TLS configuration for secure connections
    SecureSocket secureSocket?;
    # A unique client name to use to register to the appliance (auto-generated if not specified)
    string clientName?;
    # A description for the application client
    string clientDescription = "Ballerina Solace Connector";
    # The local interface IP address to bind for outbound connections
    string localAddress?;
    # The maximum time in seconds for a connection attempt
    decimal connectionTimeout = 30.0;
    # The maximum time in seconds for reading connection replies
    decimal readTimeout = 10.0;
    # ZLIB compression level (0 = disabled, 1-9 = compression)
    int compressionLevel = 0;
    # Enable transacted messaging
    boolean transacted = false;
    # Whether to generate a receive timestamp on incoming messages (set by broker)
    # When enabled, incoming messages will have receiveTimestamp automatically set
    boolean generateReceiveTimestamps = false;
    # Whether to generate a send timestamp in outgoing messages
    # When enabled, outgoing messages will have senderTimestamp automatically set if not already provided
    boolean generateSendTimestamps = false;
    # Whether to generate a sequence number in outgoing messages
    # When enabled, outgoing messages will have sequenceNumber automatically generated if not already set
    boolean generateSequenceNumbers = false;
    # Whether to calculate message expiration time in outgoing and incoming messages
    # When enabled, JCSMP calculates message expiration based on timeToLive field
    boolean calculateMessageExpiration = false;
    # Retry configuration for connection attempts
    RetryConfig retryConfig?;
|};

# Producer-specific configuration
# Note: Destination is passed at send-time, not specified in configuration
public type ProducerConfiguration record {|
    *CommonConnectionConfiguration;
|};

# Common consumer subscription fields
# Note: Flow control properties below only apply to FlowReceiver usage (queues and durable topic endpoints)
# They are ignored for direct topic subscriptions which use XMLMessageConsumer
public type CommonConsumerConfig record {|
    # Optional SQL-92 message selector for filtering messages on the broker before delivery
    # Applies to both queue consumers and durable topic endpoint subscriptions (flows only).
    # Not supported for direct topic subscriptions. Filters messages based on their properties and headers.
    # Example: "OrderType = 'URGENT' AND Priority > 5" - only messages matching this condition will be delivered.
    string selector?;
    # JCSMP message acknowledgement mode
    AcknowledgementMode ackMode = AUTO_ACK;
    # JCSMP flow control transport window size (1-255, default 255) - FlowReceiver only
    int transportWindowSize?;
    # Acknowledgement threshold as percentage of window size (1-75, default 0) - FlowReceiver only
    int ackThreshold?;
    # Acknowledgement timer in seconds (0.02 - 1.5, default 0) - FlowReceiver only
    decimal ackTimer = 0.0;
    # Auto-start the flow upon creation (default false) - FlowReceiver only
    boolean startState?;
    # Prevent receiving messages published on same session (default false) - FlowReceiver only
    boolean noLocal?;
    # Enable active/inactive flow indication (default false) - FlowReceiver only
    boolean activeFlowIndication?;
    # Number of reconnection attempts after flow goes down (-1 = infinite, default -1) - FlowReceiver only
    int reconnectTries?;
    # Wait time between reconnection attempts in seconds (min 0.05 seconds, default 3.0 seconds) - FlowReceiver only
    decimal reconnectRetryInterval = 3.0;
|};

# Queue consumer configuration for synchronous (pull-based) consumption
public type QueueSubscription record {|
    *CommonConsumerConfig;
    # The queue name to consume messages from
    string queueName;
    # Whether this is a temporary queue (auto-deleted when session disconnects)
    # Temporary queues are useful for short-lived, session-specific messaging patterns like request-reply.
    # If true, a temporary queue will be created; if false (default), uses a durable queue that must be pre-provisioned.
    boolean temporary = false;
|};

# Topic consumer configuration for synchronous (pull-based) consumption
public type TopicSubscription record {|
    *CommonConsumerConfig;
    // If all CommonConsumerConfig fields are FlowReceiver only we can have two different TopicConfigs, one for the durable case and one for the direct case
    # The topic name to subscribe to
    string topicName;
    # Endpoint type: DEFAULT (ephemeral/direct) or DURABLE (persisted on broker)
    EndpointType endpointType = DEFAULT;
    # Endpoint name - REQUIRED when endpointType is DURABLE (optional for DEFAULT)
    # Used to identify the durable topic endpoint on the broker. Must be unique for durable endpoints.
    string endpointName?;
|};

# Consumer subscription configuration (sealed: QueueConsumerConfig | TopicConsumerConfig)
public type ConsumerSubscription QueueSubscription|TopicSubscription;

# Consumer configuration for synchronous (pull-based) message consumption via MessageConsumer
public type ConsumerConfiguration record {|
    *CommonConnectionConfiguration;
    # The subscription configuration (queue or topic)
    ConsumerSubscription subscriptionConfig;
|};

# Delivery modes for messages
public enum DeliveryMode {
    # At-most-once delivery mode. Direct messages are not retained for disconnected clients and can be discarded
    # during congestion or failures. They can be reordered during network topology changes.
    # Most appropriate for high-rate, low-latency messaging applications.
    DIRECT,
    # Once-and-only-once delivery mode for Guaranteed Messaging. Persistent messages cannot be lost once acknowledged,
    # cannot be reordered during topology changes, and cannot be delivered more than once (unless redelivered flag is set).
    # Retained on durable endpoints for disconnected clients. Recommended for applications requiring persistent storage
    # and reliable message delivery.
    PERSISTENT
}

# Endpoint types for producer destinations
public enum EndpointType {
    DEFAULT,
    DURABLE
}

# Common service subscription fields (listener polling configuration)
# Note: Flow control properties below only apply to FlowReceiver usage (queues and durable topic endpoints)
# They are ignored for direct topic subscriptions which use XMLMessageConsumer
public type CommonServiceConfig record {|
    # JCSMP acknowledgement mode
    AcknowledgementMode ackMode = AUTO_ACK;
    # Optional SQL-92 message selector for filtering messages on the broker before delivery
    # Applies to both queue consumers and durable topic endpoint subscriptions (flows only).
    # Not supported for direct topic subscriptions. Filters messages based on their properties and headers.
    # Example: "OrderType = 'URGENT' AND Priority > 5" - only messages matching this condition will be delivered.
    string selector?;
    # Polling interval in seconds (how often to poll for messages)
    decimal pollingInterval = 10;
    # Receive timeout in seconds (how long to wait per polling cycle)
    decimal receiveTimeout = 10.0;
    # Whether to auto-start polling when listener starts
    boolean autoStart = true;
    # JCSMP flow control transport window size (1-255, default 255) - FlowReceiver only
    int transportWindowSize?;
    # Acknowledgement threshold as percentage of window size (1-75, default 0) - FlowReceiver only
    int ackThreshold?;
    # Acknowledgement timer in seconds (0.02 - 1.5 seconds, default 0.0 seconds) - FlowReceiver only
    decimal ackTimer = 0.0;
    # Prevent receiving messages published on same session (default false) - FlowReceiver only
    boolean noLocal?;
    # Enable active/inactive flow indication (default false) - FlowReceiver only
    boolean activeFlowIndication?;
    # Number of reconnection attempts after flow goes down (-1 = infinite, default -1) - FlowReceiver only
    int reconnectTries?;
    # Wait time between reconnection attempts in seconds (min 0.05 seconds, default 3.0 seconds) - FlowReceiver only
    decimal reconnectRetryInterval = 3.0;
|};

# Queue service configuration for asynchronous (push-based) consumption via Listener
public type QueueServiceConfig record {|
    *CommonServiceConfig;
    # The queue name to consume messages from
    string queueName;
|};

# Topic service configuration for asynchronous (push-based) consumption via Listener
public type TopicServiceConfig record {|
    *CommonServiceConfig;
    # The topic name to subscribe to
    string topicName;
    # Endpoint type: DEFAULT (ephemeral/direct) or DURABLE (persisted on broker)
    EndpointType endpointType = DEFAULT;
    # Endpoint name - REQUIRED when endpointType is DURABLE (optional for DEFAULT)
    # Used to identify the durable topic endpoint on the broker. Must be unique for durable endpoints.
    string endpointName?;
|};

# Service subscription configuration (sealed: QueueServiceConfig | TopicServiceConfig)
public type ServiceConfiguration QueueServiceConfig|TopicServiceConfig;

// For the fields that are set by the broker mention that in the comment
# Message type for publishing/consuming
public type Message record {|
    # The binary payload of the message
    byte[] payload;
    # Delivery mode for the message (DIRECT, PERSISTENT, or NON_PERSISTENT)
    // Double check if we can set this in the message level. If PERSISTENT and NON_PERSISTENT are same we can remove one
    // Ans: Yes, it can ONLY be set at message level. We can remove NON_PERSISTENT as its same as PERSISTENT
    DeliveryMode deliveryMode = DIRECT;
    # Message priority (0-255, where 0 is lowest and 255 is highest)
    byte priority?;
    # Time-to-live in milliseconds (0 = never expires, only for PERSISTENT/NON_PERSISTENT modes)
    int timeToLive?;
    # Application-defined message ID for correlation
    // Can we make it messageId and messageType
    // Ans: messageId is a deprecated field in JCSMP used for acknowledgements. Since these two fields are
    // supposed application defined I feel we should keep them as is to avoid confusion.
    string applicationMessageId?;
    # Application-defined message type
    // Check if this is only string? And why is it there?
    // Ans: this and applicationId are both string and are used by applications only
    string applicationMessageType?;
    # Correlation ID for request-reply patterns
    string correlationId?;
    # Reply-to destination for request-reply patterns
    Destination replyTo?;
    # Sender ID (set by client or broker)
    string senderId?;
    # Sender timestamp in UTC milliseconds from epoch
    int senderTimestamp?;
    # Receive timestamp in UTC milliseconds from epoch (set by broker)
    int receiveTimestamp?;
    # Sequence number for message ordering (application-managed)
    # Set by the application for message ordering and duplicate detection. Can be auto-generated if sequence number
    # generation is enabled in the session. Once set, value is preserved across message resends and available on both
    # direct and guaranteed message delivery. Note: distinct from broker-generated topicSequenceNumber.
    int sequenceNumber?;
    # Whether message was previously delivered
    boolean redelivered?;
    # Number of times this message has been delivered
    int deliveryCount?;
    # Whether the message is eligible to be moved to the Dead Message Queue (DMQ) when:
    # - Max redelivery count is exceeded (FAILED nack path), OR
    # - The message is negatively acknowledged with REJECTED (nack with false).
    # Default is false. Set to true to enable DMQ routing.
    boolean dmqEligible?;
    # Properties map for custom key-value pairs
    // String may not be enough here. Use a map<string|boolean> or map<anydata>
    // Ans: It expects a SDTMap so for now we can keep it as map<anydata>
    map<anydata> properties?;
    # Application-specific user data attachment (max 36 bytes)
    byte[] userData?;
|};
