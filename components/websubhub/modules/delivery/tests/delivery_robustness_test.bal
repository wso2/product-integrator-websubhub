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

// Robustness tests for the delivery loop's per-message step, `deliverNextNotification`.
//
// The critical invariant: a `receive()` failure (e.g. an unreadable zero-length message that the
// broker adapter cannot deserialize) must be treated as RECOVERABLE — `deliverNextNotification`
// returns `()` so the polling loop continues. It must NOT return an error, because the loop's
// `check` would then propagate it to the `on fail` block and mark the whole subscription stale,
// halting the subscriber. These tests lock that behaviour into CI using mock consumers.

import ballerina/test;
import ballerina/websubhub;

import wso2/messagestore.api as storeapi;

// A consumer whose receive() always fails — mimics the xlibb/solace zero-length "values is null" error.
isolated client class ReceiveErrorConsumer {
    isolated remote function receive() returns storeapi:Message|error? {
        return error("Failed to receive message: Cannot read the array length because 'values' is null");
    }
    isolated remote function ack(storeapi:Message message) returns error? => ();
    isolated remote function nack(storeapi:Message message) returns error? => ();
    isolated remote function deadLetter(storeapi:Message message) returns error? => ();
    isolated remote function close(storeapi:ClosureIntent intent = storeapi:TEMPORARY) returns error? => ();
}

// A consumer that reports no message available (receive returns ()).
isolated client class NoMessageConsumer {
    isolated remote function receive() returns storeapi:Message|error? => ();
    isolated remote function ack(storeapi:Message message) returns error? => ();
    isolated remote function nack(storeapi:Message message) returns error? => ();
    isolated remote function deadLetter(storeapi:Message message) returns error? => ();
    isolated remote function close(storeapi:ClosureIntent intent = storeapi:TEMPORARY) returns error? => ();
}

// A consumer that returns one malformed-JSON message, then nothing; records whether deadLetter fired.
isolated client class DeserializeFailConsumer {
    private boolean delivered = false;
    private boolean deadLettered = false;

    isolated remote function receive() returns storeapi:Message|error? {
        lock {
            if self.delivered {
                return;
            }
            self.delivered = true;
        }
        map<string|string[]> metadata = {"x-hub-contentType": "application/json"};
        return {payload: "not valid json {{{".toBytes(), metadata};
    }
    isolated remote function ack(storeapi:Message message) returns error? => ();
    isolated remote function nack(storeapi:Message message) returns error? => ();
    isolated remote function deadLetter(storeapi:Message message) returns error? {
        lock {
            self.deadLettered = true;
        }
        return;
    }
    isolated remote function close(storeapi:ClosureIntent intent = storeapi:TEMPORARY) returns error? => ();
    isolated function wasDeadLettered() returns boolean {
        lock {
            return self.deadLettered;
        }
    }
}

const TOPIC = "test-topic";
const CALLBACK = "http://subscriber.example.com/callback";

@test:Config {}
function testDeliverNext_ReceiveError_IsRecoverable_NoHalt() returns error? {
    storeapi:Consumer consumer = new ReceiveErrorConsumer();
    websubhub:HubClient clientEp = test:mock(websubhub:HubClient); // never invoked on the receive-error path

    error? result = deliverNextNotification(consumer, clientEp, TOPIC, CALLBACK);

    // MUST be () (recoverable). An error here would propagate through the loop's `check` to the
    // on-fail block and mark the subscription stale — i.e. halt the subscriber on one bad message.
    test:assertTrue(result is (),
        "a receive() error must be recoverable (return ()) so the subscriber is not halted/marked stale");
}

@test:Config {}
function testDeliverNext_NoMessage_Continues() returns error? {
    storeapi:Consumer consumer = new NoMessageConsumer();
    websubhub:HubClient clientEp = test:mock(websubhub:HubClient);

    error? result = deliverNextNotification(consumer, clientEp, TOPIC, CALLBACK);

    test:assertTrue(result is (), "no message available must return () (continue polling)");
}

@test:Config {}
function testDeliverNext_DeserializeFailure_DeadLettersAndContinues() returns error? {
    DeserializeFailConsumer mock = new DeserializeFailConsumer();
    storeapi:Consumer consumer = mock;
    websubhub:HubClient clientEp = test:mock(websubhub:HubClient);

    error? result = deliverNextNotification(consumer, clientEp, TOPIC, CALLBACK);

    test:assertTrue(result is (), "a deserialization failure must be handled (DLQ) and return () to continue");
    test:assertTrue(mock.wasDeadLettered(), "a malformed message must be routed to the DLQ via deadLetter()");
}
