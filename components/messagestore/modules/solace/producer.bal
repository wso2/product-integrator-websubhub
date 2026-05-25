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
        check self.producer->send(
            {topicName: topic},
            {
                applicationMessageId: message.id,
                payload: message.payload,
                // PERSISTENT ensures the message is spooled to subscriber queues for guaranteed delivery.
                // dmqEligible=true is required for the broker to route the message to the Dead Message Queue
                // when max-redelivery is exceeded (FAILED nack) or on REJECTED nack (deadLetter()).
                deliveryMode: solace:PERSISTENT,
                dmqEligible: true
            }
        );
    }

    isolated remote function close() returns error? {
        return self.producer->close();
    }
}
