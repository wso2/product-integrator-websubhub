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

public const MESSAGE_ID_HEADER = "x-hub-messageId";

final readonly & string[] DENIED_METADATA_HEADERS = [
    "authorization",
    "proxy-authorization",
    "cookie",
    "set-cookie",
    "host",
    "content-length",
    "content-type",
    "content-encoding",
    "transfer-encoding",
    "connection",
    "keep-alive",
    "upgrade",
    "te",
    "trailer",
    "expect",
    "accept-encoding",
    "x-hub-signature",
    "link",
    "x-ballerina-publisher",
    "x-hub-messageid",
    "x-hub-content-type"
];

# Checks whether a request header must be excluded from message-store metadata and content delivery.
#
# + headerName - The header name to check, in any case
# + return - `true` if the header must not be propagated to subscribers
public isolated function isDeniedMetadataHeader(string headerName) returns boolean {
    return DENIED_METADATA_HEADERS.indexOf(headerName.toLowerAscii()) !is ();
}
