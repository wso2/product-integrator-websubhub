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

import ballerina/log;

# Generates a group-name for a subscriber.
#
# + topic - The `topic` which subscriber needs to subscribe
# + callbackUrl - Subscriber callback URL
# + return - Generated group-name for subscriber
public isolated function generatedSubscriberId(string topic, string callbackUrl) returns string {
    return string `${topic}___${callbackUrl}`;
}

# Logs a fatal errors with proper details.
#
# + msg - Base error message  
# + error - Current error
# + keyValues - Additional key values to be logged
public isolated function logFatalError(string msg, error? 'error = (), *log:KeyValues keyValues) {
    keyValues["severity"] = "FATAL";
    log:printError(msg, 'error, keyValues = keyValues);
}

# Logs a recoverable errors with proper details.
#
# + msg - Base error message  
# + error - Current error
# + keyValues - Additional key values to be logged
public isolated function logRecoverableError(string msg, error? 'error = (), *log:KeyValues keyValues) {
    keyValues["severity"] = "RECOVERABLE";
    log:printError(msg, 'error, keyValues = keyValues);
}
