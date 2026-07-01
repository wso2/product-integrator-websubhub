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

import websubhub.config;
import websubhub.security;

import ballerina/http;
import ballerina/mime;
import ballerina/websubhub;

# Content-unaware (passthrough) publish endpoint.
#
# Reads the request body as raw bytes via `getBinaryPayload()` without parsing it and preserves the
# publisher's `Content-Type` verbatim. Unlike the standard WebSub publish endpoint (`/hub` with
# `hub.mode=publish`), which is restricted by the `ballerina/websubhub` library to five parseable
# content types, this endpoint accepts any content type (e.g. `image/png`, `application/pdf`) and
# moves the payload through ingest as a single `byte[]` copy — no parse, no re-serialization.
#
# It is additive: existing WebSub publishers keep using `/hub`. It is attached to the shared hub
# `http:Listener` in `start_hub.bal` at `config:server.publishEndpoint.path` when enabled.
http:Service rawPublishService = isolated service object {

    # Accepts a raw content publish. The target topic is taken from the `hub.topic` query parameter;
    # the body bytes and `Content-Type` are stored as-is and carried to subscribers unchanged.
    #
    # + request - The incoming publish request; its body is read as opaque bytes
    # + headers - `http:Headers` of the request, used for authorization, message id, and metadata
    # + return - `202 Accepted` on success, or a `4xx`/`5xx` response describing the failure
    isolated resource function post .(http:Request request, http:Headers headers)
            returns http:Accepted|http:Unauthorized|http:BadRequest|http:NotFound|http:InternalServerError {
        if config:securityOn {
            error? authResult = security:authorize(headers, ["update_content"]);
            if authResult is error {
                return <http:Unauthorized>{body: authResult.message()};
            }
        }

        string? topic = request.getQueryParamValue("hub.topic");
        if topic is () || topic.trim() == "" {
            return <http:BadRequest>{body: "Missing required query parameter: hub.topic"};
        }

        byte[]|error payload = request.getBinaryPayload();
        if payload is error {
            return <http:BadRequest>{body: "Unable to read the request payload: " + payload.message()};
        }

        // Preserve the publisher's Content-Type verbatim; default to octet-stream when absent so the
        // bytes are still delivered as opaque binary rather than being misinterpreted downstream.
        string contentType = request.getContentType();
        if contentType.trim() == "" {
            contentType = mime:APPLICATION_OCTET_STREAM;
        }

        websubhub:UpdateMessage msg = {
            msgType: websubhub:PUBLISH,
            hubTopic: topic,
            contentType,
            content: payload
        };
        websubhub:UpdateMessageError? result = publishUpdateMessage(msg, headers);
        if result is websubhub:UpdateMessageError {
            if result.detail().statusCode == http:STATUS_NOT_FOUND {
                return <http:NotFound>{body: result.message()};
            }
            return <http:InternalServerError>{body: result.message()};
        }
        return <http:Accepted>{};
    }
};
