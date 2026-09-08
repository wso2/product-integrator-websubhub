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

import websubhub.admin;
import websubhub.common;
import websubhub.config;
import websubhub.persistence as persist;
import websubhub.security;
import websubhub.state;

import ballerina/http;
import ballerina/log;
import ballerina/time;
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
        secureSocket: common:extractClientSecureSocketConfig(config:delivery.secureSocket),
        retryConfig: common:extractHttpRetryConfig(config:delivery.'retry)
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
        if config:securityOn {
            check security:authorize(headers, ["register_topic"]);
        }
        common:TopicRegistration topicRegistration = check buildTopicRegistration(message, headers);
        check self.registerTopic(topicRegistration);
        return websubhub:TOPIC_REGISTRATION_SUCCESS;
    }

    isolated function registerTopic(common:TopicRegistration message) returns websubhub:TopicRegistrationError? {
        lock {
            if state:isTopicAvailable(message.topic) {
                return error websubhub:TopicRegistrationError(
                    "Topic has already registered with the Hub", statusCode = http:STATUS_CONFLICT);
            }
        }
        do {
            log:printDebug("Persisting topic-registration event", topic = message.topic, 'type = "state-update", serverId = config:serverId);
            check admin:createTopic(message);
            check persist:addRegsiteredTopic(message);
        } on fail error topicRegErr {
            string errorMessage = string `Failed to register ${message.topic}: ${topicRegErr.message()}`;
            common:logRecoverableError(errorMessage, topicRegErr);
            if topicRegErr is websubhub:TopicRegistrationError {
                return topicRegErr;
            }
            return error websubhub:TopicRegistrationError(errorMessage, statusCode = http:STATUS_INTERNAL_SERVER_ERROR);
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
        if config:securityOn {
            check security:authorize(headers, ["deregister_topic"]);
        }
        check self.deregisterTopic(message);
        return websubhub:TOPIC_DEREGISTRATION_SUCCESS;
    }

    isolated function deregisterTopic(websubhub:TopicRegistration message) returns websubhub:TopicDeregistrationError? {
        lock {
            if !state:isTopicAvailable(message.topic) {
                return error websubhub:TopicDeregistrationError(
                    "Topic has not been registered in the Hub", statusCode = http:STATUS_NOT_FOUND);
            }
        }
        do {
            log:printDebug("Persisting topic-deregistration event", topic = message.topic, 'type = "state-update", serverId = config:serverId);
            check admin:deleteTopic(message);
            check persist:removeRegsiteredTopic(message);
        } on fail error topicDeregErr {
            string errorMessage = string `Failed to deregister ${message.topic}: ${topicDeregErr.message()}`;
            common:logRecoverableError(errorMessage, topicDeregErr);
            if topicDeregErr is websubhub:TopicDeregistrationError {
                return topicDeregErr;
            }
            return error websubhub:TopicDeregistrationError(errorMessage, statusCode = http:STATUS_INTERNAL_SERVER_ERROR);
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
        if config:securityOn {
            check security:authorize(headers, ["subscribe"]);
        }
        return websubhub:SUBSCRIPTION_ACCEPTED;
    }

    # Validates a incomming subscription request.
    #
    # + message - Details of the subscription
    # + return - `websubhub:SubscriptionDeniedError` if the subscription is denied by the hub or else `()`
    isolated remote function onSubscriptionValidation(websubhub:Subscription message)
                returns websubhub:SubscriptionDeniedError? {
        if !state:isTopicAvailableWithRetry(message.hubTopic) {
            return error websubhub:SubscriptionDeniedError(
                "Topic [" + message.hubTopic + "] is not registered with the Hub", statusCode = http:STATUS_NOT_ACCEPTABLE);
        } else {
            log:printDebug("Topic availability check passed for subscription",
                    topic = message.hubTopic, callback = message.hubCallback, 'type = "state-update", serverId = config:serverId);
            string subscriberId = common:generateSubscriberId(message.hubTopic, message.hubCallback);
            websubhub:VerifiedSubscription? subscription = state:getSubscription(subscriberId);
            if subscription is () {
                return;
            }
            if subscription.hasKey(common:SUBSCRIPTION_STATUS) && subscription.get(common:SUBSCRIPTION_STATUS) is SUBSCRIPTION_STALE_STATE {
                return;
            }
            log:printDebug("Subscription availability check failed for subscription",
                    topic = message.hubTopic, callback = message.hubCallback, subscriptionStatus = subscription[common:SUBSCRIPTION_STATUS] ?: "active",
                    'type = "state-update", serverId = config:serverId);
            if state:isSubscriptionAvailable(subscriberId) {
                return error websubhub:SubscriptionDeniedError(
                    "Subscriber has already registered with the Hub", statusCode = http:STATUS_NOT_ACCEPTABLE);
            }
        }
    }

    # Processes a verified subscription request.
    #
    # + message - Details of the subscription
    # + return - `error` if there is any unexpected error or else `()`
    isolated remote function onSubscriptionIntentVerified(websubhub:VerifiedSubscription message) returns error? {
        websubhub:VerifiedSubscription subscription = self.prepareSubscriptionToBePersisted(message);
        do {
            log:printDebug("Persisting subscription event",
                    topic = message.hubTopic, callback = message.hubCallback, 'type = "state-update", serverId = config:serverId);
            check admin:createSubscription(subscription);
            check persist:addSubscription(subscription);
        } on fail error subscriptionErr {
            string errorMessage = string
                `Failed to register subscription for topic ${message.hubTopic} and subscriber ${message.hubCallback}: ${subscriptionErr.message()}`;
            common:logRecoverableError(errorMessage, subscriptionErr);
            return error(errorMessage);
        }
    }

    isolated function prepareSubscriptionToBePersisted(websubhub:VerifiedSubscription message) returns websubhub:VerifiedSubscription {
        string subscriberId = common:generateSubscriberId(message.hubTopic, message.hubCallback);
        websubhub:VerifiedSubscription? subscription = state:getSubscription(subscriberId);
        // if we have a stale subscription, remove the `status` flag from the subscription and persist it again
        if subscription is websubhub:VerifiedSubscription {
            websubhub:VerifiedSubscription updatedSubscription = {
                ...subscription
            };
            _ = updatedSubscription.removeIfHasKey(common:SUBSCRIPTION_STATUS);
            return updatedSubscription;
        }
        message[common:SUBSCRIPTION_TIMESTAMP] = time:monotonicNow().toBalString();
        message[common:SUBSCRIPTION_SERVER_ID] = config:serverId;
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
        if config:securityOn {
            check security:authorize(headers, ["subscribe"]);
        }
        return websubhub:UNSUBSCRIPTION_ACCEPTED;
    }

    # Validates a incomming unsubscription request.
    #
    # + message - Details of the unsubscription
    # + return - `websubhub:UnsubscriptionDeniedError` if the unsubscription is denied by the hub or else `()`
    isolated remote function onUnsubscriptionValidation(websubhub:Unsubscription message)
                returns websubhub:UnsubscriptionDeniedError? {
        if !state:isTopicAvailableWithRetry(message.hubTopic) {
            return error websubhub:UnsubscriptionDeniedError(
                "Topic [" + message.hubTopic + "] is not registered with the Hub", statusCode = http:STATUS_NOT_ACCEPTABLE);
        } else {
            string subscriberId = common:generateSubscriberId(message.hubTopic, message.hubCallback);
            if !state:isSubscriptionAvailable(subscriberId) {
                return error websubhub:UnsubscriptionDeniedError("Could not find a valid subscriber for Topic ["
                                + message.hubTopic + "] and Callback [" + message.hubCallback + "]", statusCode = http:STATUS_NOT_ACCEPTABLE);
            }
        }
    }

    # Processes a verified unsubscription request.
    #
    # + message - Details of the unsubscription
    # + return - `error` if there is any unexpected error else `()`
    isolated remote function onUnsubscriptionIntentVerified(websubhub:VerifiedUnsubscription message) returns error? {
        string subscriberId = common:generateSubscriberId(message.hubTopic, message.hubCallback);
        websubhub:VerifiedSubscription? subscription = state:getSubscription(subscriberId);
        if subscription is () {
            return;
        }

        do {
            log:printDebug("Persisting unsubscription event",
                    topic = message.hubTopic, callback = message.hubCallback, 'type = "state-update", serverId = config:serverId);
            check admin:deleteSubscription(subscription);
            check persist:removeSubscription(message);
        } on fail error unsubscriptionErr {
            string errorMessage = string
                `Failed to deregister subscription for topic ${message.hubTopic} and subscriber ${message.hubCallback}: ${unsubscriptionErr.message()}`;
            common:logRecoverableError(errorMessage, unsubscriptionErr);
            return error(errorMessage);
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
        if config:securityOn {
            check security:authorize(headers, ["update_content"]);
        }
        check self.updateMessage(message, headers);
        return websubhub:ACKNOWLEDGEMENT;
    }

    isolated function updateMessage(websubhub:UpdateMessage msg, http:Headers headers) returns websubhub:UpdateMessageError? {
        common:TopicRegistration? topicRegistration = state:getTopic(msg.hubTopic);
        if topicRegistration is () {
            return error websubhub:UpdateMessageError(
                "Topic [" + msg.hubTopic + "] is not registered with the Hub", statusCode = http:STATUS_NOT_FOUND);
        }

        check validateContentType(msg, topicRegistration);

        string? messageId = getMessageId(headers);
        map<string[]> metadata = getMetadata(headers);
        error? errorResponse = persist:addUpdateMessage(msg.hubTopic, msg, metadata, messageId);
        if errorResponse is websubhub:UpdateMessageError {
            return errorResponse;
        } else if errorResponse is error {
            common:logRecoverableError("Error occurred while publishing the content ", errorResponse);
            return error websubhub:UpdateMessageError(
                errorResponse.message(), statusCode = http:STATUS_INTERNAL_SERVER_ERROR);
        }
    }
};

# Verifies that published content matches the content type declared for its topic.
#
# + msg - The published content-update message
# + topicRegistration - The registration of the topic being published to
# + return - A `websubhub:UpdateMessageError` if the content contradicts the topic's declaration and
# strict content-type validation is enabled
isolated function validateContentType(websubhub:UpdateMessage msg, common:TopicRegistration topicRegistration)
        returns websubhub:UpdateMessageError? {
    string declaredContentType = topicRegistration.contentType;

    if msg.msgType == websubhub:EVENT {
        if declaredContentType == common:DEFAULT_CONTENT_TYPE {
            return;
        }
        string eventErrorMessage = string `Topic [${msg.hubTopic}] delivers content as ` +
            string `[${declaredContentType}], which cannot represent a content-free event notification`;
        return error websubhub:UpdateMessageError(eventErrorMessage, statusCode = http:STATUS_UNSUPPORTED_MEDIA_TYPE);
    }

    if common:normalizeContentType(msg.contentType) == common:normalizeContentType(declaredContentType) {
        return;
    }

    string errorMessage = string `Content type [${msg.contentType}] does not match the content type ` +
        string `[${declaredContentType}] declared for topic [${msg.hubTopic}]`;
    if !config:server.strictContentTypeValidation {
        log:printWarn(errorMessage, topic = msg.hubTopic, serverId = config:serverId);
        return;
    }
    return error websubhub:UpdateMessageError(errorMessage, statusCode = http:STATUS_UNSUPPORTED_MEDIA_TYPE);
}

# Builds the hub's topic registration from the standard-library record and the registration request.
#
# + message - The topic registration parsed by the standard library
# + headers - `http:Headers` of the original registration request
# + return - The hub's topic registration, or a `websubhub:TopicRegistrationError` if the declared
# content type is not one the hub is able to deliver
isolated function buildTopicRegistration(websubhub:TopicRegistration message, http:Headers headers)
        returns common:TopicRegistration|websubhub:TopicRegistrationError {
    string|http:HeaderNotFoundError declaredContentType = headers.getHeader(common:TOPIC_CONTENT_TYPE_HEADER);
    if declaredContentType is http:HeaderNotFoundError {
        // The topic declared nothing, so it delivers as the record's default.
        return {topic: message.topic, hubMode: message.hubMode};
    }

    string contentType = declaredContentType.trim().toLowerAscii();
    if !common:isSupportedTopicContentType(contentType) {
        string supported = string:'join(", ", ...common:SUPPORTED_TOPIC_CONTENT_TYPES);
        string errorMessage = string `Content type [${contentType}] cannot be declared for a topic. ` +
            string `Supported content types are: ${supported}`;
        return error websubhub:TopicRegistrationError(errorMessage, statusCode = http:STATUS_BAD_REQUEST);
    }
    return {topic: message.topic, hubMode: message.hubMode, contentType: contentType};
}

isolated function getMessageId(http:Headers httpHeaders) returns string? {
    if !httpHeaders.hasHeader(common:MESSAGE_ID_HEADER) {
        return;
    }

    var msgId = httpHeaders.getHeader(common:MESSAGE_ID_HEADER);
    // safe to ingore the error as here we are retrieving only the available headers
    if msgId is error {
        return;
    }
    return msgId;
}

isolated function getMetadata(http:Headers httpHeaders) returns map<string[]> {
    map<string[]> headers = {};
    foreach string headerName in httpHeaders.getHeaderNames() {
        // Exclude credential-bearing and hop-by-hop headers, which describe the publisher's request
        // and must not be replayed to subscribers, along with the messageId header, which is dealt
        // with separately.
        if common:isDeniedMetadataHeader(headerName) {
            continue;
        }
        var headerValues = httpHeaders.getHeaders(headerName);
        // safe to ingore the error as here we are retrieving only the available headers
        if headerValues is error {
            continue;
        }
        headers[headerName] = headerValues;
    }
    return headers;
}
