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
import ballerina/log;
import ballerina/os;

# Generates a unique Id for a subscriber.
#
# + topic - The `topic` which subscriber needs to subscribe
# + callbackUrl - Subscriber callback URL
# + return - Generated subscriber Id for the subscriber
public isolated function generateSubscriberId(string topic, string callbackUrl) returns string {
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

# Extracts `http:RetryConfig` from the provided `RetryConfig`.
#
# + config - Optional retry configuration used to construct the `http:RetryConfig`
# + return - The constructed `http:RetryConfig` if a configuration is provided,
# otherwise `()`
public isolated function extractHttpRetryConfig(RetryConfig? config) returns http:RetryConfig? {
    if config is RetryConfig {
        var {resetOnExhaust, ...httpRetryConfig} = config;
        return httpRetryConfig;
    }
    return;
}

public isolated function extractListenerSecureSocketConfig(http:ListenerSecureSocket? config) returns http:ListenerSecureSocket? {
    string keystore = os:getEnv("WEBSUBHUB_KEYSTORE_PATH");
    string keystorePassword = os:getEnv("WEBSUBHUB_KEYSTORE_PASSWORD");
    if (keystore == "" && keystorePassword != "") || (keystore != "" && keystorePassword == "") {
        log:printWarn("Ignoring keystore env override: both WEBSUBHUB_KEYSTORE_PATH and WEBSUBHUB_KEYSTORE_PASSWORD must be set");
    }
    
    if config is http:ListenerSecureSocket {
        var {'key, ...conf} = config;
        if keystore != "" && keystorePassword != "" {
            return {
                'key: {
                    path: keystore,
                    password: keystorePassword
                },
                ...conf
            };
        }
        return config;
    }
    if keystore != "" && keystorePassword != "" {
        return {
            'key: {
                path: keystore,
                password: keystorePassword
            }
        };
    }
    return;
}

public isolated function extractClientSecureSocketConfig(http:ClientSecureSocket? config) returns http:ClientSecureSocket? {
    string truststore = os:getEnv("WEBSUBHUB_TRUSTSTORE_PATH");
    string truststorePassword = os:getEnv("WEBSUBHUB_TRUSTSTORE_PASSWORD");
    if (truststore == "" && truststorePassword != "") || (truststore != "" && truststorePassword == "") {
        log:printWarn("Ignoring truststore env override: both WEBSUBHUB_TRUSTSTORE_PATH and WEBSUBHUB_TRUSTSTORE_PASSWORD must be set");
    }

    if config is http:ClientSecureSocket {
        var {cert, ...conf} = config;
        if truststore != "" && truststorePassword != "" {
            return {
                cert: {
                    path: truststore,
                    password: truststorePassword
                },
                ...conf
            };
        }
        return config;
    }
    if truststore != "" && truststorePassword != "" {
        return {
            cert: {
                path: truststore,
                password: truststorePassword
            }
        };
    }
    return;
}
