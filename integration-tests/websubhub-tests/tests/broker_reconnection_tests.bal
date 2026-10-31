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

// Reconnection to the broker. The broker restarts e.g. during maintenance, and the hub has to resume consuming both
// the state-update events and the content to deliver once the broker is back. The consolidator exits when it loses the
// broker, so that it is restarted, hence the test starts it again. The test leaves every component connected to the
// broker again, so that the other tests are unaffected.

// The time in seconds to allow the components to reconnect to the broker once it is back
const decimal RECONNECT_TIMEOUT = 180;

@test:Config {groups: ["reconnection"], after: recoverFromBrokerRestart}
function testHubResumesConsumingAfterBrokerRestart() returns error? {
    final string topicBefore = newTopic();
    final string idBefore = uuid:createType4AsString();
    check subscribeAndWait(topicBefore, idBefore);

    check restartBroker();
    check restoreConsolidator();

    // The hub resumes consuming the state-update events, so a topic registered after the restart becomes usable
    final string topicAfter = newTopic();
    check waitUntil(isolated function() returns boolean|error {
        http:Response response = check registerTopic(topicAfter);
        return response.statusCode == http:STATUS_OK || response.statusCode == http:STATUS_CONFLICT;
    }, "the hub to accept topic registrations after the broker restart");
    check waitUntil(isolated function() returns boolean|error {
        http:Response response = check publish(topicAfter, {"event": "probe"});
        return response.statusCode == http:STATUS_OK;
    }, "the hub to apply a topic registration made after the broker restart");

    // and so does a subscription made after the restart, to which the content is delivered
    final string idAfter = uuid:createType4AsString();
    final string callbackAfter = callbackUrl(idAfter);
    http:Response response = check subscribe(topicAfter, callbackAfter);
    test:assertEquals(response.statusCode, http:STATUS_ACCEPTED, "Subscription should be accepted");
    check waitUntil(isolated function() returns boolean|error => isSubscribed(topicAfter, callbackAfter),
            "the subscription made after the broker restart to be added to the consolidator");
    check waitUntil(isolated function() returns boolean|error => publishedAndDelivered(topicAfter, idAfter, 0),
            "the content to be delivered to a subscription made after the broker restart");

    // The content is still delivered to the subscription made before the restart
    final int deliveredBefore = deliveriesOf(idBefore).length();
    check waitUntil(isolated function() returns boolean|error =>
            publishedAndDelivered(topicBefore, idBefore, deliveredBefore),
            "the content to be delivered to a subscription made before the broker restart");
}

// ========================================
// Helpers
// ========================================

# Publishes content to a topic, and checks whether a subscriber received more deliveries than it had before. The
# content is published on every check, as content published before the hub resumes delivering is not redelivered.
#
# + topic - The topic to publish to
# + id - The identifier of the test subscriber
# + deliveredBefore - The number of deliveries the subscriber received before
# + return - `true` if the subscriber received a new delivery, or an `error` if the content cannot be published
isolated function publishedAndDelivered(string topic, string id, int deliveredBefore) returns boolean|error {
    _ = check publish(topic, {"event": "after-broker-restart"});
    runtime:sleep(1);
    return deliveriesOf(id).length() > deliveredBefore;
}

# Leaves the consolidator running and the OpenTelemetry collector connected to the broker after its restart.
#
# + return - An `error` if the components do not reconnect to the broker in time
function recoverFromBrokerRestart() returns error? {
    check restoreConsolidator();
    decimal waited = 0;
    while !(check isTelemetryReceiverConnected()) {
        if waited >= RECONNECT_TIMEOUT {
            return error(string `Timed out after ${RECONNECT_TIMEOUT}s waiting for the OpenTelemetry collector to ` +
                    string `reconnect to the broker`);
        }
        runtime:sleep(2);
        waited += 2d;
    }
}
