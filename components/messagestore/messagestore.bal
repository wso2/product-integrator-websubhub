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

import messagestore.api;
import messagestore.jms;
import messagestore.kafka;
import messagestore.solace;

# Represents the message store configurations.
public type Config record {|
    # Kafka message store configurations
    kafka:Config kafka?;
    # Solace messaage store configurations
    solace:Config solace?;
    # JMS message store configurations
    jms:Config jms?;
|};

# Initialize a producer for a specific message store.
#
# + clientId - The unique client Id or name 
# + store - The message store configurations
# + return - A `store:Producer` for a specific message store, or else return an `error` if the operation fails
public isolated function createProducer(string clientId, Config store) returns api:Producer|error {
    var {kafka, solace, jms} = store;
    if kafka is kafka:Config {
        return new kafka:Producer(clientId, kafka);
    }
    if solace is solace:Config {
        return new solace:Producer(clientId, solace);
    }
    if jms is jms:Config {
        return new jms:Producer(clientId, jms);
    }
    return error("Error occurred while reading the message store configurations when creating the store producer");
}

# Initialize a consumer for a specific message store.
#
# + topic - The topic from which the consumer should received events for
# + defaultConsumerId - The default consumer Id which is associated with the user. This configuration will have different semantics for different message stores
# + store - The message store configurations
# + systemConsumer - Flag to indicate whether this is a system consumer
# + meta - The meta data required to resolve the consumer configurations
# + return - An `api:ConsumerResult` tuple of the consumer and its metadata, or an `error` if the operation fails
public isolated function createConsumer(string topic, string defaultConsumerId, Config store, boolean systemConsumer = false, record {} meta = {}) returns api:ConsumerResult|error {
    var {kafka, solace, jms} = store;
    if kafka is kafka:Config {
        return kafka:createConsumer(defaultConsumerId, topic, kafka, systemConsumer, meta);
    }
    if solace is solace:Config {
        return solace:createConsumer(defaultConsumerId, solace, systemConsumer, meta);
    }
    if jms is jms:Config {
        return jms:createConsumer(topic, defaultConsumerId, jms, systemConsumer, meta);
    }
    return error("Error occurred while reading the message store configurations when creating the store consumer");
}

# Initialize a administrator for a specific message store.
#
# + store - The message store configurations
# + return - A `store:Administrator` for a message store, or else return an `error` if the operation fails
public isolated function createAdministrator(Config store) returns api:Administrator|error {
    var {kafka, solace, jms} = store;
    if solace is solace:Config {
        return new solace:Administrator(solace);
    }
    return new api:Administrator();
}

# Validates the provided message store configuration.
#
# + store - The message store configuration to be validated
# + return - An `error` if validation fails; otherwise `()` on success
public isolated function validateConfig(Config store) returns error? {
    int configured = 0;
    configured += store.kafka is kafka:Config ? 1 : 0;
    configured += store.solace is solace:Config ? 1 : 0;
    configured += store.jms is jms:Config ? 1 : 0;
    if configured != 1 {
        return error("Exactly one message store backend must be configured");
    }
}
