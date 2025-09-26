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

import ballerina/http;
import ballerina/lang.value;
import ballerina/log;
import ballerina/websubhub;
import ballerinax/kafka;

function initializeHubState() returns error? {
    log:printDebug("Starting hub state initialization", snapshotUrl = config:state.snapshot.url);
    http:Client stateSnapshot;
    common:HttpClientConfig? config = config:state.snapshot.config;
    if config is common:HttpClientConfig {
        log:printDebug("Creating HTTP client with custom configuration", timeout = config.timeout);
        http:ClientConfiguration clientConfig = {
            timeout: config.timeout,
            retryConfig: config.'retry,
            secureSocket: config.secureSocket
        };
        stateSnapshot = check new (config:state.snapshot.url, clientConfig);
    } else {
        log:printDebug("Creating HTTP client with default configuration");
        stateSnapshot = check new (config:state.snapshot.url);
    }
    do {
        log:printDebug("Fetching system state snapshot from consolidator");
        common:SystemStateSnapshot systemStateSnapshot = check stateSnapshot->/consolidator/state\-snapshot;
        log:printDebug("State snapshot retrieved successfully", topicCount = systemStateSnapshot.topics.length(), subscriptionCount = systemStateSnapshot.subscriptions.length());

        log:printDebug("Processing topics from state snapshot");
        check processWebsubTopicsSnapshotState(systemStateSnapshot.topics);
        log:printDebug("Topics from state snapshot processed successfully");

        log:printDebug("Processing subscriptions from state snapshot");
        check processWebsubSubscriptionsSnapshotState(systemStateSnapshot.subscriptions);
        log:printDebug("Subscriptions from state snapshot processed successfully");

        // Start hub-state update worker
        log:printDebug("Starting hub state update worker");
        _ = start updateHubState();
        log:printDebug("Hub state initialization completed successfully");
    } on fail error httpError {
        common:logError("Error occurred while initializing the hub-state using the latest state-snapshot", httpError, severity = "FATAL");
        return httpError;
    }
}

function updateHubState() returns error? {
    log:printDebug("Hub state update worker started", pollingInterval = config:kafka.consumer.pollingInterval);
    while true {
        log:printDebug("Polling for state update events from Kafka", topic = config:state.events.topic);
        kafka:BytesConsumerRecord[] records = check conn:websubEventsConsumer->poll(config:kafka.consumer.pollingInterval);
        if records.length() <= 0 {
            log:printDebug("No state update events received in this poll cycle");
            continue;
        }
        log:printDebug("Received state update events from Kafka", eventCount = records.length());
        foreach kafka:BytesConsumerRecord currentRecord in records {
            log:printDebug("Processing state update event", offset = currentRecord.offset);
            string lastPersistedData = check string:fromBytes(currentRecord.value);
            error? result = processStateUpdateEvent(lastPersistedData);
            if result is error {
                common:logError("Error occurred while processing state-update event", result, severity = "FATAL");
                return result;
            } else {
                log:printDebug("State update event processed successfully", offset = currentRecord.offset);
            }
        }
        log:printDebug("All state update events in batch processed successfully", eventCount = records.length());
    }
}

function processStateUpdateEvent(string persistedData) returns error? {
    log:printDebug("Parsing state update event JSON", dataSize = persistedData.length());
    json event = check value:fromJsonString(persistedData);
    string hubMode = check event.hubMode;
    log:printDebug("State update event parsed successfully", hubMode = hubMode);
    match hubMode {
        "register" => {
            log:printDebug("Processing topic registration event");
            websubhub:TopicRegistration topicRegistration = check event.fromJsonWithType();
            log:printDebug("Topic registration event deserialized", topic = topicRegistration.topic);
            check processTopicRegistration(topicRegistration);
            log:printDebug("Topic registration event processed successfully", topic = topicRegistration.topic);
        }
        "deregister" => {
            log:printDebug("Processing topic deregistration event");
            websubhub:TopicDeregistration topicDeregistration = check event.fromJsonWithType();
            log:printDebug("Topic deregistration event deserialized", topic = topicDeregistration.topic);
            check processTopicDeregistration(topicDeregistration);
            log:printDebug("Topic deregistration event processed successfully", topic = topicDeregistration.topic);
        }
        "subscribe" => {
            log:printDebug("Processing subscription event");
            websubhub:VerifiedSubscription subscription = check event.fromJsonWithType();
            log:printDebug("Subscription event deserialized", topic = subscription.hubTopic, callback = subscription.hubCallback);
            check processSubscription(subscription);
            log:printDebug("Subscription event processed successfully", topic = subscription.hubTopic, callback = subscription.hubCallback);
        }
        "unsubscribe" => {
            log:printDebug("Processing unsubscription event");
            websubhub:VerifiedUnsubscription unsubscription = check event.fromJsonWithType();
            log:printDebug("Unsubscription event deserialized", topic = unsubscription.hubTopic, callback = unsubscription.hubCallback);
            check processUnsubscription(unsubscription);
            log:printDebug("Unsubscription event processed successfully", topic = unsubscription.hubTopic, callback = unsubscription.hubCallback);
        }
        _ => {
            log:printDebug("Invalid hub mode in state update event", hubMode = hubMode);
            return error(string `Error occurred while deserializing state-update events with invalid hubMode [${hubMode}]`);
        }
    }
    log:printDebug("State update event processing completed", hubMode = hubMode);
}
