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

// Server configuration related environment variables
public const SERVER_PORT = "SERVER_PORT";
public const SERVER_ID = "SERVER_ID";
public const SERVER_KEYSTORE = "SERVER_KEYSTORE";
public const SERVER_KEYSTORE_PASSWORD = "SERVER_KEYSTORE_PASSWORD";

// Security related environment variables
public const JWT_ISSUER = "JWT_ISSUER";
public const JWT_AUDIENCE = "JWT_AUDIENCE";
public const JWT_SCOPE_KEY = "JWT_SCOPE_KEY";
public const JWKS_URL = "JWKS_URL";
public const JWKS_CLIENT_TRUSTSTORE = "JWKS_CLIENT_TRUSTSTORE";
public const JWKS_CLIENT_TRUSTSTORE_PASSWORD = "JWKS_CLIENT_TRUSTSTORE_PASSWORD";

// Server state related environment variables
public const STATE_SNAPSHOT_URL = "STATE_SNAPSHOT_URL";
public const STATE_UPDATE_EVENTS_TOPIC = "STATE_UPDATE_EVENTS_TOPIC";
public const STATE_UPDATE_EVENTS_CONSUMER_GROUP = "STATE_UPDATE_EVENTS_CONSUMER_GROUP";

// Kafka connection related environment variables
public const KAFKA_BOOTSTRAP_SERVERS = "KAFKA_BOOTSTRAP_SERVERS";
public const KAFKA_PROTOCOL_NAME = "KAFKA_PROTOCOL_NAME";
public const KAFKA_SECURITY_PROTOCOL = "KAFKA_SECURITY_PROTOCOL";
public const KAFKA_CLIENT_KEYSTORE = "KAFKA_CLIENT_KEYSTORE";
public const KAFKA_CLIENT_KEYSTORE_PASSWORD = "KAFKA_CLIENT_KEYSTORE_PASSWORD";
public const KAFKA_CLIENT_TRUSTSTORE = "KAFKA_CLIENT_TRUSTSTORE";
public const KAFKA_CLIENT_TRUSTSTORE_PASSWORD = "KAFKA_CLIENT_TRUSTSTORE_PASSWORD";

// Kafka consumer related environment variables
public const KAFKA_CONSUMER_MAX_POLL_RECORDS = "KAFKA_CONSUMER_MAX_POLL_RECORDS";

// Message delivery related environment variables
public const MSG_DELIVERY_RETRYABLE_STATUS_CODES = "MSG_DELIVERY_RETRYABLE_STATUS_CODES";
