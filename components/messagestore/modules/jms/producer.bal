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

import messagestore.api;

import ballerina/log;
import ballerinax/java.jms;

public isolated client class Producer {
    *api:Producer;

    private jms:MessageProducer producer;
    private jms:Connection connection;
    private final jms:ConnectionConfiguration & readonly connectionConfig;

    public isolated function init(string clientName, Config config) returns error? {
        jms:ConnectionConfiguration connectionConfig = {
            initialContextFactory: config.initialContextFactory,
            providerUrl: config.providerUrl,
            connectionFactoryName: config.connectionFactoryName,
            username: config.username,
            password: config.password,
            properties: config.properties
        };
        self.connectionConfig = connectionConfig.cloneReadOnly();
        jms:Connection connection = check new (connectionConfig);
        jms:Session session = check connection->createSession();
        self.producer = check session.createProducer();
        self.connection = connection;
    }

    isolated remote function send(string topic, api:Message message) returns error? {
        // Encode the message as a MapMessage so that metadata (e.g. the original Content-Type)
        // can travel alongside the payload through the JMS broker. MapMessage.content is a
        // map<anydata> that accepts both byte[] (for the payload) and string (for metadata)
        // without requiring a JAR patch or property-name mangling — confirmed by live test against
        // ActiveMQ: hyphenated keys such as "x-hub-contentType" are accepted and round-trip cleanly.
        //
        // The payload is stored under the reserved key JMS_PAYLOAD_KEY. All metadata entries are
        // stored as top-level string values. Multi-valued metadata is flattened to its first element
        // (JMS MapMessage values are scalar; full multi-value support would need a different encoding).
        map<anydata> content = {[JMS_PAYLOAD_KEY]: message.payload};
        map<string|string[]>? metadata = message.metadata;
        if metadata is map<string|string[]> {
            foreach var [k, v] in metadata.entries() {
                if k == JMS_PAYLOAD_KEY {
                    // Skip: this key is reserved for the payload bytes and must not be
                    // overwritten by metadata. HTTP request headers cannot legally start with
                    // "__" so this guard should never fire in practice, but is kept for safety.
                    continue;
                }
                content[k] = v is string[] ? (v.length() > 0 ? v[0] : "") : v;
            }
        }
        jms:MapMessage jmsMessage = {
            correlationId: message.id,
            content
        };
        log:printDebug("[JMS MessageStore] Publishing message",
                topic = topic, messageId = message.id ?: "(none)",
                payloadSize = message.payload.length());
        check self.producer->sendTo(
            {'type: jms:TOPIC, name: topic},
            message = jmsMessage
        );
    }

    isolated remote function close() returns error? {
        lock {
            error? producerCloseResult = self.producer->close();
            error? connectionCloseResult = self.connection->close();
            if producerCloseResult is error {
                return producerCloseResult;
            }
            return connectionCloseResult;
        }
    }

    isolated remote function reconnect() returns error? {
        lock {
            error? result = self->close();
            if result is error {
                log:printWarn("Error while closing JMS producer during reconnect", 'error = result);
            }
            jms:Connection|error connectionResult = new (self.connectionConfig);
            if connectionResult is error {
                log:printWarn("Error while creating the JMS connection when reconnect", 'error = connectionResult);
                return connectionResult;
            }
            jms:Session|error sessionResult = connectionResult->createSession();
            if sessionResult is error {
                error? closeResult = connectionResult->close();
                if closeResult is error {
                    log:printWarn("Error while closing JMS connection after reconnect failure", 'error = closeResult);
                }
                return sessionResult;
            }
            jms:MessageProducer|error producerResult = sessionResult.createProducer();
            if producerResult is error {
                error? closeResult = connectionResult->close();
                if closeResult is error {
                    log:printWarn("Error while closing JMS connection after reconnect failure", 'error = closeResult);
                }
                return producerResult;
            }
            self.producer = producerResult;
            self.connection = connectionResult;
        }
    }
}
