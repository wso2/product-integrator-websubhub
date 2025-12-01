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

import ballerina/http;
import ballerina/websubhub;

# Represents a snapshot of the WebSubHub's state, containing all topics and subscriptions.
public type SystemStateSnapshot record {|
    # An array of current topic registrations in the hub
    websubhub:TopicRegistration[] topics;
    # An array of all verified subscriptions in the hub
    websubhub:VerifiedSubscription[] subscriptions;
|};

# Defines the configuration for the WebSubHub consolidator server endpoint.
public type ServerConfig record {|
    # The port on which the WebSubHub consolidator service will start
    int port;
    # SSL/TLS configurations for the service endpoint
    http:ListenerSecureSocket secureSocket?;
|};

# Defines configurations for publishing and maintaining the server's state.
public type ServerStateConfig record {|
    # Configurations for the message store topic where the state snapshot is published
    MessageStoreTopic snapshot;
    # Configurations for the message store topic where state update events are published
    MessageStoreTopic events;
|};

# Defines the configurations for a message store topic.
public type MessageStoreTopic record {|
    # The name of the message store topic
    string topic;
    # The consumer group Id to be used when consuming from the topic
    string consumerId;
|};
