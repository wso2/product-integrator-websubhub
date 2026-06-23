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
import ballerinax/kafka;

public isolated client class Producer {
    *api:Producer;

    private kafka:Producer producer;
    private final string|string[] & readonly bootstrapServers;
    private final kafka:ProducerConfiguration & readonly producerConfig;

    public isolated function init(string clientId, Config config) returns error? {
        kafka:ProducerConfiguration producerConfig = {
            clientId,
            acks: config.producer.acks,
            retryCount: config.producer.retryCount,
            secureSocket: config.secureSocket,
            securityProtocol: config.securityProtocol
        };
        self.bootstrapServers = config.bootstrapServers.cloneReadOnly();
        self.producerConfig = producerConfig.cloneReadOnly();
        self.producer = check new (config.bootstrapServers, producerConfig);
    }

    isolated remote function send(string topic, api:Message message) returns error? {
        lock {
            check self.producer->send({topic, value: message.payload.cloneReadOnly(), headers: message.metadata.cloneReadOnly()});
            return self.producer->'flush();
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
                log:printWarn("Error while closing Kafka producer during reconnect", 'error = result);
            }
            self.producer = check new (self.bootstrapServers, self.producerConfig);
        }
    }
}
