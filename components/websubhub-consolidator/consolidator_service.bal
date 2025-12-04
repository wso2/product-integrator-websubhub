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
import websubhub.consolidator.connections as conn;
import websubhub.consolidator.persistence as persist;

import ballerina/http;
import ballerina/lang.value;
import ballerina/log;
import ballerina/websubhub;

import wso2/messagestore as store;

http:Service consolidatorService = service object {
    isolated resource function get state\-snapshot() returns common:SystemStateSnapshot {
        common:SystemStateSnapshot stateSnapshot = {
            topics: getTopics(),
            subscriptions: getSubscriptions()
        };
        log:printInfo("Request received to retrieve state-snapshot, hence responding with the current state-snapshot", state = stateSnapshot);
        return stateSnapshot;
    }
};

isolated function consolidateSystemState() returns error? {
    do {
        while true {
            store:Message? message = check conn:websubEventsConsumer->receive();
            if message is () {
                continue;
            }

            string lastPersistedData = check string:fromBytes(message.payload);
            error? result = processStateUpdateEvent(lastPersistedData);
            if result is error {
                common:logFatalError("Error occurred while processing received event ", 'error = result);
                check conn:websubEventsConsumer->nack(message);
                check result;
            } else {
                check conn:websubEventsConsumer->ack(message);
            }
        }
    } on fail var e {
        _ = check conn:websubEventsConsumer->close();
        return e;
    }
}

isolated function processStateUpdateEvent(string persistedData) returns error? {
    json event = check value:fromJsonString(persistedData);
    string hubMode = check event.hubMode;
    match hubMode {
        "register" => {
            websubhub:TopicRegistration topicRegistration = check event.fromJsonWithType();
            check processTopicRegistration(topicRegistration);
        }
        "deregister" => {
            websubhub:TopicDeregistration topicDeregistration = check event.fromJsonWithType();
            check processTopicDeregistration(topicDeregistration);
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
            return error(string `Error occurred while deserializing subscriber events with invalid hubMode [${hubMode}]`);
        }
    }
}

isolated function processStateUpdate() returns error? {
    common:SystemStateSnapshot stateSnapshot = {
        topics: getTopics(),
        subscriptions: getSubscriptions()
    };
    check persist:saveWebsubEventsSnapshot(stateSnapshot);
}

isolated function constructStateSnapshot() returns common:SystemStateSnapshot => {
    topics: getTopics(),
    subscriptions: getSubscriptions()
};

