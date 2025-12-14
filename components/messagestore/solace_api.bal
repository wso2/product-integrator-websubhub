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

import xlibb/solace;
import xlibb/solace.semp;

isolated client class SolaceProducer {
    *Producer;

    private final solace:MessageProducer producer;

    isolated function init(string clientName, SolaceConfig config) returns error? {

        solace:ProducerConfiguration producerConfig = {
            clientName,
            vpnName: config.messageVpn,
            connectionTimeout: config.connectionTimeout,
            readTimeout: config.readTimeout,
            secureSocket: config.secureSocket,
            auth: config.auth,
            retryConfig: config.retryConfig
        };
        self.producer = check new (config.url, producerConfig);
    }

    isolated remote function send(string topic, Message message) returns error? {
        check self.producer->send(
            {topicName: topic},
            {payload: message.payload, properties: message.metadata}
        );
    }

    isolated remote function close() returns error? {
        return self.producer->close();
    }
}

const string ORIGINAL_SOLACE_MSG = "originalMessage";

isolated client class SolaceConsumer {
    *Consumer;

    private final solace:MessageConsumer consumer;
    private final readonly & SolaceConsumerConfig config;

    isolated function init(SolaceConfig config, string queueName, boolean autoAck = true) returns error? {

        solace:ConsumerConfiguration consumerConfig = {
            vpnName: config.messageVpn,
            connectionTimeout: config.connectionTimeout,
            readTimeout: config.readTimeout,
            secureSocket: config.secureSocket,
            auth: config.auth,
            retryConfig: config.retryConfig,
            subscriptionConfig: {
                queueName,
                ackMode: autoAck ? solace:AUTO_ACK : solace:CLIENT_ACK
            }
        };
        self.consumer = check new (config.url, consumerConfig);
        self.config = config.consumer.cloneReadOnly();
    }

    isolated remote function receive() returns Message|error? {
        solace:Message? receivedMsg = check self.consumer->receive(self.config.receiveTimeout);
        if receivedMsg is () {
            return;
        }
        Message message = {
            payload: receivedMsg.payload
        };
        message[ORIGINAL_SOLACE_MSG] = receivedMsg;
        return message;
    }

    isolated remote function ack(Message message) returns error? {
        if message.hasKey(ORIGINAL_SOLACE_MSG) {
            solace:Message original = check message.get(ORIGINAL_SOLACE_MSG).ensureType();
            return self.consumer->ack(original);
        }
    }

    isolated remote function nack(Message message) returns error? {
        if message.hasKey(ORIGINAL_SOLACE_MSG) {
            solace:Message original = check message.get(ORIGINAL_SOLACE_MSG).ensureType();
            return self.consumer->nack(original);
        }
    }

    isolated remote function close() returns error? {
        return self.consumer->close();
    }
}

isolated client class SolaceAdministrator {
    *Administrator;

    private final semp:Client administrator;
    private final string messageVpn;

    isolated function init(SolaceConfig config) returns error? {
        self.administrator = check new (
            serviceUrl = config.admin.url,
            config = {
                timeout: config.admin.timeout,
                secureSocket: config.admin.secureSocket,
                auth: config.admin.auth,
                retryConfig: config.admin.retryConfig
            }
        );
        self.messageVpn = config.messageVpn;
    }

    isolated remote function createTopic(string topic) returns TopicExists|error? {
        return;
    }

    isolated remote function deleteTopic(string topic) returns TopicNotFound|error? {
        return;
    }

    isolated remote function createSubscription(string topic, string queueName) returns SubscriptionExists|error? {
        semp:MsgVpnQueueResponse queueResponse = check self.administrator->getMsgVpnQueue(
            msgVpnName = self.messageVpn, queueName = queueName
        );
        semp:SempMeta? meta = queueResponse.meta;
        if meta is semp:SempMeta {
            if meta.responseCode === http:STATUS_NOT_FOUND {
                // create the queue
            } else if meta.responseCode === http:STATUS_CONFLICT {
                // Do nothing
            } else {
                string errMsg = "Unexpected error occurred while creating the Solace queue subscription";
                return error(errMsg);
            }
        }

        semp:MsgVpnQueueSubscriptionResponse queueSubResponse = check self.administrator->createMsgVpnQueueSubscription(
            msgVpnName = self.messageVpn,
            queueName = queueName,
            payload = {
            subscriptionTopic: topic
        }
        );
        semp:SempMeta? queueSubResponseMeta = queueSubResponse.meta;
        if queueSubResponseMeta is semp:SempMeta {
            if queueSubResponseMeta.responseCode !== http:STATUS_OK {
                string errMsg = "Unexpected error occurred while creating the Solace queue subscription";
                return error(errMsg);
            }
        }
    }

    isolated remote function deleteSubscription(string topic, string queueName) returns SubscriptionNotFound|error? {
    }

    isolated remote function close() returns error? {
        return;
    }
}

# Initialize a producer for Solace message store.
#
# + config - The Solace connection configurations
# + clientName - The unique client name to use to identify the connection
# + return - A `store:Producer` for Solace message store, or else return an `error` if the operation fails
public isolated function createSolaceProducer(SolaceConfig config, string clientName) returns Producer|error {
    return new SolaceProducer(clientName, config);
}

# Initialize a consumer for Solace message store.
#
# + config - The Solace connection configurations
# + queueName - The queue from which the consumer is receiving messages
# + autoAck - A flag to enable or disable automatic message acknowledgement
# + meta - The meta data required to resolve the consumer configurations
# + return - A `store:Consumer` for Kafka message store, or else return an `error` if the operation fails
public isolated function createSolaceConsumer(SolaceConfig config, string queueName, boolean autoAck = true,
        record {} meta = {}) returns Consumer|error {
    return new SolaceConsumer(config, queueName, autoAck);
}
