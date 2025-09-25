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
    kafka:Consumer consumerEp = check conn:createMessageConsumer(topic, consumerGroup, topicPartitions);
    websubhub:HubClient clientEp = check new (subscription, {
        httpVersion: http:HTTP_2_0,
        retryConfig: config:delivery.'retry,
        timeout: config:delivery.timeout
    });
    do {
        while true {
            kafka:BytesConsumerRecord[] records = check consumerEp->poll(config:kafka.consumer.pollingInterval);
            if !isValidConsumer(subscription.hubTopic, subscriberId) {
                fail error common:InvalidSubscriptionError(
                    string `Subscription ${subscriberId} or the topic ${topic} is invalid`, topic = topic, subscriberId = subscriberId
                );
            }
            _ = check notifySubscribers(records, clientEp);
            check consumerEp->'commit();
        }
    } on fail var e {
        common:logError("Error occurred while sending notification to subscriber", e);
        kafka:Error? result = consumerEp->close(config:kafka.consumer.gracefulClosePeriod);
        if result is kafka:Error {
            common:logError("Error occurred while gracefully closing kafka-consumer", result);
        }

        if e is common:InvalidSubscriptionError {
            return;
        }

        // If subscription-deleted error received, remove the subscription
        if e is websubhub:SubscriptionDeletedError {
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
            }
            return;
        }

        // Persist the subscription as a `stale` subscription whenever the content delivery fails
        common:StaleSubscription staleSubscription = {
            ...subscription
        };
        error? persistResult = persist:addStaleSubscription(staleSubscription);
        if persistResult is error {
            common:logError(
                    "Error occurred while persisting the stale subscription", persistResult, subscription = staleSubscription);
        }
    }
}

isolated function isValidConsumer(string topicName, string subscriberId) returns boolean {
    return isValidTopic(topicName) && isValidSubscription(subscriberId);
}

isolated function isValidSubscription(string subscriberId) returns boolean {
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
    future<websubhub:ContentDistributionSuccess|error>[] distributionResponses = [];
    foreach var kafkaRecord in records {
        websubhub:ContentDistributionMessage message = check constructContentDistMsg(kafkaRecord);
        future<websubhub:ContentDistributionSuccess|error> distributionResponse = start clientEp->notifyContentDistribution(message.cloneReadOnly());
        distributionResponses.push(distributionResponse);
    }

    foreach var responseFuture in distributionResponses {
        websubhub:ContentDistributionSuccess|error result = wait responseFuture;
        if result is error {
            return result;
        }
    }
}

isolated function constructContentDistMsg(kafka:BytesConsumerRecord kafkaRecord) returns websubhub:ContentDistributionMessage|error {
    byte[] content = kafkaRecord.value;
    string message = check string:fromBytes(content);
    json payload = check value:fromJsonString(message);
    websubhub:ContentDistributionMessage distributionMsg = {
        content: payload,
        contentType: mime:APPLICATION_JSON,
        headers: check getHeaders(kafkaRecord)
    };
    return distributionMsg;
}

isolated function getHeaders(kafka:BytesConsumerRecord kafkaRecord) returns map<string|string[]>|error {
    map<string|string[]> headers = {};
    foreach var ['key, value] in kafkaRecord.headers.entries().toArray() {
        if value is byte[] {
            headers['key] = check string:fromBytes(value);
        } else if value is byte[][] {
            string[] headerValue = value.'map(v => check string:fromBytes(v));
            headers['key] = headerValue;
        }
    }
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
