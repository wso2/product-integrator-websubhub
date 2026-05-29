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

import websubhub.common;
import websubhub.config;

import ballerina/websubhub;

import wso2/messagestore.api as storeapi;

isolated function validateRetryConfig() returns error? {
    var retryConfig = config:delivery.'retry;
    if retryConfig is () {
        return;
    }

    // Detect HTTP retry usage
    boolean hasHttpRetry =
        retryConfig.count != 0 ||
        retryConfig.interval != 0.0d ||
        retryConfig.backOffFactor != 0.0 ||
        retryConfig.maxWaitInterval != 0.0d ||
        retryConfig.statusCodes.length() > 0 ||
        retryConfig.resetOnExhaust;

    // Detect message-store retry usage
    boolean hasMessageStoreRetry =
        retryConfig.delay != 30.0d ||
        retryConfig.redeliver is int[] ||
        retryConfig.deadLetter is int[] ||
        retryConfig.defaultAction != "fail" ||
        retryConfig.networkFailureAction != "fail";

    if hasHttpRetry && hasMessageStoreRetry {
        return error("invalid retry configuration: HTTP retry configurations and message-store retry configurations cannot be used together");
    }
}

isolated function getRetryConfig() returns common:HttpRetryConfig|common:MessageStoreRetryConfig? {
    var retryConfig = config:delivery.'retry;
    if retryConfig is () {
        return;
    }

    // Detect HTTP retry usage
    boolean hasHttpRetry =
        retryConfig.count != 0 ||
        retryConfig.interval != 0.0d ||
        retryConfig.backOffFactor != 0.0 ||
        retryConfig.maxWaitInterval != 0.0d ||
        retryConfig.statusCodes.length() > 0 ||
        retryConfig.resetOnExhaust;
    if hasHttpRetry {
        return {
            count: retryConfig.count,
            interval: retryConfig.interval,
            backOffFactor: retryConfig.backOffFactor,
            maxWaitInterval: retryConfig.maxWaitInterval,
            statusCodes: retryConfig.statusCodes,
            resetOnExhaust: retryConfig.resetOnExhaust
        };
    }

    // Detect message-store retry usage
    boolean hasMessageStoreRetry =
        retryConfig.delay != 30.0d ||
        retryConfig.redeliver is int[] ||
        retryConfig.deadLetter is int[] ||
        retryConfig.defaultAction != "fail" ||
        retryConfig.networkFailureAction != "fail";
    if hasMessageStoreRetry {
        common:MessageStoreRetryConfig messageStoreRetry = {
            delay: retryConfig.delay,
            defaultAction: retryConfig.defaultAction,
            networkFailureAction: retryConfig.networkFailureAction
        };

        if retryConfig.redeliver is int[] {
            messageStoreRetry.redeliver = retryConfig.redeliver;
        }

        if retryConfig.deadLetter is int[] {
            messageStoreRetry.deadLetter = retryConfig.deadLetter;
        }
        return messageStoreRetry;
    }

    return;
}

isolated function createDispatcher(websubhub:VerifiedSubscription subscription, storeapi:Consumer consumer) returns Dispatcher|error {
    common:HttpRetryConfig|common:MessageStoreRetryConfig? config = getRetryConfig();
    if config is common:MessageStoreRetryConfig {
        return new MessageBrokerRetryBasedDispatcher(subscription, consumer, config.cloneReadOnly());
    }
    return new HttpRetryBasedDispatcher(subscription, consumer, config.cloneReadOnly());
}
