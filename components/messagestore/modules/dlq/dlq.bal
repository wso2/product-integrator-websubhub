// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.org).
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

import messagestore.api;

import ballerina/lang.value;
import ballerina/log;

# Common messagestore utility to publish messages to a DLQ
#
# + dlq - The dead-letter destination
# + dlqProducer - The dead-letter producer
# + message - The message to be pushed to the DLQ
# + return - An `error` if the operation fails
public isolated function publish(string? dlq, api:Producer? dlqProducer, api:Message message) returns error? {
    if dlq is () {
        log:printWarn("Dead-Letter configurations are disabled, hence ignoring the message and continue");
        return;
    }
    if dlqProducer is () {
        log:printWarn("Could not find the DLQ producer, hence ignoring the message and continue");
        return;
    }
    check dlqProducer->send(dlq, message);
    var sendResult = dlqProducer->send(dlq, message);
    if sendResult is error {
        var reconnectResult = dlqProducer->reconnect();
        if reconnectResult is error {
            log:printError(string `Failed to reconnect to the DLQ: ${reconnectResult.message()}`, reconnectResult);
        }
    }
    return sendResult;
}

# The field name that can be found in the meta-information provided during consumer creation for dead-letter configurations.
const string DLQ_TOPIC = "dlqTopic";

# Retrieves the name of the dead-letter topic.
#
# + systemDlqTopic - The default DLQ name
# + meta - Additional meta information to resolve the DLQ name
# + return - DLQ name if it exist, nil if there is no DLQ configured, or else an error
public isolated function resolveDeadLetterTopic(string? systemDlqTopic, record {} meta) returns string|error? {
    // Subscriber-level DLQ topic takes priority over the system-level configuration
    if meta.hasKey(DLQ_TOPIC) {
        return value:ensureType(meta[DLQ_TOPIC]);
    }
    return systemDlqTopic;
}
