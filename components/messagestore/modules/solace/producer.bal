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

    private final solace:MessageProducer producer;

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
        self.producer = check new (config.url, producerConfig);
    }

    isolated remote function send(string topic, api:Message message) returns error? {
        // Carry the message metadata (e.g. the original Content-Type) as Solace user-properties
        // (SDTMap) so it survives the broker round-trip and can be restored by the consumer.
        // xlibb/solace 0.4.1 exposes `properties: map<anydata>?` natively. Values are flattened to
        // single strings (first element of any multi-valued header).
        map<anydata>? properties = ();
        map<string|string[]>? metadata = message.metadata;
        if metadata is map<string|string[]> {
            map<anydata> props = {};
            foreach [string, string|string[]] [key, value] in metadata.entries() {
                props[key] = value is string[] ? (value.length() > 0 ? value[0] : "") : value;
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
    }

    isolated remote function close() returns error? {
        return self.producer->close();
    }
}
