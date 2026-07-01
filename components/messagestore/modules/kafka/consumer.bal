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
import messagestore.dlq;

import ballerina/lang.value;
import ballerina/log;
import ballerinax/kafka;

isolated client class Consumer {
    *api:Consumer;

    private final kafka:Consumer consumer;
    private final readonly & KafkaConsumerConfig config;
    private final string? dlqTopic;

    private KafkaConsumerRecord[] messageBatch = [];

    isolated function init(Config config, string groupId, string topic, int[]? partitions = (), string? dlqTopic = ()) returns error? {

        kafka:ConsumerConfiguration consumerConfig = {
            groupId,
            offsetReset: config.consumer.offsetReset,
            autoCommit: false,
            maxPollRecords: config.consumer.maxPollRecords,
            secureSocket: config.secureSocket,
            securityProtocol: config.securityProtocol
        };
        self.config = config.consumer.cloneReadOnly();
        self.dlqTopic = dlqTopic;

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

    isolated remote function receive() returns api:Message|error? {
        check self.updateCurrentBatch();
        if self.isCurrentBatchEmpty() {
            return;
        }

        KafkaConsumerRecord current;
        lock {
            current = self.messageBatch.shift().cloneReadOnly();
        }
        // Decode the Kafka headers (raw byte[] on the wire) back into api:Message.metadata so the
        // round-tripped data — e.g. the x-hub-contentType used to reconstruct the delivery
        // Content-Type — reaches the delivery side. Non-UTF-8 header values are skipped rather than
        // failing the whole receive.
        map<string|string[]> metadata = decodeKafkaHeaders(current.headers);
        return {
            payload: current.value,
            metadata: metadata.length() > 0 ? metadata : ()
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

    isolated remote function ack(api:Message message) returns error? {
        if self.isCurrentBatchEmpty() {
            return self.consumer->'commit();
        }
    }

    isolated remote function nack(api:Message message) returns error? {
        // As Kafka does not have a `nack` functionality no need to implement this API
    }

    isolated remote function deadLetter(api:Message message) returns error? {
        api:Producer? _dlqProducer;
        lock {
            _dlqProducer = dlqProducer;
        }
        check dlq:publish(self.dlqTopic, _dlqProducer, message);
        if self.isCurrentBatchEmpty() {
            check self.consumer->'commit();
        }
    }

    isolated remote function close(api:ClosureIntent intent = api:TEMPORARY) returns error? {
        return self.consumer->close(self.config.gracefulClosePeriod);
    }
}

# Initialize a consumer for Kafka message store.
#
# + groupId - The default Kafka consumer group to which this consumer should belong to
# + topic - The Kafka topic to which the consumer should received events for
# + config - The Kafka connection configurations
# + systemConsumer - Flag to indicate whether this is a system consumer
# + meta - The meta data required to resolve the Kafka consumer group and topic partitions, 
# if the user provided a `meta` information it would have a higher priority than the `groupId` provided. 
# As of now only consumer-group and topic-partitions can be provided as `meta`
# + return - An `api:ConsumerResult` tuple of the consumer and its metadata, or an `error` if the operation fails
public isolated function createConsumer(string groupId, string topic, Config config, boolean systemConsumer, record {} meta = {}) returns api:ConsumerResult|error {

    string consumerGroup = systemConsumer ? groupId : check resolveConsumerGroup(groupId, meta);
    int[]? topicPartitions = check resolveTopicPartitions(meta);
    string? dlqTopic = check dlq:resolveDeadLetterTopic(config.consumer.deadLetterTopic, meta);
    if dlqTopic is string {
        check initKafkaDlqProducer(config);
    }
    api:ConsumerMetadata metadata = topicPartitions !is ()
        ? {"topicPartitions": string:'join(",", ...topicPartitions.'map(p => p.toString()))}
        : {"consumerGroup": consumerGroup};
    Consumer consumer = check new Consumer(config, consumerGroup, topic, topicPartitions, dlqTopic);
    return [consumer, metadata];
}

const string CONSUMER_GROUP = "consumerGroup";
const string CONSUMER_TOPIC_PARTITIONS = "topicPartitions";

isolated function resolveConsumerGroup(string defaultGroupId, record {} meta) returns string|error {
    if meta.hasKey(CONSUMER_GROUP) {
        return value:ensureType(meta[CONSUMER_GROUP]);
    }
    return string `consumer-${defaultGroupId}`;
}

isolated function resolveTopicPartitions(record {} meta) returns int[]|error? {
    if !meta.hasKey(CONSUMER_TOPIC_PARTITIONS) {
        return;
    }
    // Kafka topic partitions will be a string with comma separated integers eg: "1,2,3,4"
    string partitionInfo = check value:ensureType(meta[CONSUMER_TOPIC_PARTITIONS]);
    return re `,`.split(partitionInfo).'map(p => p.trim()).'map(p => check int:fromString(p));
}

// Converts Kafka header values (delivered on the wire as byte[]/byte[][], or already string/string[])
// into the string-based api:Message.metadata shape. byte[] values are decoded as UTF-8; entries that
// are not valid UTF-8 are skipped rather than failing the whole receive — they are not metadata this
// hub produced. This restores the x-hub-contentType round-trip used to reconstruct delivery Content-Type.
isolated function decodeKafkaHeaders(map<byte[]|byte[][]|string|string[]> headers) returns map<string|string[]> {
    map<string|string[]> metadata = {};
    foreach var [key, value] in headers.entries() {
        if value is string {
            metadata[key] = value;
        } else if value is string[] {
            metadata[key] = value;
        } else if value is byte[] {
            string|error decoded = string:fromBytes(value);
            if decoded is string {
                metadata[key] = decoded;
            }
        } else if value is byte[][] {
            string[] decodedValues = [];
            foreach byte[] item in value {
                string|error decoded = string:fromBytes(item);
                if decoded is string {
                    decodedValues.push(decoded);
                }
            }
            if decodedValues.length() > 0 {
                metadata[key] = decodedValues;
            }
        }
    }
    return metadata;
}
