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

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/url;

# The URL through which the integration-tests Gradle build stops and starts the consolidator, e.g.
# `http://localhost:9585`
public configurable string controlUrl = ?;
# The queue the consolidator persists the snapshots of the system state to
public configurable string consolidatorSnapshotQueue = ?;
# The queue the consolidator consumes the events that update the system state from
public configurable string consolidatorEventsQueue = ?;

final http:Client controlClient = check new (controlUrl);

# The process of the consolidator, as reported by the integration-tests Gradle build.
public type ConsolidatorStatus record {
    # Whether the consolidator is running
    boolean running;
    # The exit code of the consolidator, once it has exited
    int? exitCode = ();
};

# A message spooled on a queue of the broker.
public type SpooledMessage record {
    # The identifier the broker assigned to the message, which increases with every message it spools
    int msgId;
};

# Stops the consolidator, gracefully if the platform allows. On Linux and macOS the consolidator persists the system
# state once more as it shuts down, whereas on Windows it is terminated.
#
# + return - An `error` if the consolidator could not be stopped
public isolated function stopConsolidator() returns error? {
    http:Response response = check controlClient->post("/components/consolidator/stop", ());
    check expectSuccess(response, "stop the consolidator");
}

# Starts the consolidator, without waiting for it to be ready.
#
# + return - An `error` if the consolidator could not be started
public isolated function startConsolidator() returns error? {
    http:Response response = check controlClient->post("/components/consolidator/start", ());
    check expectSuccess(response, "start the consolidator");
}

# Starts the consolidator and waits until it is ready, which is once it has restored the system state.
#
# + return - An `error` if the consolidator exits or is not ready in time
public isolated function startConsolidatorAndWait() returns error? {
    check startConsolidator();
    decimal waited = 0;
    while waited < eventualTimeout {
        if isConsolidatorReady() {
            return;
        }
        ConsolidatorStatus status = check getConsolidatorStatus();
        if !status.running {
            return error(string `The consolidator exited with code ${status.exitCode.toString()} before it was ` +
                    string `ready`);
        }
        runtime:sleep(0.5);
        waited += 0.5d;
    }
    return error(string `Timed out after ${eventualTimeout}s waiting for the consolidator to be ready`);
}

# Stops the consolidator and starts it again, waiting until it is ready.
#
# + return - An `error` if the consolidator could not be restarted
public isolated function restartConsolidator() returns error? {
    check stopConsolidator();
    check startConsolidatorAndWait();
}

# Retrieves the status of the process of the consolidator.
#
# + return - The status, or an `error` if the request fails
public isolated function getConsolidatorStatus() returns ConsolidatorStatus|error {
    return controlClient->get("/components/consolidator");
}

# Checks whether the consolidator reports itself ready.
#
# + return - `true` if the consolidator is ready
public isolated function isConsolidatorReady() returns boolean {
    http:Response|error response = consolidatorClient->get("/health/readiness");
    return response is http:Response && response.statusCode == http:STATUS_OK;
}

# Opens or shuts a queue of the broker to new messages. A shut queue discards the guaranteed messages published to
# it, and the system queues of the consolidator reject them back to their publisher.
#
# + queue - The name of the queue
# + enabled - Whether the queue should accept new messages
# + return - An `error` if the broker rejects the change
public isolated function setQueueIngress(string queue, boolean enabled) returns error? {
    check updateQueue(queue, {ingressEnabled: enabled});
}

# Checks whether a queue of the broker accepts new messages.
#
# + queue - The name of the queue
# + return - `true` if the queue accepts new messages, or an `error` if the queue cannot be retrieved
public isolated function isQueueIngressEnabled(string queue) returns boolean|error {
    map<json> config = check getQueueConfig(queue);
    return config["ingressEnabled"].ensureType();
}

# Retrieves how a queue of the broker reports the messages it discards to their publisher.
#
# + queue - The name of the queue
# + return - The `rejectMsgToSenderOnDiscardBehavior` of the queue, or an `error` if it cannot be retrieved
public isolated function getRejectMsgToSenderOnDiscardBehavior(string queue) returns string|error {
    map<json> config = check getQueueConfig(queue);
    return config["rejectMsgToSenderOnDiscardBehavior"].ensureType();
}

# Changes how a queue of the broker reports the messages it discards to their publisher.
#
# + queue - The name of the queue
# + behavior - The `rejectMsgToSenderOnDiscardBehavior` to set
# + return - An `error` if the broker rejects the change
public isolated function setRejectMsgToSenderOnDiscardBehavior(string queue, string behavior) returns error? {
    check updateQueue(queue, {rejectMsgToSenderOnDiscardBehavior: behavior});
}

# Retrieves the messages spooled on a queue of the broker, in the order the broker spooled them. A message stays
# spooled until it is acknowledged, hence the result includes the messages delivered but not yet acknowledged.
#
# + queue - The name of the queue
# + return - The spooled messages, or an `error` if they cannot be retrieved
public isolated function getSpooledMessages(string queue) returns SpooledMessage[]|error {
    SpooledMessage[] messages = [];
    string? path = string `/monitor/msgVpns/default/queues/${check url:encode(queue, "UTF-8")}/msgs` +
            string `?count=100&select=msgId`;
    while path is string {
        http:Response response = check brokerSempClient->get(path);
        json body = check response.getJsonPayload();
        if response.statusCode != http:STATUS_OK {
            return error(string `Failed to retrieve the messages of the queue ${queue}: ${body.toJsonString()}`);
        }
        SpooledMessage[] page = check (check body.data).cloneWithType();
        messages.push(...page);
        json|error nextPageUri = body.meta.paging.nextPageUri;
        path = nextPageUri is string ? check relativeSempPath(nextPageUri) : ();
    }
    return messages.sort(key = isolated function(SpooledMessage message) returns int => message.msgId);
}

# Retrieves the identifier of the last message spooled on a queue of the broker.
#
# + queue - The name of the queue
# + return - The identifier of the last message, `()` if the queue is empty, or an `error` if it cannot be retrieved
public isolated function getLastSpooledMessageId(string queue) returns int?|error {
    SpooledMessage[] messages = check getSpooledMessages(queue);
    return messages.length() == 0 ? () : messages[messages.length() - 1].msgId;
}

isolated function getQueueConfig(string queue) returns map<json>|error {
    http:Response response = check brokerSempClient->get(
            string `/config/msgVpns/default/queues/${check url:encode(queue, "UTF-8")}`);
    json body = check response.getJsonPayload();
    if response.statusCode != http:STATUS_OK {
        return error(string `Failed to retrieve the queue ${queue}: ${body.toJsonString()}`);
    }
    return (check body.data).ensureType();
}

isolated function updateQueue(string queue, map<json> changes) returns error? {
    http:Response response = check brokerSempClient->patch(
            string `/config/msgVpns/default/queues/${check url:encode(queue, "UTF-8")}`, changes);
    if response.statusCode != http:STATUS_OK {
        return error(string `Failed to update the queue ${queue} with ${changes.toJsonString()}: ` +
                check response.getTextPayload());
    }
}

// The broker reports the next page as an absolute URL, whereas the client is bound to the base URL of SEMP
isolated function relativeSempPath(string uri) returns string|error {
    int? base = uri.indexOf("/SEMP/v2");
    if base is () {
        return error(string `Unexpected SEMP paging URI: ${uri}`);
    }
    return uri.substring(base + "/SEMP/v2".length());
}

isolated function expectSuccess(http:Response response, string action) returns error? {
    if response.statusCode != http:STATUS_OK {
        return error(string `Failed to ${action}: ${response.statusCode} ${check response.getTextPayload()}`);
    }
}
