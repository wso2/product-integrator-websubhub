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

# Reserved MapMessage key under which the raw payload bytes are stored. ballerinax/java.jms does not
# expose JMS string user-properties at the Ballerina level, so metadata (e.g. the x-hub-contentType
# used to reconstruct the delivery Content-Type) is carried as ordinary MapMessage entries alongside
# the payload. The metadata copy loop skips this key to prevent a metadata entry from overwriting the
# payload.
const string JMS_PAYLOAD_KEY = "__payload";

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
        // Carry the payload and any metadata in a single MapMessage: the raw bytes under the reserved
        // JMS_PAYLOAD_KEY (MapMessage supports byte[] entries), and each metadata entry as a string so
        // it survives the broker round-trip and the consumer can restore api:Message.metadata.
        map<anydata> content = {};
        content[JMS_PAYLOAD_KEY] = message.payload;
        map<string|string[]>? metadata = message.metadata;
        if metadata is map<string|string[]> {
            foreach var [key, value] in metadata.entries() {
                if key == JMS_PAYLOAD_KEY {
                    continue;
                }
                // MapMessage entries are scalar; flatten a multi-valued header to its first element.
                // The only key the hub relies on (x-hub-contentType) is single-valued.
                content[key] = value is string[] ? (value.length() > 0 ? value[0] : "") : value;
            }
        }
        jms:MapMessage jmsMessage = {
            correlationId: message.id,
            content
        };
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
