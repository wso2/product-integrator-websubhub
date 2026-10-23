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
import ballerina/test;
import ballerina/uuid;

// Persistence of the system state. The consolidator persists a snapshot of the system state after every event, and
// restores the latest snapshot when it starts. These tests shut the snapshot queue and stop and start the
// consolidator, hence each of them leaves an open snapshot queue and a running consolidator behind, whatever its
// outcome, so that the other tests are unaffected.

// The behavior with which the system queues of the consolidator reject the messages they discard back to their
// publisher, which is what makes the broker reject a snapshot instead of silently dropping it
const REJECT_TO_SENDER_ALWAYS = "always";

// The time in seconds to let the consolidator retry a rejected snapshot. It has to be well within the retries
// configured in resources/consolidator.toml, so that the consolidator is still retrying afterwards.
const decimal RETRY_SETTLE_TIME = 2;

// ========================================
// Configuration of the system queues
// ========================================

@test:Config {groups: ["persistence"], before: restoreConsolidator, after: restoreConsolidator}
function testSystemQueuesRejectDiscardedMessages() returns error? {
    foreach string queue in [consolidatorSnapshotQueue, consolidatorEventsQueue] {
        test:assertEquals(check getRejectMsgToSenderOnDiscardBehavior(queue), REJECT_TO_SENDER_ALWAYS,
                string `The system queue ${queue} should reject the messages it discards back to their publisher`);
    }
}

@test:Config {groups: ["persistence"], before: restoreConsolidator, after: restoreConsolidator}
function testExistingSystemQueuesAreUpdatedOnStartup() returns error? {
    // A system queue created by an earlier version of the consolidator drops the messages it discards silently
    check stopConsolidator();
    foreach string queue in [consolidatorSnapshotQueue, consolidatorEventsQueue] {
        check setRejectMsgToSenderOnDiscardBehavior(queue, "when-queue-enabled");
    }

    check startConsolidatorAndWait();
    foreach string queue in [consolidatorSnapshotQueue, consolidatorEventsQueue] {
        test:assertEquals(check getRejectMsgToSenderOnDiscardBehavior(queue), REJECT_TO_SENDER_ALWAYS,
                string `The consolidator should update the existing system queue ${queue} on startup to reject ` +
                        string `the messages it discards back to their publisher`);
    }
}

// ========================================
// Persistence of the snapshots
// ========================================

@test:Config {groups: ["persistence"], before: restoreConsolidator, after: restoreConsolidator}
function testSnapshotIsPersistedOnStateChange() returns error? {
    final int lastSnapshot = check getLastSpooledMessageId(consolidatorSnapshotQueue) ?: 0;

    check registerAndWaitForTopic(newTopic());
    check waitUntil(isolated function() returns boolean|error =>
            (check getLastSpooledMessageId(consolidatorSnapshotQueue) ?: 0) > lastSnapshot,
            "the consolidator to persist a snapshot of the new state");
}

@test:Config {groups: ["persistence"], before: restoreConsolidator, after: restoreConsolidator}
function testRejectedSnapshotIsRetriedUntilAccepted() returns error? {
    final string topic = newTopic();
    final int? lastSnapshot = check getLastSpooledMessageId(consolidatorSnapshotQueue);

    // Shut the snapshot queue, so that the broker rejects the snapshot of the state that the event leads to
    check setQueueIngress(consolidatorSnapshotQueue, false);
    check registerTopicWhileSnapshotsAreRejected(topic);
    runtime:sleep(RETRY_SETTLE_TIME);

    test:assertEquals(check getLastSpooledMessageId(consolidatorSnapshotQueue), lastSnapshot,
            "No snapshot should be persisted while the snapshot queue rejects them");
    test:assertTrue((check getSpooledMessages(consolidatorEventsQueue)).length() > 0,
            "The event should not be acknowledged while its snapshot is being retried");

    // Once the snapshot queue accepts snapshots again, a retry goes through and the event is acknowledged, without
    // the consolidator having to be restarted
    check setQueueIngress(consolidatorSnapshotQueue, true);
    check waitUntil(isolated function() returns boolean|error =>
            (check getSpooledMessages(consolidatorEventsQueue)).length() == 0,
            "the consolidator to acknowledge the event once its snapshot is persisted");
    test:assertTrue((check getLastSpooledMessageId(consolidatorSnapshotQueue) ?: 0) > (lastSnapshot ?: 0),
            "A snapshot of the state should be persisted once the snapshot queue accepts it");
    test:assertTrue((check getConsolidatorStatus()).running && isConsolidatorReady(),
            "The consolidator should keep running while it retries the snapshot");

    // The consolidator still processes the events that follow
    check registerAndWaitForTopic(newTopic());
}

@test:Config {groups: ["persistence"], before: restoreConsolidator, after: restoreConsolidator}
function testConsolidatorExitsWhenSnapshotRetriesAreExhausted() returns error? {
    final string topic = newTopic();

    check setQueueIngress(consolidatorSnapshotQueue, false);
    check registerTopicWhileSnapshotsAreRejected(topic);

    // Rather than staying up without processing events, the consolidator exits with a failure, so that it is restarted
    check waitUntil(isolated function() returns boolean|error => !(check getConsolidatorStatus()).running,
            "the consolidator to exit once the retries of the snapshot are exhausted");
    ConsolidatorStatus status = check getConsolidatorStatus();
    test:assertTrue(status.exitCode is int && status.exitCode != 0,
            string `The consolidator should exit with a failure, but exited with ${status.exitCode.toString()}`);
    test:assertTrue((check getSpooledMessages(consolidatorEventsQueue)).length() > 0,
            "The event should not be acknowledged, so that it is processed again on the restart");

    // On the restart the consolidator processes the event again, from the last persisted state
    check setQueueIngress(consolidatorSnapshotQueue, true);
    check startConsolidatorAndWait();
    check waitUntil(isolated function() returns boolean|error =>
            (check getSpooledMessages(consolidatorEventsQueue)).length() == 0,
            "the consolidator to process the event again on the restart");
    test:assertTrue(check isTopicRegistered(topic), "The registration should be part of the system state");
}

