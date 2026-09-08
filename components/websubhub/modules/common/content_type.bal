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

import ballerina/mime;


public const DEFAULT_CONTENT_TYPE = mime:APPLICATION_JSON;
public const TOPIC_CONTENT_TYPE_HEADER = "x-hub-content-type";

public final readonly & string[] SUPPORTED_TOPIC_CONTENT_TYPES = [
    mime:APPLICATION_JSON,
    mime:APPLICATION_XML,
    mime:TEXT_PLAIN,
    mime:APPLICATION_OCTET_STREAM
];

# Checks whether a content type may be declared for a topic.
#
# + contentType - The content type to check, normalized to lower case
# + return - `true` if a topic may declare this content type
public isolated function isSupportedTopicContentType(string contentType) returns boolean {
    return SUPPORTED_TOPIC_CONTENT_TYPES.indexOf(contentType) !is ();
}

# Normalizes a content type for comparison.
#
# + contentType - The content type to normalize
# + return - The media type, lower-cased and stripped of any parameters
public isolated function normalizeContentType(string contentType) returns string {
    int? separator = contentType.indexOf(";");
    string mediaType = separator is int ? contentType.substring(0, separator) : contentType;
    return mediaType.trim().toLowerAscii();
}
