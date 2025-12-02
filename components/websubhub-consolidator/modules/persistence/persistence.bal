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

import wso2/messagestore as store;

public isolated function persistWebsubEventsSnapshot(common:SystemStateSnapshot systemStateSnapshot) returns error? {
    json data = systemStateSnapshot.toJson();
    byte[] payload = data.toJsonString().toBytes();
    check produceMessage(config:state.snapshot.topic, payload);
}

isolated function produceMessage(string topic, byte[] payload) returns error? {
    store:Message message = {payload};
    return (check conn:getMessageProducer(topic))->send(topic, message);
}
