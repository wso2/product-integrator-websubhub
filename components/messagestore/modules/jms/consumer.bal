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
import messagestore.dlq;

import ballerina/log;
import ballerinax/java.jms;

isolated client class Consumer {
    *api:Consumer;

    private jms:MessageConsumer consumer;
    private jms:Session session;
    private jms:Connection connection;
    private final string subscriberName;
    private final int readTimeout;
    private final string? dlqTopic;
    private final string topic;
    private final jms:ConnectionConfiguration & readonly connectionConfig;

    isolated function init(Config config, string topic, string subscriberName, string? dlqTopic = ()) returns error? {
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
        jms:Session session = check connection->createSession(jms:SESSION_TRANSACTED);
        self.consumer = check session.createConsumer({
            'type: jms:DURABLE,
            destination: {'type: jms:TOPIC, name: topic},
            subscriberName
        });
        self.connection = connection;
        self.session = session;
        self.subscriberName = subscriberName;
        self.readTimeout = <int>(config.consumer.receiveTimeout * 1000);
        self.dlqTopic = dlqTopic;
        self.topic = topic;
    }

    isolated remote function receive() returns api:Message|error? {
        jms:MessageConsumer currentConsumer;
        lock {
            currentConsumer = self.consumer;
        }
        jms:Message? receivedMsg = check currentConsumer->receive(self.readTimeout);
        if receivedMsg !is jms:BytesMessage {
            return;
        }
        api:Message message = {
            id: receivedMsg.correlationId,
            payload: receivedMsg.content
        };
        return message;
    }

    isolated remote function ack(api:Message message) returns error? {
        lock {
            return self.session->'commit();
        }
    }

    isolated remote function nack(api:Message message) returns error? {
        lock {
            return self.session->'rollback();
        }
    }

    isolated remote function deadLetter(api:Message message) returns error? {
        api:Producer? _dlqProducer;
        lock {
            _dlqProducer = dlqProducer;
        }
        check dlq:publish(self.dlqTopic, _dlqProducer, message);
        lock {
            return self.session->'commit();
        }
    }

    isolated remote function close(api:ClosureIntent intent = api:TEMPORARY) returns error? {
        lock {
            error? consumerCloseResult = self.consumer->close();
            if intent is api:PERMANENT {
                error? unsubscribeResult = self.session->unsubscribe(self.subscriberName);
                if unsubscribeResult is error {
                    return unsubscribeResult;
                }
            }
            error? sessionCloseResult = self.session->close();
            error? connectionCloseResult = self.connection->close();
            if consumerCloseResult is error {
                return consumerCloseResult;
            }
            if sessionCloseResult is error {
                return sessionCloseResult;
            }
            return connectionCloseResult;
        }
    }

    isolated remote function reconnect() returns error? {
        jms:Connection|error connectionResult = new (self.connectionConfig);
        if connectionResult is error {
            log:printWarn("Error while creating JMS connection during consumer reconnect", 'error = connectionResult);
            return connectionResult;
        }
        jms:Session|error sessionResult = connectionResult->createSession(jms:SESSION_TRANSACTED);
        if sessionResult is error {
            error? closeResult = connectionResult->close();
            if closeResult is error {
                log:printWarn("Error while closing JMS connection after consumer reconnect failure", 'error = closeResult);
            }
            log:printWarn("Error while creating JMS session during consumer reconnect", 'error = sessionResult);
            return sessionResult;
        }
        jms:MessageConsumer|error consumerResult = sessionResult.createConsumer({
            'type: jms:DURABLE,
            destination: {'type: jms:TOPIC, name: self.topic},
            subscriberName: self.subscriberName
        });
        if consumerResult is error {
            error? closeResult = connectionResult->close();
            if closeResult is error {
                log:printWarn("Error while closing JMS connection after consumer reconnect failure", 'error = closeResult);
            }
            log:printWarn("Error while creating JMS message consumer during reconnect", 'error = consumerResult);
            return consumerResult;
        }
        lock {
            error? consumerCloseErr = self.consumer->close();
            if consumerCloseErr is error {
                log:printWarn("Error while closing old JMS consumer during reconnect", 'error = consumerCloseErr);
            }
            error? sessionCloseErr = self.session->close();
            if sessionCloseErr is error {
                log:printWarn("Error while closing old JMS session during reconnect", 'error = sessionCloseErr);
            }
            error? connectionCloseErr = self.connection->close();
            if connectionCloseErr is error {
                log:printWarn("Error while closing old JMS connection during reconnect", 'error = connectionCloseErr);
            }
            self.connection = connectionResult;
            self.session = sessionResult;
            self.consumer = consumerResult;
        }
    }
}

# Initialize a consumer for JMS message store.
#
# + topic - The JMS topic to which the consumer should received events for
# + defaultSubscriberId - The JMS durable subscriber Id to which the messages should be received
# + config - The JMS connection configurations
# + systemConsumer - Flag to indicate whether this is a system consumer
# + meta - The meta data required to resolve the consumer configurations
# + return - An `api:ConsumerResult` tuple of the consumer and its metadata, or an `error` if the operation fails
public isolated function createConsumer(string topic, string defaultSubscriberId, Config config,
        boolean systemConsumer = false, record {} meta = {}) returns api:ConsumerResult|error {
    string? dlqTopic = check dlq:resolveDeadLetterTopic(config.consumer.deadLetterTopic, meta);
    if dlqTopic is string {
        check initJmsDlqProducer(config);
    }
    string subscriberName = systemConsumer ? defaultSubscriberId : string `consumer-${defaultSubscriberId}`;
    Consumer consumer = check new Consumer(config, topic, subscriberName, dlqTopic);
    return [consumer, {"subscriber": subscriberName}];
}
