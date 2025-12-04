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

import websubhub.consolidator.common;
import websubhub.consolidator.config;
import websubhub.consolidator.connections as conn;
import websubhub.consolidator.persistence as persist;

import ballerina/http;
import ballerina/lang.value;
import ballerina/log;
import ballerinax/kafka;

http:Service consolidatorService = service object {
    isolated resource function get state\-snapshot() returns common:SystemStateSnapshot {
        common:SystemStateSnapshot stateSnapshot = {
            topics: getTopics(),
            subscriptions: getSubscriptions()
        };
        log:printDebug("Request received to retrieve state-snapshot, hence responding with the current state-snapshot", state = stateSnapshot);
        return stateSnapshot;
    }
};

isolated function consolidateSystemState() returns error? {
    do {
        while true {
            kafka:BytesConsumerRecord[] records = check conn:websubEventConsumer->poll(config:kafka.consumer.pollingInterval);
            log:printDebug("Polled Kafka records for state consolidation", recordCount = records.length(), pollingInterval = config:kafka.consumer.pollingInterval);

            if records.length() > 0 {
                log:printDebug("Processing batch of Kafka records", batchSize = records.length());
            }

            foreach kafka:BytesConsumerRecord currentRecord in records {
                string lastPersistedData = check string:fromBytes(currentRecord.value);
                int messageSize = lastPersistedData.length();
                log:printDebug("Processing Kafka record for consolidation", messageSize = messageSize, offset = currentRecord.offset);
                error? result = processPersistedData(lastPersistedData);
                if result is error {
                    common:logError("Error occurred while processing received event ", result);
                } else {
                    log:printDebug("Successfully processed Kafka record", offset = currentRecord.offset);
                }
            }
        }
    } on fail var e {
        log:printDebug("Error in consolidation loop, closing Kafka consumer", gracePeriod = config:kafka.consumer.gracefulClosePeriod);
        _ = check conn:websubEventConsumer->close(config:kafka.consumer.gracefulClosePeriod);
        return e;
    }
}

isolated function processPersistedData(string persistedData) returns error? {
    log:printDebug("Starting persisted data processing", dataSize = persistedData.length());

    json payload = check value:fromJsonString(persistedData);
    string hubMode = check payload.hubMode;
    log:printDebug("Processing event based on hub mode", hubMode = hubMode);

    match hubMode {
        "register" => {
            log:printDebug("Processing topic registration event");
            check processTopicRegistration(payload);
            log:printDebug("Topic registration event processed successfully");
        }
        "deregister" => {
            log:printDebug("Processing topic deregistration event");
            check processTopicDeregistration(payload);
            log:printDebug("Topic deregistration event processed successfully");
        }
        "subscribe" => {
            log:printDebug("Processing subscription event");
            check processSubscription(payload);
            log:printDebug("Subscription event processed successfully");
        }
        "unsubscribe" => {
            log:printDebug("Processing unsubscription event");
            check processUnsubscription(payload);
            log:printDebug("Unsubscription event processed successfully");
        }
        _ => {
            common:logError("Invalid hub mode received", hubMode = hubMode);
            return error(string `Error occurred while deserializing subscriber events with invalid hubMode [${hubMode}]`);
        }
    }
    log:printDebug("Completed processing persisted data", hubMode = hubMode);
}

isolated function processStateUpdate() returns error? {
    log:printDebug("Processing state update - gathering current system state");
    common:SystemStateSnapshot stateSnapshot = {
        topics: getTopics(),
        subscriptions: getSubscriptions()
    };
    log:printDebug("Created state snapshot for persistence", topicCount = stateSnapshot.topics.length(), subscriptionCount = stateSnapshot.subscriptions.length());
    check persist:persistWebsubEventsSnapshot(stateSnapshot);
    log:printDebug("State snapshot persisted successfully");
}
