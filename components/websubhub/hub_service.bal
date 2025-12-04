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

import websubhub.common;
import websubhub.config;
import websubhub.persistence as persist;
import websubhub.security;

import ballerina/http;
import ballerina/log;
import ballerina/websubhub;

http:Service healthCheckService = service object {
    resource function get .() returns http:Ok {
        return {
            body: {
                "status": "active"
            }
        };
    }
};

websubhub:Service hubService = @websubhub:ServiceConfig {
    webHookConfig: {
        retryConfig: config:delivery.'retry
    }
} service object {

    # Registers a `topic` in the hub.
    #
    # + message - Details related to the topic-registration
    # + headers - `http:Headers` of the original `http:Request`
    # + return - `websubhub:TopicRegistrationSuccess` if topic registration is successful, `websubhub:TopicRegistrationError`
    # if topic registration failed or `error` if there is any unexpected error
    isolated remote function onRegisterTopic(websubhub:TopicRegistration message, http:Headers headers)
                                returns websubhub:TopicRegistrationSuccess|websubhub:TopicRegistrationError|error {
        log:printDebug("Topic registration request received", topic = message.topic, securityEnabled = config:securityOn);
        if config:securityOn {
            log:printDebug("Performing authorization check for topic registration", topic = message.topic);
            check security:authorize(headers, ["register_topic"]);
            log:printDebug("Authorization successful for topic registration", topic = message.topic);
        }
        check self.registerTopic(message);
        log:printDebug("Topic registration completed successfully", topic = message.topic);
        return websubhub:TOPIC_REGISTRATION_SUCCESS;
    }

    isolated function registerTopic(websubhub:TopicRegistration message) returns websubhub:TopicRegistrationError? {
        log:printDebug("Starting topic registration process", topic = message.topic);
        boolean topicExist = isTopicExist(message.topic);
        log:printDebug("Checking topic existence in cache", topic = message.topic, exists = topicExist);
        if topicExist {
            log:printDebug("Topic registration failed - already exists", topic = message.topic);
            return error websubhub:TopicRegistrationError(
                    string `Topic [${message.topic}] is already registered with the Hub`, statusCode = http:STATUS_CONFLICT);
        }
        log:printDebug("Persisting topic registration to state store", topic = message.topic);
        error? persistingResult = persist:addRegsiteredTopic(message.cloneReadOnly());
        if persistingResult is error {
            common:logError("Error occurred while persisting the topic-registration", persistingResult);
        } else {
            log:printDebug("Topic registration persisted successfully", topic = message.topic);
        }
    }

    # Deregisters a `topic` in the hub.
    #
    # + message - Details related to the topic-deregistration
    # + headers - `http:Headers` of the original `http:Request`
    # + return - `websubhub:TopicDeregistrationSuccess` if topic deregistration is successful, `websubhub:TopicDeregistrationError`
    # if topic deregistration failed or `error` if there is any unexpected error
    isolated remote function onDeregisterTopic(websubhub:TopicDeregistration message, http:Headers headers)
                        returns websubhub:TopicDeregistrationSuccess|websubhub:TopicDeregistrationError|error {
        log:printDebug("Topic deregistration request received", topic = message.topic, securityEnabled = config:securityOn);
        if config:securityOn {
            log:printDebug("Performing authorization check for topic deregistration", topic = message.topic);
            check security:authorize(headers, ["deregister_topic"]);
            log:printDebug("Authorization successful for topic deregistration", topic = message.topic);
        }
        check self.deregisterTopic(message);
        log:printDebug("Topic deregistration completed successfully", topic = message.topic);
        return websubhub:TOPIC_DEREGISTRATION_SUCCESS;
    }

    isolated function deregisterTopic(websubhub:TopicRegistration message) returns websubhub:TopicDeregistrationError? {
        log:printDebug("Starting topic deregistration process", topic = message.topic);
        boolean topicExist = isTopicExist(message.topic);
        log:printDebug("Checking topic existence in cache for deregistration", topic = message.topic, exists = topicExist);
        if !topicExist {
            log:printDebug("Topic deregistration failed - not found", topic = message.topic);
            return error websubhub:TopicDeregistrationError(
                    string `Topic [${message.topic}] is not registered with the Hub`, statusCode = http:STATUS_NOT_FOUND);
        }
        log:printDebug("Persisting topic deregistration to state store", topic = message.topic);
        error? persistingResult = persist:removeRegsiteredTopic(message.cloneReadOnly());
        if persistingResult is error {
            common:logError("Error occurred while persisting the topic-deregistration", persistingResult);
        } else {
            log:printDebug("Topic deregistration persisted successfully", topic = message.topic);
        }
    }

    # Subscribes a `subscriber` to the hub.
    #
    # + message - Details of the subscription
    # + headers - `http:Headers` of the original `http:Request`
    # + return - `websubhub:SubscriptionAccepted` if subscription is accepted from the hub, `websubhub:BadSubscriptionError`
    # if subscription is denied from the hub or `error` if there is any unexpected error
    isolated remote function onSubscription(websubhub:Subscription message, http:Headers headers)
                returns websubhub:SubscriptionAccepted|websubhub:BadSubscriptionError|error {
        log:printDebug("Subscription request received", topic = message.hubTopic, callback = message.hubCallback, securityEnabled = config:securityOn);
        if config:securityOn {
            log:printDebug("Performing authorization check for subscription", topic = message.hubTopic, callback = message.hubCallback);
            check security:authorize(headers, ["subscribe"]);
            log:printDebug("Authorization successful for subscription", topic = message.hubTopic, callback = message.hubCallback);
        }
        log:printDebug("Subscription accepted", topic = message.hubTopic, callback = message.hubCallback);
        return websubhub:SUBSCRIPTION_ACCEPTED;
    }

    # Validates a incomming subscription request.
    #
    # + message - Details of the subscription
    # + return - `websubhub:SubscriptionDeniedError` if the subscription is denied by the hub or else `()`
    isolated remote function onSubscriptionValidation(websubhub:Subscription message)
                returns websubhub:SubscriptionDeniedError? {
        log:printDebug("Starting subscription validation", topic = message.hubTopic, callback = message.hubCallback);
        boolean topicExist = isTopicExist(message.hubTopic);
        log:printDebug("Topic exists check for subscription", topic = message.hubTopic, exists = topicExist);
        if !topicExist {
            log:printDebug("Subscription validation failed - topic not registered", topic = message.hubTopic, callback = message.hubCallback);
            return error websubhub:SubscriptionDeniedError(
                string `Topic [${message.hubTopic}] is not registered with the Hub`, statusCode = http:STATUS_NOT_ACCEPTABLE);
        } else {
            string subscriberId = common:generateSubscriberId(message.hubTopic, message.hubCallback);
            log:printDebug("Generated subscriber ID for validation", subscriberId = subscriberId, topic = message.hubTopic, callback = message.hubCallback);
            websubhub:VerifiedSubscription? subscription = getSubscription(subscriberId);
            if subscription is () {
                log:printDebug("No existing subscription found - validation passed", subscriberId = subscriberId);
                return;
            }
            boolean isStale = subscription.hasKey(STATUS) && subscription.get(STATUS) is STALE_STATE;
            log:printDebug("Existing subscription found", subscriberId = subscriberId, isStale = isStale);
            if isStale {
                log:printDebug("Existing subscription is stale - validation passed", subscriberId = subscriberId);
                return;
            }
            if isSubscriptionExist(subscriberId) {
                log:printDebug("Subscription validation failed - active subscription exists", subscriberId = subscriberId, topic = message.hubTopic, callback = message.hubCallback);
                return error websubhub:SubscriptionDeniedError(
                    string `Active subscription for Topic [${message.hubTopic}] and Callback [${message.hubCallback}] already exists`,
                    statusCode = http:STATUS_NOT_ACCEPTABLE
                );
            }
        }
        log:printDebug("Subscription validation completed successfully", topic = message.hubTopic, callback = message.hubCallback);
    }

    # Processes a verified subscription request.
    #
    # + message - Details of the subscription
    # + return - `error` if there is any unexpected error or else `()`
    isolated remote function onSubscriptionIntentVerified(websubhub:VerifiedSubscription message) returns error? {
        log:printDebug("Processing verified subscription intent", topic = message.hubTopic, callback = message.hubCallback);
        websubhub:VerifiedSubscription subscription = self.prepareSubscriptionToBePersisted(message);
        log:printDebug("Subscription prepared for persistence", topic = subscription.hubTopic, callback = subscription.hubCallback);
        error? persistingResult = persist:addSubscription(subscription);
        if persistingResult is error {
            common:logError("Error occurred while persisting the subscription", persistingResult);
        } else {
            log:printDebug("Subscription persisted successfully", topic = subscription.hubTopic, callback = subscription.hubCallback);
        }
    }

    isolated function prepareSubscriptionToBePersisted(websubhub:VerifiedSubscription message) returns websubhub:VerifiedSubscription {
        string subscriberId = common:generateSubscriberId(message.hubTopic, message.hubCallback);
        log:printDebug("Preparing subscription for persistence", subscriberId = subscriberId, topic = message.hubTopic, callback = message.hubCallback);
        websubhub:VerifiedSubscription? subscription = getSubscription(subscriberId);
        // if we have a stale subscription, remove the `status` flag from the subscription and persist it again
        if subscription is websubhub:Subscription {
            log:printDebug("Found existing stale subscription, updating status", subscriberId = subscriberId);
            websubhub:VerifiedSubscription updatedSubscription = {
                ...subscription
            };
            _ = updatedSubscription.removeIfHasKey(STATUS);
            log:printDebug("Stale subscription status removed", subscriberId = subscriberId);
            return updatedSubscription;
        }
        log:printDebug("Preparing new subscription", subscriberId = subscriberId);
        if !message.hasKey(CONSUMER_GROUP) {
            string consumerGroup = common:generateGroupName(message.hubTopic, message.hubCallback);
            message[CONSUMER_GROUP] = consumerGroup;
            log:printDebug("Generated consumer group for subscription", subscriberId = subscriberId, consumerGroup = consumerGroup);
        } else {
            log:printDebug("Using existing consumer group from subscription", subscriberId = subscriberId);
        }
        message[SERVER_ID] = config:server.id;
        log:printDebug("Assigned server ID to subscription", subscriberId = subscriberId, serverId = config:server.id);
        return message;
    }

    # Unsubscribes a `subscriber` from the hub.
    #
    # + message - Details of the unsubscription
    # + headers - `http:Headers` of the original `http:Request`
    # + return - `websubhub:UnsubscriptionAccepted` if unsubscription is accepted from the hub, `websubhub:BadUnsubscriptionError`
    # if unsubscription is denied from the hub or `error` if there is any unexpected error
    isolated remote function onUnsubscription(websubhub:Unsubscription message, http:Headers headers)
                returns websubhub:UnsubscriptionAccepted|websubhub:BadUnsubscriptionError|error {
        log:printDebug("Unsubscription request received", topic = message.hubTopic, callback = message.hubCallback, securityEnabled = config:securityOn);
        if config:securityOn {
            log:printDebug("Performing authorization check for unsubscription", topic = message.hubTopic, callback = message.hubCallback);
            check security:authorize(headers, ["subscribe"]);
            log:printDebug("Authorization successful for unsubscription", topic = message.hubTopic, callback = message.hubCallback);
        }
        log:printDebug("Unsubscription accepted", topic = message.hubTopic, callback = message.hubCallback);
        return websubhub:UNSUBSCRIPTION_ACCEPTED;
    }

    # Validates a incomming unsubscription request.
    #
    # + message - Details of the unsubscription
    # + return - `websubhub:UnsubscriptionDeniedError` if the unsubscription is denied by the hub or else `()`
    isolated remote function onUnsubscriptionValidation(websubhub:Unsubscription message)
                returns websubhub:UnsubscriptionDeniedError? {
        log:printDebug("Starting unsubscription validation", topic = message.hubTopic, callback = message.hubCallback);
        boolean topicExist = isTopicExist(message.hubTopic);
        log:printDebug("Topic exists check for unsubscription", topic = message.hubTopic, exists = topicExist);
        if !topicExist {
            log:printDebug("Unsubscription validation failed - topic not registered", topic = message.hubTopic, callback = message.hubCallback);
            return error websubhub:UnsubscriptionDeniedError(
                string `Topic [${message.hubTopic}] is not registered with the Hub`, statusCode = http:STATUS_NOT_ACCEPTABLE);
        } else {
            string subscriberId = common:generateSubscriberId(message.hubTopic, message.hubCallback);
            log:printDebug("Generated subscriber ID for unsubscription validation", subscriberId = subscriberId, topic = message.hubTopic, callback = message.hubCallback);
            boolean subscriptionExist = isSubscriptionExist(subscriberId);
            log:printDebug("Subscription existence check", subscriberId = subscriberId, exist = subscriptionExist);
            if !subscriptionExist {
                log:printDebug("Unsubscription validation failed - no valid subscription found", subscriberId = subscriberId, topic = message.hubTopic, callback = message.hubCallback);
                return error websubhub:UnsubscriptionDeniedError(
                    string `Could not find a valid subscription for Topic [${message.hubTopic}] and Callback [${message.hubCallback}]`,
                    statusCode = http:STATUS_NOT_ACCEPTABLE
                );
            }
        }
        log:printDebug("Unsubscription validation completed successfully", topic = message.hubTopic, callback = message.hubCallback);
    }

    # Processes a verified unsubscription request.
    #
    # + message - Details of the unsubscription
    isolated remote function onUnsubscriptionIntentVerified(websubhub:VerifiedUnsubscription message) {
        log:printDebug("Processing verified unsubscription intent", topic = message.hubTopic, callback = message.hubCallback);
        lock {
            log:printDebug("Persisting unsubscription to state store", topic = message.hubTopic, callback = message.hubCallback);
            error? persistingResult = persist:removeSubscription(message.cloneReadOnly());
            if persistingResult is error {
                common:logError("Error occurred while persisting the unsubscription", persistingResult);
            } else {
                log:printDebug("Unsubscription persisted successfully", topic = message.hubTopic, callback = message.hubCallback);
            }
        }
    }

    # Publishes content to the hub.
    #
    # + message - Details of the published content
    # + headers - `http:Headers` of the original `http:Request`
    # + return - `websubhub:Acknowledgement` if publish content is successful, `websubhub:UpdateMessageError`
    # if publish content failed or `error` if there is any unexpected error
    isolated remote function onUpdateMessage(websubhub:UpdateMessage message, http:Headers headers)
                returns websubhub:Acknowledgement|websubhub:UpdateMessageError|error {
        log:printDebug("Content update request received", topic = message.hubTopic, contentType = message.contentType, securityEnabled = config:securityOn);
        if config:securityOn {
            log:printDebug("Performing authorization check for content update", topic = message.hubTopic);
            check security:authorize(headers, ["update_content"]);
            log:printDebug("Authorization successful for content update", topic = message.hubTopic);
        }
        check self.updateMessage(message, headers);
        log:printDebug("Content update completed successfully", topic = message.hubTopic);
        return websubhub:ACKNOWLEDGEMENT;
    }

    isolated function updateMessage(websubhub:UpdateMessage message, http:Headers headers) returns websubhub:UpdateMessageError? {
        log:printDebug("Starting content update processing", topic = message.hubTopic, contentType = message.contentType);
        boolean topicAvailable = false;
        lock {
            topicAvailable = registeredTopicsCache.hasKey(message.hubTopic);
        }
        log:printDebug("Topic availability check for content update", topic = message.hubTopic, available = topicAvailable);
        if topicAvailable {
            map<string[]> messageHeaders = getHeadersMap(headers);
            log:printDebug("Extracted headers for content update", topic = message.hubTopic, headerCount = messageHeaders.length());
            log:printDebug("Publishing content to persistence layer", topic = message.hubTopic);
            error? errorResponse = persist:addUpdateMessage(message.hubTopic, message, messageHeaders);
            if errorResponse is websubhub:UpdateMessageError {
                log:printDebug("Content update failed with UpdateMessageError", topic = message.hubTopic, errorMsg = errorResponse.message());
                return errorResponse;
            } else if errorResponse is error {
                common:logError("Error occurred while publishing the content", errorResponse);
                return error websubhub:UpdateMessageError(
                    errorResponse.message(), statusCode = http:STATUS_INTERNAL_SERVER_ERROR);
            } else {
                log:printDebug("Content published successfully to persistence layer", topic = message.hubTopic);
            }
        } else {
            log:printDebug("Content update failed - topic not registered", topic = message.hubTopic);
            return error websubhub:UpdateMessageError(
                string `Topic [${message.hubTopic}] is not registered with the Hub`, statusCode = http:STATUS_NOT_FOUND);
        }
    }
};

isolated function getHeadersMap(http:Headers httpHeaders) returns map<string[]> {
    map<string[]> headers = {};
    string[] headerNames = httpHeaders.getHeaderNames();
    log:printDebug("Processing HTTP headers", headerCount = headerNames.length(), headerNames = headerNames);
    foreach string headerName in headerNames {
        var headerValues = httpHeaders.getHeaders(headerName);
        // safe to ingore the error as here we are retrieving only the available headers
        if headerValues is error {
            log:printDebug("Error retrieving header values", headerName = headerName, errorMsg = headerValues.message());
            continue;
        }
        headers[headerName] = headerValues;
        log:printDebug("Header processed", headerName = headerName, valueCount = headerValues.length());
    }
    log:printDebug("Headers processing completed", totalHeaders = headers.length());
    return headers;
}
