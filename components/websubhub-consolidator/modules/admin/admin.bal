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

import websubhub.consolidator.config;

import ballerina/log;

import wso2/messagestore as store;

final store:Administrator administrator = check createAdministrator();

isolated function init() returns error? {
    // Create topic and subscription for state snapshot consumer
    var {topic, consumerId} = config:state.snapshot;
    error? result = administrator->createTopic(topic);
    if result is store:TopicExists {
        log:printWarn(string `Topic [${topic}] already exists in the message store`);
    }

    result = administrator->createSubscription(topic, consumerId);
    if result is store:SubscriptionExists {
        log:printWarn(string `Subscription for Topic [${topic}] and Subscriber [${consumerId}] exists`);
    } else if result is error {
        return result;
    }

    // Create topic and subscription for state events consumer
    {topic, consumerId} = config:state.events;
    result = administrator->createTopic(topic);
    if result is store:TopicExists {
        log:printWarn(string `Topic [${topic}] already exists in the message store`);
    }
    
    result = administrator->createSubscription(topic, consumerId);
    if result is store:SubscriptionExists {
        log:printWarn(string `Subscription for Topic [${topic}] and Subscriber [${consumerId}] exists`);
    }
    return result;
}

isolated function createAdministrator() returns store:Administrator|error {
    var {kafka, solace} = config:store;
    if solace is store:SolaceConfig {
        return store:createSolaceAdministrator(solace);
    }
    return new store:Administrator();
}
