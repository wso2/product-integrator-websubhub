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

public isolated client class Producer {
    *api:Producer;

    private solace:MessageProducer producer;
    private final string url;
    private final solace:ProducerConfiguration & readonly producerConfig;

    public isolated function init(string clientName, Config config) returns error? {

        solace:ProducerConfiguration producerConfig = {
            clientName,
            messageVpn: config.messageVpn,
            connectTimeout: config.connectionTimeout,
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
        map<solace:Property> properties = buildProperties(message);
        lock {
            check self.producer->send(
                {
                    messageId: message.id,
                    payload: message.payload.cloneReadOnly(),
                    properties: properties.cloneReadOnly()
                },
                {topicName: topic}
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

# Builds the Solace message properties carried alongside a published message.
#
#
# + message - The message being published
# + return - The properties to set on the Solace message
isolated function buildProperties(api:Message message) returns map<solace:Property> {
    map<solace:Property> properties = {};
    map<string|string[]>? metadata = message.metadata;
    if metadata is map<string|string[]> {
        foreach var [key, value] in metadata.entries() {
            // An SDT property holds a single string, so a repeated header is joined the way HTTP
            // represents one.
            properties[key] = value is string ? value : string:'join(", ", ...value);
        }
    }
    string? contentType = message.contentType;
    if contentType is string {
        properties[solace:HTTP_CONTENT_TYPE_PROP] = contentType;
    }
    return properties;
}
