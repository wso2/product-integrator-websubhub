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
import ballerina/jballerina.java;
import ballerina/lang.runtime;
import ballerina/lang.value;
import ballerina/log;
import ballerina/websubhub;

import wso2/messagestore.api as storeapi;

function initializeHubState() returns error? {
    http:Client stateSnapshot;
    common:HttpClientConfig? config = config:state.snapshot.config;
    if config is common:HttpClientConfig {
        http:ClientConfiguration clientConfig = {
            timeout: config.timeout,
            retryConfig: config?.'retry,
            secureSocket: config.secureSocket
        };
        stateSnapshot = check new (config:state.snapshot.url, clientConfig);
    } else {
        stateSnapshot = check new (config:state.snapshot.url);
    }
    do {
        common:SystemStateSnapshot systemStateSnapshot = check stateSnapshot->/;
        processWebsubTopicsSnapshotState(systemStateSnapshot.topics);
        check processWebsubSubscriptionsSnapshotState(systemStateSnapshot.subscriptions);
        // Start hub-state update worker
        _ = start updateHubState();
    } on fail error httpError {
        common:logFatalError("Error occurred while initializing the hub-state using the latest state-snapshot", httpError);
        return httpError;
    }
}

// The state-update events are consumed for as long as the hub runs. When the connection to the message store is lost,
// e.g. while the broker restarts, the consumer is reconnected and the consumption resumes. An event that was received
// but not acknowledged is redelivered once the consumer is reconnected.
function updateHubState() {
    validateReconnectInterval();
    do {
        while true {
            storeapi:Message|error? message = conn:websubEventsConsumer->receive();
            if message is error {
                common:logRecoverableError("Error occurred while receiving state-update event from the message store",
                        message);
                reconnectWebSubEventsConsumer();
                continue;
            }
            if message is () {
                continue;
            }

            string|error lastPersistedData = string:fromBytes(message.payload);
            error? result = lastPersistedData is string ? processStateUpdateEvent(lastPersistedData) : lastPersistedData;
            if result is error {
                common:logRecoverableError(
                        "Error occurred while processing state-update event, hence moving it to the dead-letter queue",
                        result);
                check conn:websubEventsConsumer->deadLetter(message);
                continue;
            }
            error? ackResult = conn:websubEventsConsumer->ack(message);
            if ackResult is error {
                common:logRecoverableError("Error occurred while acknowledging state-update event", ackResult);
                reconnectWebSubEventsConsumer();
            }
        }
    } on fail error e {
        error? closeResult = conn:websubEventsConsumer->close();
        if closeResult is error {
            common:logFatalError("Error occurred while closing the state-update event consumer", closeResult);
        }
        common:logFatalError("Stopped processing state-update events, hence exiting the hub", e);
        exit(1);
    }
}

// Terminates the process with the given exit code
isolated function exit(int status) = @java:Method {
    'class: "java.lang.System",
    name: "exit",
    paramTypes: ["int"]
} external;

// Reconnects the state-update event consumer, retrying every `state.reconnect.interval` until the message store is
// reachable again
function reconnectWebSubEventsConsumer() {
    while true {
        error? result = conn:websubEventsConsumer->reconnect();
        if result is () {
            log:printInfo("Reconnected the state-update event consumer");
            return;
        }
        common:logRecoverableError("Error occurred while reconnecting the state-update event consumer", result);
        runtime:sleep(getReconnectInterval());
    }
}

function validateReconnectInterval() {
    if config:state.reconnect.interval < 0d {
        log:printWarn("state configuration: reconnect interval should be greater than or equal to 0. Hence falling back to default value of 1 second");
    } else if config:state.reconnect.interval == 0d {
        log:printWarn("state configuration: reconnect interval is set to 0, which may cause continuous reconnection attempts");
    }
}

function getReconnectInterval() returns decimal {
    return config:state.reconnect.interval < 0d ? 1d : config:state.reconnect.interval;
}

function processStateUpdateEvent(string persistedData) returns error? {
    json event = check value:fromJsonString(persistedData);
    string hubMode = check event.hubMode;
    match event.hubMode {
        "register" => {
            common:TopicRegistration topicRegistration = check event.fromJsonWithType();
            processTopicRegistration(topicRegistration);
        }
        "deregister" => {
            websubhub:TopicDeregistration topicDeregistration = check event.fromJsonWithType();
            processTopicDeregistration(topicDeregistration);
        }
        "subscribe" => {
            websubhub:VerifiedSubscription subscription = check event.fromJsonWithType();
            check processSubscription(subscription);
        }
        "unsubscribe" => {
            websubhub:VerifiedUnsubscription unsubscription = check event.fromJsonWithType();
            check processUnsubscription(unsubscription);
        }
        _ => {
            return error(string `Error occurred while deserializing state-update events with invalid hubMode [${hubMode}]`);
        }
    }
}
