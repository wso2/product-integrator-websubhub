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

import websubhub.consolidator.admin as _;
import websubhub.consolidator.common;
import websubhub.consolidator.config;
import websubhub.consolidator.connections as conn;
import websubhub.consolidator.persistence as persist;

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/lang.value;
import ballerina/log;

import wso2/messagestore as store;
import wso2/messagestore.api as storeapi;

public function main() returns error? {
    error? validation = store:validateConfig(config:store);
    if validation is error {
        common:logFatalError("Message store configuration validation failed", validation);
        return;
    }

    // Initialize consolidator-service state
    error? stateSyncResult = syncSystemState();
    if stateSyncResult is error {
        common:logFatalError("Error while syncing system state during startup", stateSyncResult);
        // Exit with a failure, so that the consolidator is restarted by a restart policy that only acts on failures
        exit(1);
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
    runtime:onGracefulStop(onShutdown);
}

isolated function syncSystemState() returns error? {
    storeapi:Consumer websubEventsSnapshotConsumer = check conn:initWebSubEventSnapshotConsumer();
    do {
        // Only the latest snapshot is retained, and it is acknowledged only after it is re-persisted. If any step fails
        // before that, the consumer is closed with it unacknowledged, so that the message store redelivers it on the
        // next startup instead of the system state being lost. Older snapshots are superseded by the latest one, hence
        // they are acknowledged as soon as a newer one is received.
        storeapi:Message? lastMessage = ();
        while true {
            storeapi:Message? message = check websubEventsSnapshotConsumer->receive();
            if message is () {
                break;
            }
            if lastMessage is storeapi:Message {
                check websubEventsSnapshotConsumer->ack(lastMessage);
            }
            lastMessage = message;
        }

        if lastMessage is () {
            check websubEventsSnapshotConsumer->close();
            return;
        }

        string persistedMsg = check string:fromBytes(lastMessage.payload);
        common:SystemStateSnapshot lastStateSnapshot = check (check value:fromJsonString(persistedMsg)).fromJsonWithType();
        check persist:saveLastSnapshotMessage({
            payload: lastMessage.payload,
            metadata: lastMessage.metadata
        });
        check websubEventsSnapshotConsumer->ack(lastMessage);
        check websubEventsSnapshotConsumer->close();
        refreshTopicCache(lastStateSnapshot.topics);
        refreshSubscribersCache(lastStateSnapshot.subscriptions);
    } on fail error syncError {
        common:logFatalError("Error occurred while syncing system-state", syncError);
        error? result = websubEventsSnapshotConsumer->close();
        if result is error {
            common:logFatalError("Error occurred while gracefully closing the message store consumer", result);
        }
        return syncError;
    }
}

isolated function onShutdown() returns error? {
    log:printInfo("Shutting down the Event consolidator service, persisting the system state");
    // A single attempt, as retrying would hold up the shutdown
    error? persistError = processStateUpdate(retryOnFailure = false);
    if persistError is error {
        log:printError("Error occurred while persisting the consolidated state during shutdown, hence logging the state",
                state = constructStateSnapshot());
        return persistError;
    }
}
