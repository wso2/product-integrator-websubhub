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

type SolaceQueueNotFound distinct error;

type SolaceEntityNotFound distinct error;

type SolaceQueueExists distinct error;

type SolaceEntityExists distinct error;

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

    isolated remote function createTopic(string topic, record {} meta = {}) returns TopicExists|error? {
        return;
    }

    isolated remote function deleteTopic(string topic, record {} meta = {}) returns TopicNotFound|error? {
        return;
    }

    isolated remote function createSubscription(string topic, string queueName, record {} meta = {}) returns SubscriptionExists|error? {
        semp:MsgVpnQueue|error queue = self.retrieveQueue(queueName);
        if queue is SolaceQueueNotFound {
            string dlqName = string `dlq-${queueName}`;
            semp:MsgVpnQueue|error dlq = self.retrieveQueue(dlqName);
            if dlq is SolaceQueueNotFound {
                _ = check self.createQueue(self.messageVpn, dlqName);
            } else if dlq is error {
                return dlq;
            }
            _ = check self.createQueue(queueName, dlqName);
        }

        if queue is error {
            return queue;
        }
        _ = check self.addTopicSubscription(queueName, topic);
    }

    isolated remote function deleteSubscription(string topic, string queueName, record {} meta = {}) returns SubscriptionNotFound|error? {
        semp:MsgVpnQueueSubscription[] subscriptions = check self.retrieveTopicSubscriptions(queueName);
        semp:MsgVpnQueueSubscription[] filteredSubscriptions = subscriptions.filter(a => a.subscriptionTopic === topic);
        if filteredSubscriptions.length() === 0 {
            string errorMsg = string `
                Subscription not found for the topic [${topic}] in Solace queue [${queueName}] in message-vpn [${self.messageVpn}]`;
            return error SubscriptionNotFound(errorMsg);
        }

        _ = check self.removeTopicSubscription(queueName, topic);

        if subscriptions.length() === 1 {
            return self.deleteQueue(queueName);
        }
    }

    isolated function retrieveQueue(string queueName) returns semp:MsgVpnQueue|error {
        string vpn = self.messageVpn;
        semp:MsgVpnQueueResponse|error response = self.administrator->getMsgVpnQueue(
            msgVpnName = vpn,
            queueName = queueName
        );
        if response is semp:MsgVpnQueueResponse {
            if response.data is semp:MsgVpnQueue {
                return <semp:MsgVpnQueue>response.data;
            }
            return error SolaceQueueNotFound(string `Empty response received when tried to retrieve queue [${queueName}] for vpn [${vpn}]`);
        }

        if response is http:ClientRequestError {
            http:Detail errorDetails = response.detail();
            if errorDetails.statusCode !== http:STATUS_BAD_REQUEST {
                return response;
            }
            record {semp:SempMeta meta;} payload = check errorDetails.body.cloneWithType();
            if "NOT_FOUND" !== payload.meta.'error?.status {
                return response;
            }
            return error SolaceQueueNotFound(string `Could not find the queue [${queueName}] for vpn [${vpn}]`);
        }

        return response;
    }

    isolated function createQueue(string queueName, string? dlq = ()) returns semp:MsgVpnQueue|error {
        string vpn = self.messageVpn;
        semp:MsgVpnQueueResponse|error response = self.administrator->createMsgVpnQueue(vpn, payload = {
            queueName,
            deadMsgQueue: dlq,
            accessType: "non-exclusive",
            permission: "delete"
        });
        if response is semp:MsgVpnQueueResponse {
            if response.data is semp:MsgVpnQueue {
                return <semp:MsgVpnQueue>response.data;
            }
            return error(string `Empty response received when tried to create a queue [${queueName}] in vpn [${vpn}]`);
        }

        if response is http:ClientRequestError {
            http:Detail errorDetails = response.detail();
            if errorDetails.statusCode !== http:STATUS_BAD_REQUEST {
                return response;
            }
            record {semp:SempMeta meta;} payload = check errorDetails.body.cloneWithType();
            if "NOT_FOUND" === payload.meta.'error?.status {
                return error(string `Could not find the vpn [${vpn}]`);
            }
            if "ALREADY_EXISTS" !== payload.meta.'error?.status {
                return response;
            }
            return error SolaceQueueExists(string `Queue [${queueName}] already exists in vpn [${vpn}]`);
        }
        return response;
    }

    isolated function addTopicSubscription(string queueName, string subscriptionTopic) returns semp:MsgVpnQueueSubscription|error {
        string vpn = self.messageVpn;
        semp:MsgVpnQueueSubscriptionResponse|error response = self.administrator->createMsgVpnQueueSubscription(
            msgVpnName = vpn,
            queueName = queueName,
            payload = {
            subscriptionTopic
        }
        );
        if response is semp:MsgVpnQueueSubscriptionResponse {
            if response.data is semp:MsgVpnQueueSubscription {
                return <semp:MsgVpnQueueSubscription>response.data;
            }
            return error(string `Empty response received when trying to add a topic subscription [${subscriptionTopic}] for a queue [${queueName}] in vpn [${vpn}]`);
        }

        if response is http:ClientRequestError {
            http:Detail errorDetails = response.detail();
            if errorDetails.statusCode !== http:STATUS_BAD_REQUEST {
                return response;
            }
            record {semp:SempMeta meta;} payload = check errorDetails.body.cloneWithType();
            if "NOT_FOUND" === payload.meta.'error?.status {
                return error(string `Could not find either the queue [${queueName}] or the vpn [${vpn}]`);
            }
            if "ALREADY_EXISTS" !== payload.meta.'error?.status {
                return response;
            }
            return error SubscriptionExists(string `Topic subscription [${subscriptionTopic}] already existst for queue [${queueName}] in vpn [${vpn}]`);
        }
        return response;
    }

    isolated function retrieveTopicSubscriptions(string queueName) returns semp:MsgVpnQueueSubscription[]|error {
        string vpn = self.messageVpn;
        semp:MsgVpnQueueSubscription[] subscriptions = [];
        string? cursor = ();

        while true {
            semp:MsgVpnQueueSubscriptionsResponse|error response;
            if cursor is string {
                response = self.administrator->getMsgVpnQueueSubscriptions(
                    msgVpnName = vpn,
                    queueName = queueName,
                    cursor = cursor
                );
            } else {
                response = self.administrator->getMsgVpnQueueSubscriptions(
                    msgVpnName = vpn,
                    queueName = queueName
                );
            }

            if response is http:ClientRequestError {
                http:Detail details = response.detail();
                if details.statusCode == http:STATUS_BAD_REQUEST {
                    record {semp:SempMeta meta;} payload = check details.body.cloneWithType();
                    if payload.meta.'error?.status == "NOT_FOUND" {
                        return error SubscriptionNotFound(
                        string `Could not find either the queue [${queueName}] or the vpn [${vpn}]`
                        );
                    }
                }
                return response;
            }
            if response is error {
                return response;
            }

            if response.data is semp:MsgVpnQueueSubscription[] {
                subscriptions.push(...(<semp:MsgVpnQueueSubscription[]>response.data));
            }

            semp:SempPaging? paging = response.meta.paging;
            if paging is () {
                break;
            }

            cursor = paging.cursorQuery;
        }

        return subscriptions;
    }

    isolated function removeTopicSubscription(string queueName, string subscriptionTopic) returns error? {
        _ = check self.administrator->deleteMsgVpnQueueSubscription(
            msgVpnName = self.messageVpn,
            queueName = queueName,
            subscriptionTopic = subscriptionTopic
        );
    }

    isolated function deleteQueue(string queueName) returns error? {
        _ = check self.administrator->deleteMsgVpnQueue(
            msgVpnName = self.messageVpn,
            queueName = queueName
        );
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

# Initialize a administrator for Solace message store.
#
# + config - The Solace connection configurations
# + return - A `store:Administrator` for Solace message store, or else return an `error` if the operation fails
public isolated function createSolaceAdministrator(SolaceConfig config) returns Administrator|error {
    return new SolaceAdministrator(config);
}
