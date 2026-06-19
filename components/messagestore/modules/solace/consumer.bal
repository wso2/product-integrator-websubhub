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

import xlibb/solace;

const string ORIGINAL_SOLACE_MSG = "originalMessage";

isolated client class Consumer {
    *api:Consumer;

    private final solace:MessageConsumer consumer;
    private final readonly & SolaceConsumerConfig config;

    isolated function init(Config config, string queueName) returns error? {

        solace:ConsumerConfiguration consumerConfig = {
            vpnName: config.messageVpn,
            connectionTimeout: config.connectionTimeout,
            readTimeout: config.readTimeout,
            secureSocket: extractSolaceSecureSocketConfig(config.secureSocket),
            auth: config.auth,
            retryConfig: config.retryConfig,
            subscriptionConfig: {
                queueName,
                ackMode: solace:CLIENT_ACK
            }
        };
        self.consumer = check new (config.url, consumerConfig);
        self.config = config.consumer.cloneReadOnly();
    }

    isolated remote function receive() returns api:Message|error? {
        solace:Message? receivedMsg = check self.consumer->receive(self.config.receiveTimeout);
        if receivedMsg is () {
            return;
        }
        api:Message message = {
            id: receivedMsg.applicationMessageId,
            payload: receivedMsg.payload
        };
        message[ORIGINAL_SOLACE_MSG] = receivedMsg;
        return message;
    }

    isolated remote function ack(api:Message message) returns error? {
        if message.hasKey(ORIGINAL_SOLACE_MSG) {
            solace:Message original = check message.get(ORIGINAL_SOLACE_MSG).ensureType();
            return self.consumer->ack(original);
        }
    }

    isolated remote function nack(api:Message message) returns error? {
        if message.hasKey(ORIGINAL_SOLACE_MSG) {
            solace:Message original = check message.get(ORIGINAL_SOLACE_MSG).ensureType();
            return self.consumer->nack(original);
        }
    }

    isolated remote function deadLetter(api:Message message) returns error? {
        if message.hasKey(ORIGINAL_SOLACE_MSG) {
            solace:Message original = check message.get(ORIGINAL_SOLACE_MSG).ensureType();
            return self.consumer->nack(original, false);
        }
    }

    isolated remote function close(api:ClosureIntent intent = api:TEMPORARY) returns error? {
        return self.consumer->close();
    }
}

// todo: fix system queue consumer creation

# Initialize a consumer for Solace message store.
#
# + config - The Solace connection configurations
# + queueName - The queue from which the consumer is receiving messages
# + systemConsumer - Flag to indicate whether this is a system consumer
# + meta - The meta data required to resolve the consumer configurations,
# if `solace.queue_name` is present it takes priority over the `queueName` parameter
# + return - A `store:Consumer` for Kafka message store, or else return an `error` if the operation fails
public isolated function createConsumer(string queueName, Config config, boolean systemConsumer = false, record {} meta = {}) returns api:ConsumerResult|error {
    string effectiveQueueName = systemConsumer ? queueName : resolveQueueName(config.queue, queueName, meta);
    return {consumer: check new Consumer(config, effectiveQueueName), metadata: {"queue": effectiveQueueName}};
}
