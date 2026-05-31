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

// mock_types.bal — shared test infrastructure for deliver_and_acknowledge_test.bal
//
// Consumer mock strategy
// ----------------------
// test:mock(storeapi:Consumer) requires that the backing object (if provided) exposes
// exactly the interface of storeapi:Consumer — no extra fields.  Instead of a custom
// backing class, we use test:prepare().when().thenReturn() to stub each remote method.
//
// Three helper functions each configure a mock consumer that accepts exactly ONE of the
// three ACK operations.  Any call to an unexpected operation returns a descriptive error,
// which propagates out of deliverAndAcknowledge() and causes test:assertEquals(result, ())
// to fail — making the wrong-method assertion implicit.

import ballerina/test;
import ballerina/websubhub;

import wso2/messagestore.api as storeapi;

// consumerExpectingAck stubs ack→() and nack/deadLetter→error.
// Use for success-path and Concern A tests.
public function consumerExpectingAck() returns storeapi:Consumer {
    storeapi:Consumer mc = test:mock(storeapi:Consumer);
    test:prepare(mc).when("ack").thenReturn(());
    test:prepare(mc).when("nack").thenReturn(error("unexpected nack — expected ack"));
    test:prepare(mc).when("deadLetter").thenReturn(error("unexpected deadLetter — expected ack"));
    return mc;
}

// consumerExpectingNack stubs nack→() and ack/deadLetter→error.
// Use for recoverable-failure tests (500, 502, timeout, network error).
public function consumerExpectingNack() returns storeapi:Consumer {
    storeapi:Consumer mc = test:mock(storeapi:Consumer);
    test:prepare(mc).when("ack").thenReturn(error("unexpected ack — expected nack"));
    test:prepare(mc).when("nack").thenReturn(());
    test:prepare(mc).when("deadLetter").thenReturn(error("unexpected deadLetter — expected nack"));
    return mc;
}

// consumerExpectingDeadLetter stubs deadLetter→() and ack/nack→error.
// Use for non-recoverable-failure tests (400, 401, 403, 404, 410).
public function consumerExpectingDeadLetter() returns storeapi:Consumer {
    storeapi:Consumer mc = test:mock(storeapi:Consumer);
    test:prepare(mc).when("ack").thenReturn(error("unexpected ack — expected deadLetter"));
    test:prepare(mc).when("nack").thenReturn(error("unexpected nack — expected deadLetter"));
    test:prepare(mc).when("deadLetter").thenReturn(());
    return mc;
}

// stubHubClient sets the return value of notifyContentDistribution on a mock HubClient.
public function stubHubClient(
        websubhub:HubClient mockClient,
        websubhub:ContentDistributionSuccess|websubhub:Error returnValue) {
    test:prepare(mockClient).when("notifyContentDistribution").thenReturn(returnValue);
}
