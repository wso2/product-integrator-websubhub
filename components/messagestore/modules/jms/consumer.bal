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

import ballerinax/java.jms;

isolated client class Consumer {
    *api:Consumer;

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

    isolated remote function receive() returns api:Message|error? {
        jms:Message? receivedMsg = check self.consumer->receive(self.readTimeout);
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
        return self.session->'commit();
    }

    isolated remote function nack(api:Message message) returns error? {
        return self.session->'rollback();
    }

    isolated remote function deadLetter(api:Message message) returns error? {
        api:Producer? _dlqProducer;
        lock {
            _dlqProducer = dlqProducer;
        }
        check dlq:publish(self.dlqTopic, _dlqProducer, message);
        return self.session->'commit();
    }

    isolated remote function close(api:ClosureIntent intent = api:TEMPORARY) returns error? {
        check self.consumer->close();
        if intent is api:PERMANENT {
            check self.session->unsubscribe(self.subscriberName);
        }
        return self.session->close();
    }
}

# Initialize a consumer for JMS message store.
#
# + topic - The JMS topic to which the consumer should received events for
# + defaultSubscriberId - The JMS durable subscriber Id to which the messages should be received
# + config - The JMS connection configurations
# + systemConsumer - Flag to indicate whether this is a system consumer
# + meta - The meta data required to resolve the consumer configurations
# + return - A `store:Consumer` for Kafka message store, or else return an `error` if the operation fails
public isolated function createConsumer(string topic, string defaultSubscriberId, Config config,
        boolean systemConsumer = false, record {} meta = {}) returns api:ConsumerResult|error {
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
    string? dlqTopic = check dlq:resolveDeadLetterTopic(config.consumer.deadLetterTopic, meta);
    if dlqTopic is string {
        check initJmsDlqProducer(config);
    }
    string subscriberName = systemConsumer ? defaultSubscriberId : string `consumer-${defaultSubscriberId}`;
    return {consumer: check new Consumer(session, config.consumer, topic, subscriberName), metadata: {"subscriber": subscriberName}};
}
