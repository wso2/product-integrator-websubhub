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

import websubhub.config;

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;
// import ballerina/os;
import ballerina/websubhub;

public function main() returns error? {
    // Initialize the Hub
    check initializeHubState();

    // int hubPort = check getHubPort();
    // Start the HealthCheck Service
    // http:Listener httpListener = check new (config:server.port,
    //     secureSocket = config:server.secureSocket
    // );

    http:Listener httpListener = check new(config:server.port);
    runtime:registerListener(httpListener);
    check httpListener.attach(healthCheckService, "/health");

    // Start the Hub
    websubhub:Listener hubListener = check new (httpListener);
    runtime:registerListener(hubListener);
    check hubListener.attach(hubService, "hub");
    check hubListener.'start();
    log:printInfo("Websubhub service started successfully");
}

// isolated function getHubPort() returns int|error {
//     string hubPort = os:getEnv("HUB_PORT");
//     if hubPort == "" {
//         return config:server.port;
//     }
//     return int:fromString(hubPort);
// }
