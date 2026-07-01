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

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;
import ballerina/websubhub;

import wso2/messagestore as store;

public function main() returns error? {
    error? validation = store:validateConfig(config:store);
    if validation is error {
        common:logFatalError("Message store configuration validation failed", validation);
        return;
    }

    // Starting the health-check service
    http:Listener httpListener = check new (config:server.port,
        secureSocket = common:extractListenerSecureSocketConfig(config:server.secureSocket)
    );
    check httpListener.attach(healthCheckService, "/health");

    // Attach the content-unaware (passthrough) publish endpoint when enabled. It shares the hub
    // listener but is hosted on a distinct path, so it does not collide with the WebSub hub service.
    if config:server.publishEndpoint.enabled {
        string epPath = config:server.publishEndpoint.path.trim();
        if epPath == "" || epPath == "/hub" || epPath == "hub" || epPath == "/health" {
            return error(string `Invalid publishEndpoint.path '${epPath}': must be non-empty and must not conflict with /hub or /health`);
        }
        check httpListener.attach(rawPublishService, epPath);
        log:printInfo("Content passthrough publish endpoint enabled", path = epPath);
    }

    // Start the Hub
    websubhub:Listener hubListener = check new (httpListener);
    check hubListener.attach(hubService, "hub");
    check hubListener.'start();
    runtime:registerListener(hubListener);

    // Initialize the Hub
    check initializeHubState();
    log:printInfo("Websubhub service started successfully");
}
