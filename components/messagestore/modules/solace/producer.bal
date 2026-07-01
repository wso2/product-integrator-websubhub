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

import xlibb/solace;

public isolated client class Producer {
    *api:Producer;

    private solace:MessageProducer producer;
    private final string url;
    private final solace:ProducerConfiguration & readonly producerConfig;

    public isolated function init(string clientName, Config config) returns error? {

        solace:ProducerConfiguration producerConfig = {
            clientName,
            vpnName: config.messageVpn,
            connectionTimeout: config.connectionTimeout,
            readTimeout: config.readTimeout,
            secureSocket: extractSolaceSecureSocketConfig(config.secureSocket),
            auth: config.auth,
            retryConfig: config.retryConfig
        };
        self.url = config.url;
        self.producerConfig = producerConfig.cloneReadOnly();
        self.producer = check new (config.url, producerConfig);
    }

    isolated remote function send(string topic, api:Message message) returns error? {
        // Carry the message metadata (e.g. the original Content-Type) as Solace user-properties
        // (SDTMap) so it survives the broker round-trip and can be restored by the consumer.
        // xlibb/solace 0.4.1 exposes `properties: map<anydata>?` natively.
        //
        // A multi-valued header (string[]) is flattened to its first element. The Solace SDTMap does
        // not accept array values — sending one fails with "Failed to send message: null" — so we
        // cannot carry arrays as-is. Single-valued metadata (which includes the only key this hub
        // relies on, x-hub-contentType) is unaffected. Preserving repeated header values would require
        // reversibly encoding the array (e.g. JSON) here and decoding it in the consumer.
        map<anydata>? properties = ();
        map<string|string[]>? metadata = message.metadata;
        if metadata is map<string|string[]> {
            map<anydata> props = {};
            foreach [string, string|string[]] [key, value] in metadata.entries() {
                if value is string[] {
                    // Solace SDTMap does not support array values. Flatten to the first element.
                    // Skip the key entirely when the array is empty — storing "" would silently
                    // round-trip as an empty string on the consumer side, which is more surprising
                    // than simply omitting the key.
                    if value.length() > 0 {
                        props[key] = value[0];
                    }
                } else {
                    props[key] = value;
                }
            }
            properties = props;
        }
        log:printDebug("[Solace MessageStore] Publishing message",
                topic = topic, messageId = message.id ?: "(none)",
                payloadSize = message.payload.length(),
                propertyCount = properties is map<anydata> ? properties.length() : 0);
        check self.producer->send(
            {topicName: topic},
            {
                applicationMessageId: message.id,
                payload: message.payload,
                properties
            }
        );
        lock {
            // todo: Setting properties will throw an error, hence ignoring setting properties for now
            check self.producer->send(
                {topicName: topic},
                {
                applicationMessageId: message.id,
                payload: message.payload.cloneReadOnly()
            }
            );
        }
    }

    isolated remote function close() returns error? {
        lock {
            return self.producer->close();
        }
    }

    isolated remote function reconnect() returns error? {
        lock {
            error? result = self.producer->close();
            if result is error {
                log:printWarn("Error while closing Solace producer during reconnect", 'error = result);
            }
            self.producer = check new (self.url, self.producerConfig);
        }
    }
}
