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
import websubhub.config;
import websubhub.connections as conn;
import websubhub.persistence as persist;

import ballerina/http;
import ballerina/lang.value;
import ballerina/log;
import ballerina/mime;
import ballerina/websubhub;
import ballerinax/kafka;

isolated map<websubhub:VerifiedSubscription> subscribersCache = {};

const string CONSUMER_GROUP = "consumerGroup";
const string CONSUMER_TOPIC_PARTITIONS = "topicPartitions";
const string SERVER_ID = "SERVER_ID";
const string STATUS = "status";
const string STALE_STATE = "stale";

isolated function processWebsubSubscriptionsSnapshotState(websubhub:VerifiedSubscription[] subscriptions) returns error? {
    log:printDebug("Received latest state-snapshot for websub subscriptions", newState = subscriptions);
    foreach websubhub:VerifiedSubscription subscription in subscriptions {
        check processSubscription(subscription);
    }
}

isolated function processSubscription(websubhub:VerifiedSubscription subscription) returns error? {
    log:printDebug("Subscription request received", topic = subscription.hubTopic, callback = subscription.hubCallback);
    string subscriberId = common:generateSubscriberId(subscription.hubTopic, subscription.hubCallback);
    websubhub:VerifiedSubscription? existingSubscription = getSubscription(subscriberId);
    boolean isFreshSubscription = existingSubscription is ();
    boolean isRenewingStaleSubscription = false;
    if existingSubscription is websubhub:VerifiedSubscription {
        isRenewingStaleSubscription = existingSubscription.hasKey(STATUS) && existingSubscription.get(STATUS) is STALE_STATE;
    }
    boolean isMarkingSubscriptionAsStale = subscription.hasKey(STATUS) && subscription.get(STATUS) is STALE_STATE;

    lock {
        // add the subscriber if subscription event received for a new subscription or a stale subscription, when renewing a stale subscription
        if isFreshSubscription || isRenewingStaleSubscription || isMarkingSubscriptionAsStale {
            subscribersCache[subscriberId] = subscription.cloneReadOnly();
        }
    }

    if isMarkingSubscriptionAsStale {
        log:printDebug(string `Subscriber ${subscriberId} has been marked as stale, hence not starting the consumer`);
        return;
    }
    if !isFreshSubscription && !isRenewingStaleSubscription {
        log:printDebug(string `Subscriber ${subscriberId} is already available in the 'hub', hence not starting the consumer`);
        return;
    }

    string serverId = check subscription[SERVER_ID].ensureType();
    // if the subscription already exists in the `hub` instance, or the given subscription
    // does not belong to the `hub` instance do not start the consumer
    if serverId != config:server.id {
        log:printDebug(
                string `Subscriber ${subscriberId} does not belong to the current server, hence not starting the consumer`,
                subscriberServerId = serverId
        );
        return;
    }

    _ = start pollForNewUpdates(subscriberId, subscription.cloneReadOnly());
}

isolated function processUnsubscription(websubhub:VerifiedUnsubscription unsubscription) returns error? {
    log:printDebug("Unsubscription request received", topic = unsubscription.hubTopic, callback = unsubscription.hubCallback);
    string subscriberId = common:generateSubscriberId(unsubscription.hubTopic, unsubscription.hubCallback);
    lock {
        _ = subscribersCache.removeIfHasKey(subscriberId);
    }
}

