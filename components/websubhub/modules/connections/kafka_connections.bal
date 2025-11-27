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

import websubhub.common;

import ballerina/lang.value;
import ballerina/websubhub;

import wso2/message.store;

const string CONSUMER_GROUP = "consumerGroup";
const string CONSUMER_TOPIC_PARTITIONS = "topicPartitions";

isolated function createKafkaConsumerForSubscriber(websubhub:VerifiedSubscription subscription, store:KafkaConfig config)
    returns store:Consumer|error {

    string consumerGroup = check getKafkaConsumerGroup(subscription);
    int[]? topicPartitions = check getKafkaTopicPartitions(subscription);
    return store:createKafkaConsumer(
            config,
            consumerGroup,
            subscription.hubTopic,
            autoCommit = false,
            partitions = topicPartitions
    );
}

isolated function getKafkaConsumerGroup(websubhub:VerifiedSubscription subscription) returns string|error {
    if subscription.hasKey(CONSUMER_GROUP) {
        return value:ensureType(subscription[CONSUMER_GROUP]);
    }
    string timestamp = check value:ensureType(subscription[common:SUBSCRIPTION_TIMESTAMP]);
    return string `${subscription.hubTopic}___${subscription.hubCallback}___${timestamp}`;
}

isolated function getKafkaTopicPartitions(websubhub:VerifiedSubscription subscription) returns int[]|error? {
    if !subscription.hasKey(CONSUMER_TOPIC_PARTITIONS) {
        return;
    }
    // Kafka topic partitions will be a string with comma separated integers eg: "1,2,3,4"
    string partitionInfo = check value:ensureType(subscription[CONSUMER_TOPIC_PARTITIONS]);
    return re `,`.split(partitionInfo).'map(p => p.trim()).'map(p => check int:fromString(p));
}
