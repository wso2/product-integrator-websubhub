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
import ballerinax/solace;

const string ORIGINAL_SOLACE_MSG = "originalMessage";

const string DESTINATION_ATTRIBUTE = "destination";
const string URL_ATTRIBUTE = "url";

isolated client class Consumer {
    *api:Consumer;

    private solace:MessageConsumer consumer;
    private final readonly & SolaceConsumerConfig config;
    private final string url;
    private final string queueName;
    private final readonly & solace:ConsumerConfiguration solaceConsumerConfig;

    isolated function init(Config config, string queueName) returns error? {

        solace:ConsumerConfiguration consumerConfig = {
            messageVpn: config.messageVpn,
            connectTimeout: config.connectionTimeout,
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
        self.url = config.url;
        self.queueName = queueName;
        self.solaceConsumerConfig = consumerConfig.cloneReadOnly();
    }

    isolated remote function receive() returns api:Message|error? {
        solace:MessageConsumer _consumer;
        lock {
            _consumer = self.consumer;
        }
        solace:Message? receivedMsg = check _consumer->receive(self.config.receiveTimeout);
        if receivedMsg is () {
            return;
        }
        api:Message message = {
            id: receivedMsg.messageId,
            payload: check toPayloadBytes(receivedMsg.payload)
        };
        string? contentType = extractContentType(receivedMsg);
        if contentType is string {
            message.contentType = contentType;
        }
        map<string|string[]>? metadata = extractMessageMetadata(receivedMsg);
        if metadata is map<string|string[]> {
            message.metadata = metadata;
        }
        message.receiveAttributes = {[DESTINATION_ATTRIBUTE]: self.queueName, [URL_ATTRIBUTE]: self.url};
        message[ORIGINAL_SOLACE_MSG] = receivedMsg;
        return message;
    }

    isolated remote function ack(api:Message message) returns error? {
        if message.hasKey(ORIGINAL_SOLACE_MSG) {
            solace:Message original = check message.get(ORIGINAL_SOLACE_MSG).ensureType();
            solace:MessageConsumer _consumer;
            lock {
                _consumer = self.consumer;
            }
            return _consumer->ack(original);
        }
    }

    isolated remote function nack(api:Message message) returns error? {
        if message.hasKey(ORIGINAL_SOLACE_MSG) {
            solace:Message original = check message.get(ORIGINAL_SOLACE_MSG).ensureType();
            solace:MessageConsumer _consumer;
            lock {
                _consumer = self.consumer;
            }
            return _consumer->nack(original);
        }
    }

    isolated remote function deadLetter(api:Message message) returns error? {
        if message.hasKey(ORIGINAL_SOLACE_MSG) {
            solace:Message original = check message.get(ORIGINAL_SOLACE_MSG).ensureType();
            solace:MessageConsumer _consumer;
            lock {
                _consumer = self.consumer;
            }
            return _consumer->nack(original, false);
        }
    }

    isolated remote function close(api:ClosureIntent intent = api:TEMPORARY) returns error? {
        lock {
            return self.consumer->close();
        }
    }

    isolated remote function reconnect() returns error? {
        error? _closeResult = self->close();
        if _closeResult is error {
            log:printWarn("Error while closing Solace consumer during reconnect", 'error = _closeResult);
        }
        solace:MessageConsumer _consumer = check new (self.url, self.solaceConsumerConfig);
        lock {
            self.consumer = _consumer;
        }
    }
}

# Message properties that describe the message itself rather than carrying publisher metadata, and
# so must not be replayed to subscribers as delivery headers.
final readonly & string[] RESERVED_PROPERTIES = [
    solace:HTTP_CONTENT_TYPE_PROP,
    solace:HTTP_CONTENT_ENCODING_PROP,
    solace:SOLACE_ISXML_PROP
];

isolated function extractMessageMetadata(solace:Message msg) returns map<string|string[]>? {
    map<anydata>? props = msg.properties;
    if props is () {
        return;
    }
    map<string|string[]> metadata = {};
    foreach var [key, value] in props.entries() {
        if RESERVED_PROPERTIES.indexOf(key) !is () {
            continue;
        }
        if value is string {
            metadata[key] = value;
        }
    }
    return metadata.length() > 0 ? metadata : ();
}

# Reads the content type travelling with a message.
#
# The connector surfaces the SMF HTTP Content Type field through `Message.properties`. The broker
# populates that field from the `Content-Type` header of a message published over its REST
# interface, and this hub's producer writes it for messages it publishes itself, so the same
# property serves both a direct REST publisher and a publish made through the hub.
#
# + msg - The message received from the broker
# + return - The content type of the payload, or `()` if the message carries none
isolated function extractContentType(solace:Message msg) returns string? {
    map<anydata>? props = msg.properties;
    if props is () {
        return;
    }
    anydata contentType = props[solace:HTTP_CONTENT_TYPE_PROP];
    if contentType !is string {
        return;
    }
    string trimmed = contentType.trim();
    return trimmed.length() == 0 ? () : trimmed;
}

// todo: fix system queue consumer creation

# Initialize a consumer for Solace message store.
#
# + config - The Solace connection configurations
# + queueName - The queue from which the consumer is receiving messages
# + systemConsumer - Flag to indicate whether this is a system consumer
# + meta - The meta data required to resolve the consumer configurations,
# if `solace.queue_name` is present it takes priority over the `queueName` parameter
# + return - An `api:ConsumerResult` tuple of the consumer and its metadata, or an `error` if the operation fails
public isolated function createConsumer(string queueName, Config config, boolean systemConsumer = false, record {} meta = {}) returns api:ConsumerResult|error {
    string effectiveQueueName = systemConsumer ? queueName : resolveQueueName(config.queue, queueName, meta);
    Consumer consumer = check new Consumer(config, effectiveQueueName);
    return [consumer, {"queue": effectiveQueueName}];
}

# Converts a received payload into the bytes the message store carries.
#
# `ballerinax/solace` types `Message.payload` as `anydata` and resolves it from the SMF message
# type, so a text message arrives as a `string` and a map message as a mapping. The store is
# byte-oriented, so everything is normalised here.
#
# + payload - The payload as the connector surfaced it
# + return - The payload as bytes, or an `error` if it cannot be represented
isolated function toPayloadBytes(anydata payload) returns byte[]|error {
    if payload is byte[] {
        return payload;
    }
    if payload is string {
        return payload.toBytes();
    }
    if payload is xml {
        return payload.toString().toBytes();
    }
    return payload.toJsonString().toBytes();
}
