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

# Represents a message published to a message store.
public type Message record {|
    # The message payload
    byte[] payload;
    # The metadata associated with the message (e.g., Kafka message headers or JMS message properties)
    map<string|string[]> metadata?;
|};

# Represents a producer client that can publish messages to the message store.
public isolated client class Producer {

    # Sends a message to the specified topic.
    #
    # + topic - The destination topic to which the message should be published
    # + message - The message to be sent
    # + return - An `error` if sending fails, otherwise `()`.
    isolated remote function send(string topic, Message message) returns error? {
        return error("Calling an abstract API");
    }

    # Closes the underlying broker connection.
    #
    # + return - An `error` if closing the connection fails, otherwise `()`.
    isolated remote function close() returns error? {
        return error("Calling an abstract API");
    }
}

# Represents a consumer client that receives messages from the message store.
public isolated client class Consumer {

    # Receives a message from the broker.
    #
    # + return - The received `store:Message` on success, () if no message is available, or an error if the operation fails
    isolated remote function receive() returns Message|error? {
        return error("Calling an abstract API");
    }

    # Acknowledges successful processing of a message.
    #
    # + message - The message to acknowledge.
    # + return - An `error?` value if acknowledgement fails, otherwise `()`.
    isolated remote function ack(Message message) returns error? {
        return error("Calling an abstract API");
    }

    # Negatively acknowledges a message.
    #
    # + message - The message to negatively acknowledge.
    # + return - An `error?` value if the nack operation fails, otherwise `()`.
    isolated remote function nack(Message message) returns error? {
        return error("Calling an abstract API");
    }

    # Closes the underlying consumer and the associated broker connection.
    #
    # + return - An `error` if closing the consumer fails, otherwise `()`.
    isolated remote function close() returns error? {
        return error("Calling an abstract API");
    }
}

# Error indicating that the topic already exists in the message store.
public type TopicExists distinct error;

# Error indicating that the topic does not exist in the message store.
public type TopicNotFound distinct error;

# Error indicating that the subscription already exists for the given topic and subscriber ID.
public type SubscriptionExists distinct error;

# Error indicating that the specified subscription does not exist.
public type SubscriptionNotFound distinct error;

# Represents an administrative client used to manage topics and subscriptions in the underlying message store.
public isolated client class Administrator {

    # Creates a new topic in the message store.
    #
    # + topic - Name of the topic to be created
    # + return - `TopicExists` if the topic already exists, `error?` for other errors,
    # or `()` on success
    isolated remote function createTopic(string topic) returns TopicExists|error? {
        return;
    }

    # Deletes an existing topic from the message store.
    #
    # + topic - Name of the topic to be deleted
    # + return - `TopicNotFound` if the topic does not exist, `error?` for other errors,
    # or `()` on success
    function deleteTopic(string topic) returns TopicNotFound|error? {
        return;
    }

    # Creates a new subscription for a given topic and subscriber ID.
    #
    # + topic - The topic to subscribe to
    # + subscriberId - Unique identifier of the subscriber
    # + return - `SubscriptionExists` if the subscription already exists, `error?` for other
    # errors, or `()` on success
    function createSubscription(string topic, string subscriberId) returns SubscriptionExists|error? {
        return;
    }

    # Deletes an existing subscription for a given topic and subscriber ID.
    #
    # + topic - The topic associated with the subscription
    # + subscriberId - Unique identifier of the subscriber
    # + return - `SubscriptionNotFound` if the subscription does not exist, `error?` for
    # other errors, or `()` on success
    function deleteSubscription(string topic, string subscriberId) returns SubscriptionNotFound|error? {
        return;
    }

    # Closes the administrative client and releases any associated resources.
    #
    # + return - `error?` if closing the client fails, or `()` on success
    function close() returns error? {
        return;
    }
}