isolated function pollForNewUpdates(string subscriberId, websubhub:VerifiedSubscription subscription) returns error? {
    string topic = subscription.hubTopic;
    string consumerGroup = check value:ensureType(subscription[CONSUMER_GROUP]);
    int[]? topicPartitions = check getTopicPartitions(subscription);
    log:printDebug("Creating Kafka consumer for subscription", subscriberId = subscriberId, topic = topic, consumerGroup = consumerGroup, partitions = topicPartitions);
    kafka:Consumer consumerEp = check conn:createMessageConsumer(topic, consumerGroup, topicPartitions);
    log:printDebug("Kafka consumer created successfully", subscriberId = subscriberId, topic = topic);

    log:printDebug("Creating WebSubHub client for content delivery", subscriberId = subscriberId, callback = subscription.hubCallback);
    websubhub:HubClient clientEp = check new (subscription, {
        httpVersion: http:HTTP_2_0,
        retryConfig: config:delivery.'retry,
        timeout: config:delivery.timeout
    });
    log:printDebug("WebSubHub client created successfully", subscriberId = subscriberId);

    do {
        log:printDebug("Starting message polling loop", subscriberId = subscriberId, topic = topic, pollingInterval = config:kafka.consumer.pollingInterval);
        while true {
            log:printDebug("Polling for new messages", subscriberId = subscriberId, topic = topic);
            kafka:BytesConsumerRecord[] records = check consumerEp->poll(config:kafka.consumer.pollingInterval);
            log:printDebug("Polling completed", subscriberId = subscriberId, recordCount = records.length());

            if !isValidConsumer(subscription.hubTopic, subscriberId) {
                log:printDebug("Consumer validation failed - invalidating subscription", subscriberId = subscriberId, topic = topic);
                fail error common:InvalidSubscriptionError(
                    string `Subscription ${subscriberId} or the topic ${topic} is invalid`, topic = topic, subscriberId = subscriberId
                );
            }

            if records.length() > 0 {
                log:printDebug("Notifying subscribers with received messages", subscriberId = subscriberId, messageCount = records.length());
                _ = check notifySubscribers(records, clientEp);
                log:printDebug("Subscriber notification completed successfully", subscriberId = subscriberId);
            }

            log:printDebug("Committing Kafka offset", subscriberId = subscriberId, topic = topic);
            check consumerEp->'commit();
            log:printDebug("Kafka offset committed successfully", subscriberId = subscriberId);
        }
    } on fail var e {
        log:printDebug("Error occurred in polling loop", subscriberId = subscriberId, errorMsg = e.message());
        common:logError("Error occurred while sending notification to subscriber", e);

        log:printDebug("Closing Kafka consumer gracefully", subscriberId = subscriberId, gracePeriod = config:kafka.consumer.gracefulClosePeriod);
        kafka:Error? result = consumerEp->close(config:kafka.consumer.gracefulClosePeriod);
        if result is kafka:Error {
            common:logError("Error occurred while gracefully closing kafka-consumer", result);
        } else {
            log:printDebug("Kafka consumer closed successfully", subscriberId = subscriberId);
        }

        if e is common:InvalidSubscriptionError {
            log:printDebug("Invalid subscription error - terminating consumer", subscriberId = subscriberId);
            return;
        }

        // If subscription-deleted error received, remove the subscription
        if e is websubhub:SubscriptionDeletedError {
            log:printDebug("Subscription deleted error - removing subscription from persistence", subscriberId = subscriberId);
            websubhub:VerifiedUnsubscription unsubscription = {
                hubMode: "unsubscribe",
                hubTopic: subscription.hubTopic,
                hubCallback: subscription.hubCallback,
                hubSecret: subscription.hubSecret
            };
            error? persistResult = persist:removeSubscription(unsubscription);
            if persistResult is error {
                common:logError(
                        "Error occurred while removing the subscription", persistResult, subscription = unsubscription);
            } else {
                log:printDebug("Subscription removed from persistence successfully", subscriberId = subscriberId);
            }
            return;
        }

        // Persist the subscription as a `stale` subscription whenever the content delivery fails
        log:printDebug("Marking subscription as stale due to delivery failure", subscriberId = subscriberId);
        common:StaleSubscription staleSubscription = {
            ...subscription
        };
        error? persistResult = persist:addStaleSubscription(staleSubscription);
        if persistResult is error {
            common:logError(
                    "Error occurred while persisting the stale subscription", persistResult, subscription = staleSubscription);
        } else {
            log:printDebug("Subscription marked as stale successfully", subscriberId = subscriberId);
        }
    }
}

isolated function isValidConsumer(string topicName, string subscriberId) returns boolean {
    return isTopicExist(topicName) && isSubscriptionExist(subscriberId);
}

isolated function isSubscriptionExist(string subscriberId) returns boolean {
    lock {
        return subscribersCache.hasKey(subscriberId);
    }
}

