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

import websubhub.config;

import ballerina/log;
import ballerinax/kafka;
import websubhub.common;

// Producer which persist the current in-memory state of the Hub 
kafka:ProducerConfiguration statePersistConfig = {
    clientId: "state-persist",
    acks: "1",
    retryCount: 3,
    secureSocket: config:kafka.connection.secureSocket,
    securityProtocol: config:kafka.connection.securityProtocol
};
public final kafka:Producer statePersistProducer = check new (config:kafka.connection.bootstrapServers, statePersistConfig);

// Consumer which reads the persisted subscriber details
kafka:ConsumerConfiguration websubEventsConsumerConfig = {
    groupId: config:state.events.consumerGroup,
    offsetReset: "earliest",
    topics: [config:state.events.topic],
    secureSocket: config:kafka.connection.secureSocket,
    securityProtocol: config:kafka.connection.securityProtocol
};
public final kafka:Consumer websubEventsConsumer = check new (config:kafka.connection.bootstrapServers, websubEventsConsumerConfig);

# Creates a `kafka:Consumer` for a subscriber.
#
# + topicName - The kafka-topic to which the consumer should subscribe  
# + groupName - The consumer group name  
# + partitions - The kafka topic-partitions
# + return - `kafka:Consumer` if succcessful or else `error`
public isolated function createMessageConsumer(string topicName, string groupName, int[]? partitions = ()) returns kafka:Consumer|error {
    log:printDebug("Creating Kafka message consumer", topic = topicName, groupId = groupName, partitions = partitions);
    kafka:ConsumerConfiguration consumerConfiguration = {
        groupId: groupName,
        autoCommit: false,
        secureSocket: config:kafka.connection.secureSocket,
        securityProtocol: config:kafka.connection.securityProtocol,
        maxPollRecords: config:kafka.consumer.maxPollRecords
    };
    log:printDebug("Consumer configuration prepared", groupId = groupName, autoCommit = false, maxPollRecords = config:kafka.consumer.maxPollRecords);

    if partitions is () {
        // Kafka consumer topic subscription should only be used when manual partition assignment is not used
        log:printDebug("Using topic subscription mode (no manual partition assignment)", topic = topicName);
        consumerConfiguration.topics = [topicName];
        kafka:Consumer consumer = check new (config:kafka.connection.bootstrapServers, consumerConfiguration);
        log:printDebug("Kafka consumer created successfully with topic subscription", topic = topicName, groupId = groupName);
        return consumer;
    }

    log:printDebug("Using manual partition assignment mode", topic = topicName, partitionCount = partitions.length());
    kafka:Consumer|kafka:Error consumerEp = check new (config:kafka.connection.bootstrapServers, consumerConfiguration);
    if consumerEp is kafka:Error {
        common:logError("Error occurred while creating the consumer", consumerEp);
        return consumerEp;
    }
    log:printDebug("Kafka consumer instance created successfully", topic = topicName, groupId = groupName);

    kafka:TopicPartition[] kafkaTopicPartitions = partitions.'map(p => {topic: topicName, partition: p});
    log:printDebug("Assigning partitions to consumer", topic = topicName, partitions = partitions);
    kafka:Error? paritionAssignmentErr = consumerEp->assign(kafkaTopicPartitions);
    if paritionAssignmentErr is kafka:Error {
        common:logError("Error occurred while assigning partitions to the consumer", paritionAssignmentErr);
        return paritionAssignmentErr;
    }
    log:printDebug("Partitions assigned successfully", topic = topicName, assignedPartitions = partitions.length());

    log:printDebug("Processing partition offsets", topic = topicName);
    kafka:TopicPartition[] parititionsWithoutCmtdOffsets = [];
    foreach kafka:TopicPartition partition in kafkaTopicPartitions {
        log:printDebug("Checking committed offset for partition", topic = topicName, partition = partition.partition);
        kafka:PartitionOffset|kafka:Error? offset = consumerEp->getCommittedOffset(partition);
        if offset is kafka:Error {
            common:logError("Error occurred while retrieving the commited offsets for the topic-partition", offset);
            return offset;
        }

        if offset is () {
            log:printDebug("No committed offset found for partition", topic = topicName, partition = partition.partition);
            parititionsWithoutCmtdOffsets.push(partition);
        } else {
            log:printDebug("Found committed offset for partition", topic = topicName, partition = partition.partition, offset = offset.offset);
        }

        if offset is kafka:PartitionOffset {
            log:printDebug("Seeking to committed offset", topic = topicName, partition = partition.partition, offset = offset.offset);
            kafka:Error? kafkaSeekErr = consumerEp->seek(offset);
            if kafkaSeekErr is kafka:Error {
                common:logError("Error occurred while assigning seeking partitions for the consumer", kafkaSeekErr);
                return kafkaSeekErr;
            }
            log:printDebug("Successfully seeked to committed offset", topic = topicName, partition = partition.partition);
        }
    }

    if parititionsWithoutCmtdOffsets.length() > 0 {
        log:printDebug("Seeking partitions without committed offsets to beginning", topic = topicName, partitionsCount = parititionsWithoutCmtdOffsets.length());
        kafka:Error? kafkaSeekErr = consumerEp->seekToBeginning(parititionsWithoutCmtdOffsets);
        if kafkaSeekErr is kafka:Error {
            common:logError("Error occurred while assigning seeking partitions (for paritions without committed offsets) for the consumer", kafkaSeekErr);
            return kafkaSeekErr;
        }
        log:printDebug("Successfully seeked partitions without committed offsets to beginning", topic = topicName);
    }

    log:printDebug("Kafka message consumer created successfully with manual partition assignment", topic = topicName, groupId = groupName, partitionCount = partitions.length());
    return consumerEp;
}
