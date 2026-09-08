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

# Publisher request headers propagated to subscribers by default.
public final readonly & string[] DEFAULT_FORWARDED_HEADERS = [
    "traceparent",
    "tracestate",
    "baggage"
];

# Checks whether a publisher request header may be propagated to subscribers.
#
# + headerName - The header name to check, in any case
# + additional - Extra header names the deployment has opted into, in any case
# + return - `true` if the header may be propagated to subscribers
public isolated function isForwardableHeader(string headerName, string[] additional = []) returns boolean {
    string name = headerName.toLowerAscii();
    if DEFAULT_FORWARDED_HEADERS.indexOf(name) !is () {
        return true;
    }
    foreach string allowed in additional {
        if allowed.toLowerAscii() == name {
            return true;
        }
    }
    return false;
}
