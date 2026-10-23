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

import ballerina/lang.runtime;

import wso2/messagestore.api as storeapi;

# Re-persists the latest state snapshot read during startup. Returns only after the message store has acknowledged
# the snapshot, so that the caller can safely acknowledge the original snapshot. A failed persistence is retried as
# configured in `persistRetry`.
#
# + message - The latest state snapshot message
# + return - An `error` if the snapshot could not be persisted or was rejected by the message store once the retries
# are exhausted
public isolated function saveLastSnapshotMessage(storeapi:Message message) returns error? {
    return produceMessageWithRetry(config:state.snapshot.topic, message, true);
}

# Persists the given system state snapshot. Returns only after the message store has acknowledged the snapshot.
#
# + systemStateSnapshot - The system state snapshot
# + retryOnFailure - Whether to retry a failed persistence as configured in `persistRetry`. It is turned off where the
# caller cannot wait for the retries, e.g. during a graceful shutdown.
# + return - An `error` if the snapshot could not be persisted or was rejected by the message store, once the retries
# are exhausted if they are turned on
public isolated function saveWebsubEventsSnapshot(common:SystemStateSnapshot systemStateSnapshot,
        boolean retryOnFailure = true) returns error? {
    json data = systemStateSnapshot.toJson();
    byte[] payload = data.toJsonString().toBytes();
    return produceMessageWithRetry(config:state.snapshot.topic, {payload}, retryOnFailure);
}

isolated function produceMessageWithRetry(string topic, storeapi:Message message, boolean retryOnFailure)
        returns error? {
    var {maxRetries, retryInterval, backOffFactor, maxWaitInterval} = config:state.persistRetry;
    int retries = 0;
    decimal waitInterval = retryInterval;
    while true {
        error? result = produceMessage(topic, message);
        if result is () || !retryOnFailure || retries >= maxRetries {
            return result;
        }
        retries += 1;
        common:logRecoverableError(string `Failed to persist the state snapshot, hence retrying in ${waitInterval}s`,
                result, attempt = retries, maxRetries = maxRetries);
        runtime:sleep(waitInterval);
        waitInterval = decimal:min(waitInterval * backOffFactor, maxWaitInterval);
    }
}

isolated function produceMessage(string topic, storeapi:Message message) returns error? {
    storeapi:Producer producer = check conn:getMessageProducer(topic);
    var sendResult = producer->send(topic, message);
    if sendResult is error {
        var reconnectResult = producer->reconnect();
        if reconnectResult is error {
            common:logFatalError(string `Failed to reconnect to the topic: ${reconnectResult.message()}`, reconnectResult);
        }
    }
    return sendResult;
}
