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
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

// Integration tests for the BROKER_RETRY delivery mode end-to-end against a live
// Solace broker.  All tests are disabled by default (enable: false) because they
// require the full infrastructure stack described in CLAUDE.md:
//
//   - Solace broker on tcp://localhost:55554 (SEMP on http://localhost:8085)
//   - Hub running on https://localhost:9000
//   - Consolidator running on http://localhost:10001
//   - Mock subscriber running on http://localhost:8090
//
// To run a specific scenario locally, flip `enable: true` on that test and follow
// the setup steps from CLAUDE.md §12 "Build & Run Quick Reference".
//
// Queue assumptions:
//   - `deliveryCountEnabled = true` on the subscriber queue
//   - DMQ queue linked to the subscriber queue (created at subscription time by admin.bal)
//   - `dmqEligible = true` on published messages (set in producer.bal)
//
// Verification commands are embedded in each test as comments so the scenario can
// be confirmed manually even when the test body is a stub.

import ballerina/http;
import ballerina/test;

// ---------------------------------------------------------------------------
// Shared HTTP client for hub interaction during integration tests
// ---------------------------------------------------------------------------

final http:Client hubClient = check new ("https://localhost:9000",
        secureSocket = {cert: {path: "resources/wso2websubhub.jks", password: "password"}});

// ---------------------------------------------------------------------------
// Scenario 1 — HAPPY PATH
// Publisher POST → subscriber returns 200 → message ACKed and removed from queue
// ---------------------------------------------------------------------------

@test:Config {enable: false}
function testIntegration_HappyPath() returns error? {
    // Setup: ensure mock subscriber returns 200
    //   curl -X POST "http://localhost:8090/control?code=200"
    //
    // Action: publish a message
    //   curl -sk -X POST https://localhost:9000/hub \
    //     -H "Content-Type: application/x-www-form-urlencoded" \
    //     -d "hub.mode=publish&hub.topic=test-topic"
    //
    // Verify: main queue spooledMsgCount == 0, DMQ spooledMsgCount unchanged
    //   curl -s -u admin:admin \
    //     "http://localhost:8085/SEMP/v2/monitor/msgVpns/default/queues/consumer-99889" \
    //     | python3 -c "import sys,json; d=json.load(sys.stdin)['data']; print('queue:', d['spooledMsgCount'])"

    // TODO: implement using hubClient and SEMP API assertions
}

// ---------------------------------------------------------------------------
// Scenario 2 — NON-RECOVERABLE FAILURE → IMMEDIATE DLQ
// Publisher POST → subscriber returns 404 → message routes to DMQ immediately
// Subscription must remain active (not stale)
// ---------------------------------------------------------------------------

@test:Config {enable: false}
function testIntegration_NonRecoverable_ImmediateDLQ() returns error? {
    // Setup: mock subscriber returns 404
    //   curl -X POST "http://localhost:8090/control?code=404"
    //
    // Action: publish
    //
    // Verify:
    //   - main queue: spooledMsgCount == 0
    //   - DMQ queue: spooledMsgCount == previous + 1
    //   - subscribersCache: subscription entry still present with no "stale" status
    //   - Hub logs: "Non-recoverable delivery failure — routing message to DMQ" WARN line

    // TODO: implement
}

// ---------------------------------------------------------------------------
// Scenario 3 — RECOVERABLE FAILURE → BROKER RETRY → EVENTUAL SUCCESS
// Publisher POST → subscriber returns 500 for first N attempts → 200 on final attempt
// Message must be ACKed; DMQ must remain empty; deliveryCount must increment
// ---------------------------------------------------------------------------

@test:Config {enable: false}
function testIntegration_Recoverable_EventualSuccess() returns error? {
    // Setup: mock subscriber returns 500 for first 2 calls, then 200
    //   curl -X POST "http://localhost:8090/control?code=500"   (set to 500)
    //   # after observing 2 NACK WARN log lines:
    //   curl -X POST "http://localhost:8090/control?code=200"   (flip to 200)
    //
    // Action: publish (with queue maxRedelivery >= 2)
    //
    // Verify:
    //   - main queue: spooledMsgCount == 0 (message ACKed)
    //   - DMQ queue: spooledMsgCount unchanged
    //   - Hub logs: attempt=1 WARN, attempt=2 WARN, then attempt=3 "Message delivered" DEBUG

    // TODO: implement
}

// ---------------------------------------------------------------------------
// Scenario 4 — RECOVERABLE FAILURE → RETRY EXHAUSTION → DMQ
// Publisher POST → subscriber always returns 500 → maxRedeliveryCount exhausted
// Message must route to DMQ; subscription must NOT be marked stale
// ---------------------------------------------------------------------------

@test:Config {enable: false}
function testIntegration_Recoverable_ExhaustToDMQ() returns error? {
    // Setup: mock subscriber always returns 500
    //   curl -X POST "http://localhost:8090/control?code=500"
    //
    // Queue setting: redeliver.maxCount = 2  (so 3 total attempts: 1 initial + 2 redeliveries)
    //
    // Verify after ~(maxRedelivery+1) * interval seconds:
    //   - main queue: spooledMsgCount == 0
    //   - DMQ queue:  spooledMsgCount == previous + 1
    //     (Solace SEMP: maxRedeliveryExceededToDmqMsgCount should increment)
    //   - Hub logs: attempt=1, attempt=2, attempt=3 WARN lines, then NO stale-subscription event
    //   - subscribersCache: subscription still active (no "stale" status field)
    //
    // KEY REGRESSION: in WSH_RETRY mode the same failure sequence marks the subscription stale.
    //                  BROKER_RETRY must NOT do this.

    // TODO: implement
}

// ---------------------------------------------------------------------------
// Scenario 5 — SUBSCRIPTION STAYS ACTIVE (KEY REGRESSION TEST)
// Trigger any delivery failure in BROKER_RETRY mode.
// subscribersCache must still contain the subscription with no stale status.
// Contrast: same failure in WSH_RETRY mode marks the subscription stale.
// ---------------------------------------------------------------------------

@test:Config {enable: false}
function testIntegration_SubscriptionStaysActive_AfterDeliveryFailure() returns error? {
    // Setup: mock subscriber returns 500
    //
    // Action: publish one message; wait for NACK WARN log
    //
    // Verify via hub admin API or log inspection:
    //   - GET https://localhost:9000/hub/subscriptions  (or equivalent admin endpoint)
    //     Subscription entry must exist with no "status":"stale" field
    //   - Hub logs must NOT contain "addStaleSubscription" in BROKER_RETRY mode
    //
    // Compare: switch to WSH_RETRY mode (Config.toml deliveryMode=WSH_RETRY),
    //          repeat the same failure, and verify stale IS marked.

    // TODO: implement
}
