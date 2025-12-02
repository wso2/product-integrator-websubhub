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
import ballerina/lang.runtime;
import ballerina/lang.value;
import ballerina/log;

import wso2/messagestore as store;

public function main() returns error? {
    // Initialize consolidator-service state
    error? stateSyncResult = syncSystemState();
    if stateSyncResult is error {
        common:logFatalError("Error while syncing system state during startup", stateSyncResult);
        return;
    }

    // Start the HTTP endpoint
    http:Listener httpListener = check new (config:server.port,
        secureSocket = config:server.secureSocket
    );
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
    store:Consumer websubEventsSnapshotConsumer = check conn:initWebSubEventSnapshotConsumer();
    do {
        store:Message? message = check websubEventsSnapshotConsumer->receive();
        if message is () {
            return websubEventsSnapshotConsumer->close();
        }

        string persistedMsg = check string:fromBytes(message.payload);
        common:SystemStateSnapshot[] events = check value:fromJsonString(persistedMsg).ensureType();
        if events.length() > 0 {
            common:SystemStateSnapshot lastStateSnapshot = events.pop();
            refreshTopicCache(lastStateSnapshot.topics);
            refreshSubscribersCache(lastStateSnapshot.subscriptions);
            check persist:persistWebsubEventsSnapshot(lastStateSnapshot);
        }
        return websubEventsSnapshotConsumer->close();
    } on fail error kafkaError {
        common:logFatalError("Error occurred while syncing system-state", kafkaError);
        error? result = check websubEventsSnapshotConsumer->close();
        if result is error {
            common:logFatalError("Error occurred while gracefully closing the message store consumer", result);
        }
        return kafkaError;
    }
}
