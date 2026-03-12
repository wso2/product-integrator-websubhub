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

import ballerinax/java.jms;

isolated client class JmsProducer {
    *Producer;

    private final jms:MessageProducer producer;

    isolated function init(jms:Connection connection) returns error? {

        jms:Session session = check connection->createSession();
        self.producer = check session.createProducer();
    }

    isolated remote function send(string topic, Message message) returns error? {
        jms:BytesMessage jmsMessage = {
            content: message.payload
        };
        check self.producer->sendTo(
            {'type: jms:TOPIC, name: topic},
            message = jmsMessage
        );
    }

    isolated remote function close() returns error? {
        return self.producer->close();
    }
}

isolated client class JmsConsumer {
    *Consumer;

    private final jms:MessageConsumer consumer;
    private final jms:Session session;
    private final string subscriberName;
    private final int readTimeout;
    private final string? dlqTopic;

    isolated function init(jms:Session session, JmsConsumerConfig config, string topic, string subscriberName, string? dlqTopic = ()) returns error? {

        self.session = session;
        self.consumer = check session.createConsumer({
            'type: jms:DURABLE,
            destination: {
                'type: jms:TOPIC,
                name: topic
            },
            subscriberName
        });
        self.subscriberName = subscriberName;
        self.readTimeout = <int>(config.receiveTimeout * 1000);
        self.dlqTopic = dlqTopic;
    }

    isolated remote function receive() returns Message|error? {
        jms:Message? receivedMsg = check self.consumer->receive(self.readTimeout);
        if receivedMsg !is jms:BytesMessage {
            return;
        }
        Message message = {
            payload: receivedMsg.content
        };
        return message;
    }

    isolated remote function ack(Message message) returns error? {
        return self.session->'commit();
    }

    isolated remote function nack(Message message) returns error? {
        return self.session->'rollback();
    }

    isolated remote function deadLetter(Message message) returns error? {
        check publishToDlq(self.dlqTopic, message);
        return self.session->'commit();
    }

    isolated remote function close(ClosureIntent intent = TEMPORARY) returns error? {
        check self.consumer->close();
        if intent is PERMANENT {
            check self.session->unsubscribe(self.subscriberName);
        }
        return self.session->close();
    }
}

isolated function initJmsDlqProducer(JmsConfig config) returns error? {
    lock {
        if dlqProducer is Producer {
            return;
        }
    }
    lock {
        dlqProducer = check createJmsProducer(config.cloneReadOnly(), "dlq-message-producer");
    }
}

# Initialize a producer for JMS message store.
#
# + config - The JMS connection configurations
# + clientName - The unique client name to use to identify the connection
# + return - A `store:Producer` for a JMS message store, or else return an `error` if the operation fails
public isolated function createJmsProducer(JmsConfig config, string clientName) returns Producer|error {
    jms:ConnectionConfiguration connectionConfig = {
        initialContextFactory: config.initialContextFactory,
        providerUrl: config.providerUrl,
        connectionFactoryName: config.connectionFactoryName,
        username: config.username,
        password: config.password,
        properties: config.properties
    };
    jms:Connection connection = check new (connectionConfig);
    return new JmsProducer(connection);
}

# Initialize a consumer for JMS message store.
#
# + config - The JMS connection configurations
# + topic - The JMS topic to which the consumer should received events for
# + subscriberName - The JMS durable subscriber to which the messages should be received
# + meta - The meta data required to resolve the consumer configurations
# + return - A `store:Consumer` for Kafka message store, or else return an `error` if the operation fails
public isolated function createJmsConsumer(JmsConfig config, string topic, string subscriberName,
        record {} meta = {}) returns Consumer|error {
    jms:ConnectionConfiguration connectionConfig = {
        initialContextFactory: config.initialContextFactory,
        providerUrl: config.providerUrl,
        connectionFactoryName: config.connectionFactoryName,
        username: config.username,
        password: config.password,
        properties: config.properties
    };
    jms:Connection connection = check new (connectionConfig);
    jms:Session session = check connection->createSession(jms:SESSION_TRANSACTED);
    string? dlqTopic = check resolveDeadLetterTopic(config.consumer.deadLetterTopic, meta);
    if dlqTopic is string {
        check initJmsDlqProducer(config);
    }
    return new JmsConsumer(session, config.consumer, topic, subscriberName);
}