isolated function getSubscription(string subscriberId) returns websubhub:VerifiedSubscription? {
    lock {
        return subscribersCache[subscriberId].cloneReadOnly();
    }
}

isolated function notifySubscribers(kafka:BytesConsumerRecord[] records, websubhub:HubClient clientEp) returns error? {
    log:printDebug("Starting subscriber notification process", recordCount = records.length());
    future<websubhub:ContentDistributionSuccess|error>[] distributionResponses = [];
    foreach kafka:BytesConsumerRecord kafkaRecord in records {
        log:printDebug("Constructing content distribution message", offset = kafkaRecord.offset);
        websubhub:ContentDistributionMessage message = check constructContentDistMsg(kafkaRecord);
        log:printDebug("Content distribution message constructed", contentType = message.contentType);

        log:printDebug("Starting async content distribution");
        future<websubhub:ContentDistributionSuccess|error> distributionResponse = start clientEp->notifyContentDistribution(message.cloneReadOnly());
        distributionResponses.push(distributionResponse);
    }
    log:printDebug("All async content distributions started", totalDistributions = distributionResponses.length());

    log:printDebug("Waiting for content distribution responses");
    foreach var responseFuture in distributionResponses {
        log:printDebug("Waiting for distribution response");
        websubhub:ContentDistributionSuccess|error result = wait responseFuture;
        if result is error {
            log:printDebug("Content distribution failed", errorMsg = result.message());
            return result;
        }
    }
    log:printDebug("All content distributions completed successfully", totalDistributions = distributionResponses.length());
}

isolated function constructContentDistMsg(kafka:BytesConsumerRecord kafkaRecord) returns websubhub:ContentDistributionMessage|error {
    log:printDebug("Constructing content distribution message from Kafka record", offset = kafkaRecord.offset);
    byte[] content = kafkaRecord.value;
    log:printDebug("Converting Kafka record bytes to string", contentSize = content.length());
    string message = check string:fromBytes(content);
    log:printDebug("Parsing JSON payload from string message", messageLength = message.length());
    json payload = check value:fromJsonString(message);
    log:printDebug("Extracting headers from Kafka record");
    map<string|string[]> headers = check getHeaders(kafkaRecord);
    log:printDebug("Creating content distribution message", headerCount = headers.length());
    websubhub:ContentDistributionMessage distributionMsg = {
        content: payload,
        contentType: mime:APPLICATION_JSON,
        headers: headers
    };
    log:printDebug("Content distribution message constructed successfully", contentType = distributionMsg.contentType);
    return distributionMsg;
}

isolated function getHeaders(kafka:BytesConsumerRecord kafkaRecord) returns map<string|string[]>|error {
    log:printDebug("Processing headers from Kafka record", headerCount = kafkaRecord.headers.length());
    map<string|string[]> headers = {};
    foreach var ['key, value] in kafkaRecord.headers.entries().toArray() {
        log:printDebug("Processing header", headerKey = 'key);
        if value is byte[] {
            string headerStringValue = check string:fromBytes(value);
            headers['key] = headerStringValue;
            log:printDebug("Header processed as string", headerKey = 'key, valueLength = headerStringValue.length());
        } else if value is byte[][] {
            string[] headerValue = value.'map(v => check string:fromBytes(v));
            headers['key] = headerValue;
            log:printDebug("Header processed as string array", headerKey = 'key, arrayLength = headerValue.length());
        } else {
            log:printDebug("Unsupported header value type", headerKey = 'key);
        }
    }
    log:printDebug("Headers processing completed", totalHeaders = headers.length());
    return headers;
}

isolated function getTopicPartitions(websubhub:VerifiedSubscription subscription) returns int[]|error? {
    if !subscription.hasKey(CONSUMER_TOPIC_PARTITIONS) {
        return;
    }
    // Kafka topic partitions will be a string with comma separated integers eg: "1,2,3,4"
    string partitionInfo = check value:ensureType(subscription[CONSUMER_TOPIC_PARTITIONS]);
    return re `,`.split(partitionInfo).'map(p => p.trim()).'map(p => check int:fromString(p));
}
