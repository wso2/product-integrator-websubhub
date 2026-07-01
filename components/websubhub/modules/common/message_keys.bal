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

public const SUBSCRIPTION_TIMESTAMP = "timestamp";
public const SUBSCRIPTION_STATUS = "status";
public const SUBSCRIPTION_SERVER_ID = "serverId";

# Internal contract — content-type passthrough.
#
# Key under which the original publisher Content-Type is carried through the message store so
# subscribers receive the correct `Content-Type` header. This is a broker-INTERNAL storage detail,
# NOT a publisher- or subscriber-facing API: publishers set a normal HTTP `Content-Type`, and
# subscribers receive a normal `Content-Type` header — neither sees this key.
#
# Lifecycle:
#   1. Ingest (persistence:addUpdateMessage) writes the effective content-type under this key into
#      the message metadata map. For JSON-serialized content (incl. form-urlencoded) it is pinned to
#      `application/json` because the stored bytes are JSON.
#   2. The message-store adapter MUST round-trip the metadata map across the broker:
#        - Solace: written to / read from `solace:Message.properties` (SDTMap user-properties).
#        - Kafka:  message headers (currently disabled — see kafka/consumer.bal TODO).
#      Any new broker adapter MUST preserve this key for content-type passthrough to work.
#   3. Delivery (delivery:constructContentDistMsg) reads this key to set the subscriber Content-Type;
#      if it is absent (legacy in-flight messages) it falls back to `application/json`.
public const CONTENT_TYPE_METADATA_KEY = "x-hub-contentType";

