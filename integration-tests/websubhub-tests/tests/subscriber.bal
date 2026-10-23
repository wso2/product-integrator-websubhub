// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
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

# An intent verification (or denial) request received by a test subscriber.
type VerificationRequest record {|
    # The `hub.mode` of the request, e.g. `subscribe`, `unsubscribe` or `denied`
    string mode;
    # The `hub.topic` of the request
    string? topic;
    # The `hub.reason` of a denial
    string? reason;
|};

# A content delivery received by a test subscriber.
type ContentDelivery record {|
    # The delivered payload
    string payload;
    # The `X-Hub-Signature` header, if the hub signed the content
    string? signature;
    # The `Content-Type` header, exactly as received. Recorded verbatim rather than parsed:
    # a hub that rewrites every delivery to `application/json` still delivers successfully, so
    # the raw header is the only thing that distinguishes passthrough from a default.
    string? contentType;
|};

isolated map<VerificationRequest[]> verificationRequests = {};
isolated map<ContentDelivery[]> contentDeliveries = {};

// Test subscribers, each identified by the last segment of its callback URL
listener http:Listener subscriberListener = new (subscriberPort);

service /callback on subscriberListener {

    // Intent verification: echo the challenge to accept the (un)subscription
    resource function get [string id](http:Request request) returns string {
        map<string[]> query = request.getQueryParams();
        VerificationRequest verification = {
            mode: firstValue(query, "hub.mode") ?: "",
            topic: firstValue(query, "hub.topic"),
            reason: firstValue(query, "hub.reason")
        };
        lock {
            verificationRequests[id] = [...(verificationRequests[id] ?: []), verification.clone()];
        }
        return firstValue(query, "hub.challenge") ?: "";
    }

    // Content delivery
    resource function post [string id](http:Request request) returns http:Ok|error {
        string|http:HeaderNotFoundError signature = request.getHeader("X-Hub-Signature");
        string|http:HeaderNotFoundError contentType = request.getHeader("Content-Type");
        ContentDelivery delivery = {
            payload: check request.getTextPayload(),
            signature: signature is string ? signature : (),
            contentType: contentType is string ? contentType : ()
        };
        lock {
            contentDeliveries[id] = [...(contentDeliveries[id] ?: []), delivery.clone()];
        }
        return http:OK;
    }
}

isolated function verificationsOf(string id) returns VerificationRequest[] {
    lock {
        return (verificationRequests[id] ?: []).clone();
    }
}

isolated function deliveriesOf(string id) returns ContentDelivery[] {
    lock {
        return (contentDeliveries[id] ?: []).clone();
    }
}

isolated function hasVerification(string id, string mode) returns boolean =>
    verificationsOf(id).some(verification => verification.mode == mode);

isolated function firstValue(map<string[]> query, string name) returns string? {
    string[]? values = query[name];
    return values is string[] && values.length() > 0 ? values[0] : ();
}
