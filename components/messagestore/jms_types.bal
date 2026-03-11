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

import ballerinax/java.jms;

# Defines the JMS message store configurations
public type JmsMessageStore record {|
    # Configurations related to JMS message store connection    
    JmsConfig solace;
|};

public type JmsConfig record {|
    *jms:ConnectionConfiguration;
    # JMS consumer-specific configurations
    JmsConsumerConfig consumer;
|};

# Defines configurations for the JMS consumer.
public type JmsConsumerConfig record {|
    # The timeout to wait for one receive call to the JMS message store
    decimal receiveTimeout = 10;
    # The dead-letter topic to which unprocessable messages should be forwarded.
    # If not configured, dead-lettering is disabled for this consumer.
    string deadLetterTopic?;
|};
