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
import ballerina/jwt;
import ballerina/log;
import ballerina/os;

final http:ListenerJwtAuthHandler? jwtAuthHandler = getJwtAuthHandler();

isolated function getJwtAuthHandler() returns http:ListenerJwtAuthHandler? {
    common:JwtValidatorConfig? config = config:server.auth;
    if config is () {
        return;
    }
    http:JwtValidatorConfig validatorConfig = {
        issuer: getIdpConfig("IDP_TOKEN_ISSUER", config.issuer),
        audience: getIdpConfig("IDP_TOKEN_AUDIENCE", config.audience),
        scopeKey: getIdpConfig("IDP_TOKEN_SCOPE_KEY", config.scopeKey)
    };
    jwt:ValidatorSignatureConfig? signature = config.signature;
    if signature is jwt:ValidatorSignatureConfig {
        validatorConfig.signatureConfig = signature;
    }
    return new (validatorConfig);
}

isolated function getIdpConfig(string envVariableName, string defaultValue) returns string {
    return os:getEnv(envVariableName) == "" ? defaultValue : os:getEnv(envVariableName);
}

# Checks for authorization for the current request.
#
# + headers - `http:Headers` for the current request
# + authScopes - Requested auth-scopes to access the current resource
# + return - `error` if there is any authorization error or else `()`
public isolated function authorize(http:Headers headers, string[] authScopes) returns error? {
    http:ListenerJwtAuthHandler? handler = jwtAuthHandler;
    if handler is () {
        return;
    }
    string|http:HeaderNotFoundError authHeader = headers.getHeader(http:AUTH_HEADER);
    if authHeader is string {
        jwt:Payload|http:Unauthorized auth = handler.authenticate(authHeader);
        if auth is jwt:Payload {
            http:Forbidden? forbiddenError = handler.authorize(auth, authScopes);
            if forbiddenError is http:Forbidden {
                log:printError("Forbidden Error received - Authentication credentials invalid");
                return error("Not authorized");
            }
        } else {
            log:printError("Unauthorized Error received - Authentication credentials invalid");
            return error("Not authorized");
        }
    } else {
        log:printError("Authorization header not found");
        return error("Not authorized");
    }
}
