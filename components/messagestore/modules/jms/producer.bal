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
        lock {
            jms:BytesMessage jmsMessage = {
                correlationId: message.id,
                content: message.payload.cloneReadOnly()
            };
            check self.producer->sendTo(
                {'type: jms:TOPIC, name: topic},
                message = jmsMessage
            );
        }
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
