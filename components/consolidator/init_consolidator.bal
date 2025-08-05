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

import consolidator.common;
import consolidator.config;
import consolidator.persistence as persist;

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;
import ballerinax/kafka;
import consolidator.connections as conn;

public function main() returns error? {
    // Initialize consolidator-service state
    error? stateSyncResult = syncSystemState();
    if stateSyncResult is error {
        common:logError("Error while syncing system state during startup", stateSyncResult, "FATAL");
        return;
    }

    // Start the HTTP endpoint
    http:Listener httpListener = check new (config:consolidatorHttpEndpointPort);
    runtime:registerListener(httpListener);
    check httpListener.attach(consolidatorService, "/consolidator");
    check httpListener.attach(healthCheckService, "/health");
    check httpListener.'start();
    log:printInfo("Starting Event Consolidator Service");

    // start the consolidator-service
    _ = start consolidateSystemState();
    lock {
        startupCompleted = true;
    }
}

isolated function syncSystemState() returns error? {
    kafka:ConsumerConfiguration websubEventsSnapshotConfig = {
        groupId: config:websubEventsSnapshotConsumerGroup,
        offsetReset: "earliest",
        topics: [config:websubEventsSnapshotTopic],
        secureSocket: conn:secureSocketConfig,
        securityProtocol: kafka:PROTOCOL_SSL
    };
    kafka:Consumer websubEventsSnapshotConsumer = check new (config:kafkaUrl, websubEventsSnapshotConfig);
    do {
        common:SystemStateSnapshot[] events = check websubEventsSnapshotConsumer->pollPayload(config:pollingInterval);
        if events.length() > 0 {
            common:SystemStateSnapshot lastStateSnapshot = events.pop();
            refreshTopicCache(lastStateSnapshot.topics);
            refreshSubscribersCache(lastStateSnapshot.subscriptions);
            check persist:persistWebsubEventsSnapshot(lastStateSnapshot);
        }
    } on fail error kafkaError {
        common:logError("Error occurred while syncing system-state", kafkaError, "FATAL");
        error? result = check websubEventsSnapshotConsumer->close();
        if result is error {
            common:logError("Error occurred while gracefully closing kafka:Consumer", result);
        }
        return kafkaError;
    }
    check websubEventsSnapshotConsumer->close();
}