// ========================================
// Restoration of the state on startup
// ========================================

@test:Config {groups: ["persistence"], before: restoreConsolidator, after: restoreConsolidator}
function testStateIsRestoredOnRestart() returns error? {
    final string topic = newTopic();
    final string callback = callbackUrl(uuid:createType4AsString());
    check registerAndWaitForTopic(topic);
    http:Response response = check subscribe(topic, callback);
    test:assertEquals(response.statusCode, http:STATUS_ACCEPTED, "Subscription should be accepted");
    check waitUntil(isolated function() returns boolean|error => isSubscribed(topic, callback),
            "the subscription to be added to the consolidator");
    SystemState stateBefore = check getSystemState();
    final readonly & int[] snapshotsBefore = (check getSpooledMessages(consolidatorSnapshotQueue))
        .map(message => message.msgId).cloneReadOnly();

    check restartConsolidator();

    SystemState stateAfter = check getSystemState();
    test:assertTrue(check isTopicRegistered(topic), "The registered topic should be restored on restart");
    test:assertTrue(check isSubscribed(topic, callback), "The subscription should be restored on restart");
    test:assertEquals(stateAfter.topics.length(), stateBefore.topics.length(),
            "Every registered topic should be restored on restart");
    test:assertEquals(stateAfter.subscriptions.length(), stateBefore.subscriptions.length(),
            "Every subscription should be restored on restart");
    // The restored snapshot is re-persisted and supersedes the ones persisted before the restart, hence they are all
    // acknowledged. The consolidator persists new snapshots as it processes events after the restart, so the queue
    // is not expected to hold a single snapshot.
    error? superseded = waitUntil(isolated function() returns boolean|error =>
            (check getSpooledMessages(consolidatorSnapshotQueue)).every(message =>
                snapshotsBefore.indexOf(message.msgId) is ()),
            "the consolidator to acknowledge the snapshots persisted before the restart");
    if superseded is error {
        int[] remaining = (check getSpooledMessages(consolidatorSnapshotQueue)).map(message => message.msgId);
        test:assertFail(string `${superseded.message()}. Snapshots before the restart: ${snapshotsBefore.toString()}, ` +
                string `on the queue now: ${remaining.toString()}`);
    }
}

@test:Config {groups: ["persistence"], before: restoreConsolidator, after: restoreConsolidator}
function testLatestSnapshotIsKeptWhenItCannotBeRepersistedOnStartup() returns error? {
    final string topic = newTopic();
    check registerAndWaitForTopic(topic);
    check stopConsolidator();
    // The snapshot the consolidator restores from on its next start
    int? latestSnapshot = check getLastSpooledMessageId(consolidatorSnapshotQueue);
    test:assertTrue(latestSnapshot is int, "A snapshot of the state should be persisted");

    // On startup the consolidator re-persists the latest snapshot before it acknowledges it. With the snapshot queue
    // shut the broker rejects the re-persisted snapshot, so once the retries are exhausted the consolidator exits.
    check setQueueIngress(consolidatorSnapshotQueue, false);
    check startConsolidator();
    check waitUntil(isolated function() returns boolean|error => !(check getConsolidatorStatus()).running,
            "the consolidator to exit as it cannot re-persist the latest snapshot");
    ConsolidatorStatus status = check getConsolidatorStatus();
    test:assertTrue(status.exitCode is int && status.exitCode != 0,
            string `The consolidator should exit with a failure, but exited with ${status.exitCode.toString()}`);

    // The older snapshots are acknowledged as superseded, but the latest one must be kept, or the state would be lost
    SpooledMessage[] remaining = check getSpooledMessages(consolidatorSnapshotQueue);
    test:assertEquals(remaining.map(message => message.msgId), [latestSnapshot],
            "Only the latest snapshot should be kept, as it could not be re-persisted");

    check setQueueIngress(consolidatorSnapshotQueue, true);
    check startConsolidatorAndWait();
    test:assertTrue(check isTopicRegistered(topic), "The state should be restored from the kept snapshot");
}

// ========================================
// Helpers
// ========================================

# Registers a topic while the snapshot queue rejects snapshots, and waits until the consolidator has applied the
# registration to its state, which it does before it persists the snapshot.
#
# + topic - The topic to register
# + return - An `error` if the registration fails or is not processed in time
function registerTopicWhileSnapshotsAreRejected(string topic) returns error? {
    http:Response response = check registerTopic(topic);
    test:assertEquals(response.statusCode, http:STATUS_OK, "Topic registration should be accepted");
    check waitUntil(isolated function() returns boolean|error => isTopicRegistered(topic),
            "the consolidator to process the registration");
}

# Opens the snapshot queue and leaves the consolidator running and ready. The consolidator is restarted if the
# snapshot queue was shut, so that the next test does not start while it is still retrying a rejected snapshot.
#
# + return - An `error` if the environment cannot be restored
function restoreConsolidator() returns error? {
    boolean snapshotQueueWasShut = !check isQueueIngressEnabled(consolidatorSnapshotQueue);
    if snapshotQueueWasShut {
        check setQueueIngress(consolidatorSnapshotQueue, true);
    }
    if !snapshotQueueWasShut && isConsolidatorReady() {
        return;
    }
    if (check getConsolidatorStatus()).running {
        check stopConsolidator();
    }
    check startConsolidatorAndWait();
}
