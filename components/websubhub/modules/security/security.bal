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

final http:ListenerJwtAuthHandler? jwtAuthHandler = getJwtAuthHandler();

isolated function getJwtAuthHandler() returns http:ListenerJwtAuthHandler? {
    log:printDebug("Initializing JWT authentication handler");
    common:JwtValidatorConfig? config = config:server.auth;
    if config is () {
        log:printDebug("No JWT authentication configuration found - security disabled");
        return;
    }
    log:printDebug("JWT authentication configuration found", issuer = config.issuer, audience = config.audience);
    http:JwtValidatorConfig validatorConfig = {
        issuer: config.issuer,
        audience: config.audience,
        scopeKey: config.scopeKey
    };
    common:JwksConfig? signature = config.signature;
    if signature is common:JwksConfig {
        log:printDebug("Configuring JWKS for JWT validation", jwksUrl = signature.url);
        validatorConfig.signatureConfig.jwksConfig = {
            url: signature.url,
            clientConfig: {
                secureSocket: signature.secureSocket
            }
        };
    } else {
        log:printDebug("No JWKS configuration found - using default signature validation");
    }
    log:printDebug("JWT authentication handler initialized successfully");
    return new (validatorConfig);
}

# Checks for authorization for the current request.
#
# + headers - `http:Headers` for the current request
# + authScopes - Requested auth-scopes to access the current resource
# + return - `error` if there is any authorization error or else `()`
public isolated function authorize(http:Headers headers, string[] authScopes) returns error? {
    log:printDebug("Starting authorization check", requiredScopes = authScopes);
    http:ListenerJwtAuthHandler? handler = jwtAuthHandler;
    if handler is () {
        log:printDebug("No JWT auth handler configured - skipping authorization");
        return;
    }
    log:printDebug("JWT auth handler found - performing authorization");
    string|http:HeaderNotFoundError authHeader = headers.getHeader(http:AUTH_HEADER);
    if authHeader is string {
        log:printDebug("Authorization header found - authenticating JWT");
        jwt:Payload|http:Unauthorized auth = handler.authenticate(authHeader);
        if auth is jwt:Payload {
            log:printDebug("JWT authentication successful - checking authorization", subject = auth.sub, issuer = auth.iss);
            http:Forbidden? forbiddenError = handler.authorize(auth, authScopes);
            if forbiddenError is http:Forbidden {
                common:logError("Authorization failed - insufficient scopes", requiredScopes = authScopes, subject = auth.sub);
                return error("Not authorized");
            } else {
                log:printDebug("Authorization successful", subject = auth.sub, grantedScopes = authScopes);
            }
        } else {
            common:logError("JWT authentication failed - unauthorized");
            return error("Not authorized");
        }
    } else {
        log:printDebug("Authorization header not found in request");
        common:logError("Authorization header not found in request");
        return error("Not authorized");
    }
    log:printDebug("Authorization check completed successfully", requiredScopes = authScopes);
}
