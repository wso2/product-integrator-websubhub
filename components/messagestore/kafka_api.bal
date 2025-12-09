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

import ballerina/log;
import ballerinax/kafka;

isolated client class KafkaProducer {
    *Producer;

    private final kafka:Producer producer;

    isolated function init(string clientId, KafkaConfig config) returns error? {
        kafka:ProducerConfiguration producerConfig = {
            clientId,
            acks: config.producer.acks,
            retryCount: config.producer.retryCount,
            secureSocket: config.secureSocket,
            securityProtocol: config.securityProtocol
        };
        self.producer = check new (config.bootstrapServers, producerConfig);
    }

    isolated remote function send(string topic, Message message) returns error? {
        check self.producer->send({topic, value: message.payload, headers: message.metadata});
        return self.producer->'flush();
    }

    isolated remote function close() returns error? {
        return self.producer->close();
    }
}

isolated client class KafkaConsumer {
    *Consumer;

    private final kafka:Consumer consumer;
    private final readonly & KafkaConsumerConfig config;

    private KafkaConsumerRecord[] messageBatch = [];

    isolated function init(KafkaConfig config, string groupId, string topic, boolean autoCommit = true,
            kafka:OffsetResetMethod? offsetReset = (), int[]? partitions = ()) returns error? {

        kafka:ConsumerConfiguration consumerConfig = {
            groupId,
            offsetReset,
            autoCommit,
            maxPollRecords: config.consumer.maxPollRecords,
            secureSocket: config.secureSocket,
            securityProtocol: config.securityProtocol
        };
        self.config = config.consumer.cloneReadOnly();

        if partitions is () {
            // Kafka consumer topic subscription should only be used when manual partition assignment is not used
            consumerConfig.topics = [topic];
            self.consumer = check new (config.bootstrapServers, consumerConfig);
            return;
        }

        kafka:Consumer|kafka:Error consumer = check new (config.bootstrapServers, consumerConfig);
        if consumer is kafka:Error {
            log:printError("Error occurred while creating the Kafka consumer", consumer);
            return consumer;
        }

        kafka:TopicPartition[] kafkaTopicPartitions = partitions.'map(p => {topic: topic, partition: p});
        kafka:Error? paritionAssignmentErr = consumer->assign(kafkaTopicPartitions);
        if paritionAssignmentErr is kafka:Error {
            log:printError("Error occurred while assigning partitions to the Kafka consumer", paritionAssignmentErr);
            return paritionAssignmentErr;
        }

        kafka:TopicPartition[] parititionsWithoutCmtdOffsets = [];
        foreach kafka:TopicPartition partition in kafkaTopicPartitions {
            kafka:PartitionOffset|kafka:Error? offset = consumer->getCommittedOffset(partition);
            if offset is kafka:Error {
                log:printError("Error occurred while retrieving the commited offsets for the Kafka topic partition", offset);
                return offset;
            }

            if offset is () {
                parititionsWithoutCmtdOffsets.push(partition);
            }

            if offset is kafka:PartitionOffset {
                kafka:Error? kafkaSeekErr = consumer->seek(offset);
                if kafkaSeekErr is kafka:Error {
                    log:printError("Error occurred while assigning seeking partitions for the Kafka consumer", kafkaSeekErr);
                    return kafkaSeekErr;
                }
            }
        }

        if parititionsWithoutCmtdOffsets.length() > 0 {
            kafka:Error? kafkaSeekErr = consumer->seekToBeginning(parititionsWithoutCmtdOffsets);
            if kafkaSeekErr is kafka:Error {
                log:printError(
                        "Error occurred while assigning seeking partitions (for paritions without committed offsets) for the Kafka consumer",
                        kafkaSeekErr
                );
                return kafkaSeekErr;
            }
        }

        self.consumer = consumer;
    }

    isolated remote function receive() returns Message|error? {
        check self.updateCurrentBatch();
        if self.isCurrentBatchEmpty() {
            return;
        }

        KafkaConsumerRecord current;
        lock {
            current = self.messageBatch.shift().cloneReadOnly();
        }
        // TODO: Temporary disabling kafka-header mapping as there is bug which crashes the `store:Consumer` when retrieving headers
        return {
            payload: current.value
        };
    }

    isolated function isCurrentBatchEmpty() returns boolean {
        lock {
            return self.messageBatch.length() == 0;
        }
    }

    isolated function updateCurrentBatch() returns error? {
        if !self.isCurrentBatchEmpty() {
            return;
        }
        KafkaConsumerRecord[] messages = check self.consumer->poll(self.config.pollingInterval);
        lock {
            self.messageBatch.push(...messages.cloneReadOnly());
        }
    }

    isolated remote function ack(Message message) returns error? {
        if self.isCurrentBatchEmpty() {
            return self.consumer->'commit();
        }
    }

    isolated remote function nack(Message message) returns error? {
        // As Kafka does not have a `nack` functionality no need to implement this API
    }

    isolated remote function close() returns error? {
        return self.consumer->close(self.config.gracefulClosePeriod);
    }
}

# Initialize a producer for Kafka message store.
#
# + config - The Kafka connection configurations
# + clientId - The client Id
# + return - A `store:Producer` for Kafka message store, or else return an `error` if the operation fails
public isolated function createKafkaProducer(KafkaConfig config, string clientId) returns Producer|error {
    return new KafkaProducer(clientId, config);
}

# Initialize a consumer for Kafka message store.
#
# + config - The Kafka connection configurations
# + groupId - The Kafka consumer group to which this consumer should belong to
# + topic - The Kafka topic to which the consumer should received events for
# + autoCommit - The flag to enable auto-commit offsets  
# + offsetReset - The offset reset strategy if no initial offset
# + partitions - The Kafka topic partitions
# + return - A `store:Consumer` for Kafka message store, or else return an `error` if the operation fails
public isolated function createKafkaConsumer(KafkaConfig config, string groupId, string topic, boolean autoCommit = true,
        kafka:OffsetResetMethod? offsetReset = (), int[]? partitions = ()) returns Consumer|error {
    return new KafkaConsumer(config, groupId, topic, autoCommit, offsetReset, partitions);
}
