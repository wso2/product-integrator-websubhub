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

import ballerina/http;
import ballerina/log;
import ballerina/websubhub;

import wso2/messagestore.api as storeapi;

isolated client class Dispatcher {

    isolated remote function notifyContentDistribution(storeapi:Message message) returns error? {
    }
}

isolated client class HttpRetryBasedDispatcher {
    *Dispatcher;

    private final websubhub:HubClient dispatcherClient;
    private final storeapi:Consumer consumer;
    private final string topic;
    private final string callback;
    private final common:HttpRetryConfig? & readonly 'retry;

    isolated function init(websubhub:VerifiedSubscription subscription, storeapi:Consumer consumer) returns error? {
        self.dispatcherClient = check new (subscription, {
            httpVersion: http:HTTP_2_0,
            secureSocket: common:extractClientSecureSocketConfig(config:delivery.secureSocket),
            retryConfig: common:extractHttpRetryConfig(config:delivery.'retry),
            timeout: config:delivery.timeout
        });
        self.consumer = consumer;
        self.topic = subscription.hubTopic;
        self.callback = subscription.hubCallback;
        var 'retry = config:delivery.'retry;
        self.'retry = 'retry is common:HttpRetryConfig ? 'retry : ();
    }

    isolated remote function notifyContentDistribution(storeapi:Message message) returns error? {
        websubhub:ContentDistributionMessage|error notification = constructContentDistMsg(message);
        if notification is error {
            log:printWarn("Error occurred while deserializing the message, hence pushing the message to DLQ", 'error = notification);
            check self.consumer->deadLetter(message);
            return;
        }

        error? result = check self.deliverWithRetryReset(notification);
        if result is error {
            check self.consumer->nack(message);
            check result;
        } else {
            common:logContentDelivery(self.topic, self.callback, message.id);
            check self.consumer->ack(message);
        }
    }

    isolated function deliverWithRetryReset(websubhub:ContentDistributionMessage notification) returns error? {
        var 'retry = self.'retry;
        if 'retry is () || !'retry.resetOnExhaust {
            _ = check self.dispatcherClient->notifyContentDistribution(notification);
            return;
        }

        while true {
            websubhub:ContentDistributionSuccess|websubhub:Error result = self.dispatcherClient->notifyContentDistribution(notification);
            if result is websubhub:ContentDistributionSuccess {
                return;
            }

            // Check whether the returned status code is a retryable status-code, if not return the error
            int statusCode = result.detail().statusCode;
            if 'retry.statusCodes.indexOf(statusCode) is () {
                return result;
            }
        }
    }
}
