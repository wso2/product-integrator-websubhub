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
import ballerina/lang.runtime;
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
    private final storeapi:ConsumerMetadata & readonly consumerMetadata;

    isolated function init(websubhub:VerifiedSubscription subscription, storeapi:Consumer consumer, readonly & common:HttpRetryConfig? retryConfig, storeapi:ConsumerMetadata consumerMetadata) returns error? {
        self.dispatcherClient = check new (subscription, {
            httpVersion: http:HTTP_2_0,
            secureSocket: common:extractClientSecureSocketConfig(config:delivery.secureSocket),
            retryConfig: common:extractHttpRetryConfig(retryConfig),
            timeout: config:delivery.timeout
        });
        self.consumer = consumer;
        self.topic = subscription.hubTopic;
        self.callback = subscription.hubCallback;
        self.'retry = retryConfig;
        self.consumerMetadata = consumerMetadata.cloneReadOnly();
    }

    isolated remote function notifyContentDistribution(storeapi:Message message) returns error? {
        websubhub:ContentDistributionMessage|error notification = constructContentDistMsg(message);
        if notification is error {
            common:logContentDeliveryFailure("Error occurred while deserializing the message, moving message to dead-letter queue",
                self.topic, self.callback, message.id, self.consumerMetadata, err = notification);
            check self.consumer->deadLetter(message);
            return;
        }

        error? result = self.deliverWithRetryReset(notification);
        if result is error {
            check self.consumer->nack(message);
            return error(result.message(), result, topic = self.topic, callback = self.callback, 
                messageId = message.id ?: "[No Message Id]", consumerMetadata = self.consumerMetadata);
        }
        common:logContentDelivery(self.topic, self.callback, message.id, self.consumerMetadata);
        check self.consumer->ack(message);
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

isolated client class MessageBrokerRetryBasedDispatcher {
    *Dispatcher;

    private final websubhub:HubClient dispatcherClient;
    private final storeapi:Consumer consumer;
    private final string topic;
    private final string callback;
    private final common:MessageStoreRetryConfig & readonly 'retry;
    private final storeapi:ConsumerMetadata & readonly consumerMetadata;

    isolated function init(websubhub:VerifiedSubscription subscription, storeapi:Consumer consumer, readonly & common:MessageStoreRetryConfig retryConfig, storeapi:ConsumerMetadata consumerMetadata) returns error? {
        self.dispatcherClient = check new (subscription, {
            httpVersion: http:HTTP_2_0,
            secureSocket: common:extractClientSecureSocketConfig(config:delivery.secureSocket),
            timeout: config:delivery.timeout
        });
        self.consumer = consumer;
        self.topic = subscription.hubTopic;
        self.callback = subscription.hubCallback;
        self.'retry = retryConfig;
        self.consumerMetadata = consumerMetadata.cloneReadOnly();
    }

    isolated remote function notifyContentDistribution(storeapi:Message message) returns error? {
        websubhub:ContentDistributionMessage|error notification = constructContentDistMsg(message);
        if notification is error {
            common:logContentDeliveryFailure("Error occurred while deserializing the message, moving message to dead-letter queue",
                self.topic, self.callback, message.id, self.consumerMetadata, err = notification);
            check self.consumer->deadLetter(message);
            return;
        }

        websubhub:ContentDistributionSuccess|websubhub:Error result = self.dispatcherClient->notifyContentDistribution(notification);
        if result is websubhub:ContentDistributionSuccess {
            common:logContentDelivery(self.topic, self.callback, message.id, self.consumerMetadata);
            check self.consumer->ack(message);
            return;
        }

        int statusCode = result.detail().statusCode;

        // The WebSub HubClient can surface a 2xx response (e.g. 202 Accepted) as a websubhub:Error.
        // That is still a successful delivery, so acknowledge it rather than classifying it as a
        // retry/fail outcome (which would wrongly mark the subscription stale).
        if statusCode >= 200 && statusCode < 300 {
            common:logContentDelivery(self.topic, self.callback, message.id);
            check self.consumer->ack(message);
            return;
        }

        common:RetryAction action = self.resolveRetryAction(statusCode);
        common:logContentDeliveryFailure("Received error response for content-delivery from the subscriber",
                self.topic, self.callback, message.id, self.consumerMetadata, err = result);

        if action === "redeliver" {
            // Sleep BEFORE nacking. The broker redelivers immediately on nack, so the delay must be
            // applied first; otherwise (with more than one async worker) another worker picks up the
            // redelivery instantly and the configured backoff is lost.
            runtime:sleep(self.'retry.delay);
            check self.consumer->nack(message);
            return;
        }

        if action === "deadLetter" {
            check self.consumer->deadLetter(message);
            return;
        }

        if action === "fail" {
            return error(result.message(), result, topic = self.topic, callback = self.callback, 
                messageId = message.id ?: "[No Message Id]", consumerMetadata = self.consumerMetadata);
        }
    }

    isolated function resolveRetryAction(int responseStatusCode) returns common:RetryAction {
        int[]? redeliver = self.'retry.redeliver;
        if redeliver !is () && redeliver.indexOf(responseStatusCode) is int {
            return "redeliver";
        }
        int[]? deadLetter = self.'retry.deadLetter;
        if deadLetter !is () && deadLetter.indexOf(responseStatusCode) is int {
            return "deadLetter";
        }
        if responseStatusCode >= 400 && responseStatusCode < 600 {
            return self.'retry.defaultAction;
        }
        return self.'retry.networkFailureAction;
    }
}
