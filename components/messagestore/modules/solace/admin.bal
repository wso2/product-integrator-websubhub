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

import messagestore.api;

import ballerina/http;
import ballerina/log;

import xlibb/solace.semp;

type SolaceQueueNotFound distinct error;

type SolaceEntityNotFound distinct error;

type SolaceQueueExists distinct error;

type SolaceEntityExists distinct error;

type SolaceQueuePermission "no-access"|"read-only"|"consume"|"modify-topic"|"delete";

const string META_QUEUE_NAME = "solace.queue_name";
const string META_DLQ_NAME = "solace.dlq_name";
const string META_MAX_MSG_SPOOL = "solace.max_msg_spool";
const string META_NON_OWNER_PERMISSION = "solace.non_owner_permission";
const string META_DELIVERY_COUNT_ENABLED = "solace.delivery_count_enabled";
const string META_RESPECT_TTL = "solace.respect_ttl";
const string META_MAX_TTL = "solace.max_ttl";
const string META_REDELIVERY_ENABLED = "solace.redelivery_enabled";
const string META_REDELIVERY_TRY_FOREVER = "solace.redelivery_try_forever";
const string META_REDELIVERY_MAX_COUNT = "solace.redelivery_max_count";

public isolated client class Administrator {
    *api:Administrator;

    private final semp:Client administrator;
    private final string messageVpn;
    private final readonly & SolaceQueueConfig? queueConfig;

    public isolated function init(Config config) returns error? {
        self.administrator = check new (
            serviceUrl = config.admin.url,
            config = {
                timeout: config.admin.timeout,
                secureSocket: extractSolaceAdminSecureSocketConfig(config.admin.secureSocket),
                auth: config.admin.auth,
                retryConfig: config.admin.retryConfig
            }
        );
        self.messageVpn = config.messageVpn;
        self.queueConfig = config.queue.cloneReadOnly();
    }

    isolated remote function createTopic(string topic, boolean systemTopic = false, record {} meta = {}) returns api:TopicExists|error? {
        return;
    }

    isolated remote function deleteTopic(string topic, boolean systemTopic = false, record {} meta = {}) returns api:TopicNotFound|error? {
        return;
    }

    isolated remote function createSubscription(string topic, string queueName, boolean systemSubscriber = false, record {} meta = {}) returns api:SubscriptionExists|error? {
        string effectiveQueueName = systemSubscriber ? queueName : resolveQueueName(self.queueConfig, queueName, meta);
        string effectiveDlqName = resolveDlqName(self.queueConfig, effectiveQueueName, meta);
        log:printWarn("Creating topic subscription for ", topic = topic, queue = effectiveQueueName, dlq = effectiveDlqName);
        semp:MsgVpnQueue|error queue = self.retrieveQueue(effectiveQueueName);
        if queue is SolaceQueueNotFound {
            semp:MsgVpnQueue|error dlq = self.retrieveQueue(effectiveDlqName);
            if dlq is SolaceQueueNotFound {
                _ = check self.createQueue(effectiveDlqName, (), self.queueConfig, meta);
            } else if dlq is error {
                return dlq;
            }
            _ = check self.createQueue(effectiveQueueName, effectiveDlqName, self.queueConfig, meta);
        } else if queue is error {
            return queue;
        }
        _ = check self.addTopicSubscription(effectiveQueueName, topic);
    }

    isolated remote function deleteSubscription(string topic, string queueName, boolean systemSubscriber = false, record {} meta = {}) returns api:SubscriptionNotFound|error? {
        string effectiveQueueName = systemSubscriber ? queueName : resolveQueueName(self.queueConfig, queueName, meta);
        string effectiveDlqName = resolveDlqName(self.queueConfig, effectiveQueueName, meta);
        log:printWarn("Deleting topic subscription for ", topic = topic, queue = effectiveQueueName, dlq = effectiveDlqName);
        semp:MsgVpnQueueSubscription[]? subscriptions = check self.retrieveTopicSubscriptions(effectiveQueueName);
        if subscriptions is () {
            return;
        }

        semp:MsgVpnQueueSubscription[] filteredSubscriptions = subscriptions.filter(a => a.subscriptionTopic === topic);
        if filteredSubscriptions.length() === 0 {
            // If the topic-subscription is not-available return nil so that unsubscription not fail
            return;
        }

        _ = check self.removeTopicSubscription(effectiveQueueName, topic);

        if subscriptions.length() === 1 {
            check self.deleteQueue(effectiveQueueName);
            if !systemSubscriber && meta.hasKey(META_DLQ_NAME) {
                boolean? dlqDeleteEnabled = self.queueConfig?.dlq?.deleteCustomOnUbsubscription;
                if dlqDeleteEnabled is () || !dlqDeleteEnabled {
                    return;
                }
            }
            check self.deleteQueue(effectiveDlqName);
        }
    }

    isolated function retrieveQueue(string queueName) returns semp:MsgVpnQueue|error {
        string vpn = self.messageVpn;
        semp:MsgVpnQueueResponse|error response = self.administrator->getMsgVpnQueue(
            msgVpnName = vpn,
            queueName = queueName
        );
        if response is semp:MsgVpnQueueResponse {
            if response.data is semp:MsgVpnQueue {
                return <semp:MsgVpnQueue>response.data;
            }
            return error SolaceQueueNotFound(string `Empty response received when tried to retrieve queue [${queueName}] for vpn [${vpn}]`);
        }

        if response is http:ClientRequestError {
            http:Detail errorDetails = response.detail();
            if errorDetails.statusCode !== http:STATUS_BAD_REQUEST {
                return response;
            }
            record {semp:SempMeta meta;} payload = check errorDetails.body.cloneWithType();
            if "NOT_FOUND" === payload.meta.'error?.status {
                return error SolaceQueueNotFound(string `Could not find the queue [${queueName}] for vpn [${vpn}]`);
            }
            return response;
        }

        return response;
    }

    isolated function createQueue(string queueName, string? dlqName = (), SolaceQueueConfig? queueConfig = (), record {} meta = {}) returns semp:MsgVpnQueue|error {
        string vpn = self.messageVpn;
        semp:MsgVpnQueue queuePayload = check buildQueuePayload(queueName, dlqName, queueConfig, meta);
        semp:MsgVpnQueueResponse|error response = self.administrator->createMsgVpnQueue(msgVpnName = vpn, payload = queuePayload);
        if response is semp:MsgVpnQueueResponse {
            if response.data is semp:MsgVpnQueue {
                return <semp:MsgVpnQueue>response.data;
            }
            return error(string `Empty response received when tried to create a queue [${queueName}] in vpn [${vpn}]`);
        }

        if response is http:ClientRequestError {
            http:Detail errorDetails = response.detail();
            if errorDetails.statusCode !== http:STATUS_BAD_REQUEST {
                return response;
            }
            record {semp:SempMeta meta;} payload = check errorDetails.body.cloneWithType();
            if "NOT_FOUND" === payload.meta.'error?.status {
                return error(string `Could not find the vpn [${vpn}]`);
            }
            if "ALREADY_EXISTS" !== payload.meta.'error?.status {
                return response;
            }
            return error SolaceQueueExists(string `Queue [${queueName}] already exists in vpn [${vpn}]`);
        }
        return response;
    }

    isolated function addTopicSubscription(string queueName, string subscriptionTopic) returns semp:MsgVpnQueueSubscription|error {
        string vpn = self.messageVpn;
        semp:MsgVpnQueueSubscriptionResponse|error response = self.administrator->createMsgVpnQueueSubscription(
            msgVpnName = vpn,
            queueName = queueName,
            payload = {
            subscriptionTopic
        }
        );
        if response is semp:MsgVpnQueueSubscriptionResponse {
            if response.data is semp:MsgVpnQueueSubscription {
                return <semp:MsgVpnQueueSubscription>response.data;
            }
            return error(string `Empty response received when trying to add a topic subscription [${subscriptionTopic}] for a queue [${queueName}] in vpn [${vpn}]`);
        }

        if response is http:ClientRequestError {
            http:Detail errorDetails = response.detail();
            if errorDetails.statusCode !== http:STATUS_BAD_REQUEST {
                return response;
            }
            record {semp:SempMeta meta;} payload = check errorDetails.body.cloneWithType();
            if "NOT_FOUND" === payload.meta.'error?.status {
                return error(string `Could not find either the queue [${queueName}] or the vpn [${vpn}]`);
            }
            if "ALREADY_EXISTS" === payload.meta.'error?.status {
                return error api:SubscriptionExists(string `Topic subscription [${subscriptionTopic}] already existst for queue [${queueName}] in vpn [${vpn}]`);
            }
            return response;
        }
        return response;
    }

    isolated function retrieveTopicSubscriptions(string queueName) returns semp:MsgVpnQueueSubscription[]|error? {
        string vpn = self.messageVpn;
        semp:MsgVpnQueueSubscription[] subscriptions = [];
        string? cursor = ();

        while true {
            semp:MsgVpnQueueSubscriptionsResponse|error response;
            if cursor is string {
                response = self.administrator->getMsgVpnQueueSubscriptions(
                    msgVpnName = vpn,
                    queueName = queueName,
                    cursor = cursor
                );
            } else {
                response = self.administrator->getMsgVpnQueueSubscriptions(
                    msgVpnName = vpn,
                    queueName = queueName
                );
            }

            if response is http:ClientRequestError {
                http:Detail details = response.detail();
                if details.statusCode == http:STATUS_BAD_REQUEST {
                    record {semp:SempMeta meta;} payload = check details.body.cloneWithType();
                    if payload.meta.'error?.status == "NOT_FOUND" {
                        log:printDebug(string `No subscriptions found or queue [${queueName}] does not exist`);
                        // If the topic or VPN not found return nil, so that unsubscription could be successful when there is unexpected queue deletion
                        return;
                    }
                }
                return response;
            }
            if response is error {
                return response;
            }

            if response.data is semp:MsgVpnQueueSubscription[] {
                subscriptions.push(...(<semp:MsgVpnQueueSubscription[]>response.data));
            }

            semp:SempPaging? paging = response.meta.paging;
            if paging is () {
                break;
            }

            cursor = paging.cursorQuery;
        }

        return subscriptions;
    }

    isolated function removeTopicSubscription(string queueName, string subscriptionTopic) returns error? {
        _ = check self.administrator->deleteMsgVpnQueueSubscription(
            msgVpnName = self.messageVpn,
            queueName = queueName,
            subscriptionTopic = subscriptionTopic
        );
    }

    isolated function deleteQueue(string queueName) returns error? {
        var response = self.administrator->deleteMsgVpnQueue(
            msgVpnName = self.messageVpn,
            queueName = queueName
        );
        if response is http:ClientRequestError {
            http:Detail details = response.detail();
            if details.statusCode == http:STATUS_BAD_REQUEST {
                record {semp:SempMeta meta;} payload = check details.body.cloneWithType();
                if payload.meta.'error?.status == "NOT_FOUND" {
                    return;
                }
            }
            return response;
        }

        if response is error {
            return response;
        }
    }

    isolated remote function close() returns error? {
        return;
    }
}

isolated function resolveQueueName(SolaceQueueConfig? queueConfig, string queueId, record {} meta) returns string {
    anydata val = meta[META_QUEUE_NAME];
    if val is string {
        return val;
    }
    string? queueNamePrefix = queueConfig?.queueNamePrefix;
    if queueNamePrefix is string {
        return string `${queueNamePrefix}${queueId}`;
    }
    return string `consumer-${queueId}`;
}

isolated function resolveDlqName(SolaceQueueConfig? queueConfig, string queueName, record {} meta) returns string {
    anydata val = meta[META_DLQ_NAME];
    if val is string {
        return val;
    }
    string? dlqPrefix = queueConfig?.dlq?.prefix;
    if dlqPrefix is string {
        return string `${dlqPrefix}${queueName}`;
    }
    return string `dlq-${queueName}`;
}

isolated function buildQueuePayload(string queueName, string? dlqName, SolaceQueueConfig? queueConfig, record {} meta) returns semp:MsgVpnQueue|error {
    semp:MsgVpnQueue payload = {
        queueName,
        accessType: "non-exclusive",
        ingressEnabled: true,
        egressEnabled: true
    };

    if dlqName is string {
        payload.deadMsgQueue = dlqName;
    }

    if queueConfig is SolaceQueueConfig {
        payload.owner = queueConfig.queueOwner;
        payload.maxMsgSpoolUsage = queueConfig.messageQueueQuota;
        payload.deliveryCountEnabled = queueConfig.deliveryCountEnabled;
        payload.respectTtlEnabled = queueConfig.respectTtl;
        payload.maxTtl = queueConfig.maxTtl;
        payload.permission = check queueConfig.nonOwnerPermission.cloneWithType(SolaceQueuePermission);

        var redeliver = queueConfig.redeliver;
        if redeliver is record {|int maxCount;|} {
            payload.redeliveryEnabled = true;
            payload.maxRedeliveryCount = redeliver.maxCount;
        } else if redeliver is record {|boolean tryForever;|} && redeliver.tryForever {
            payload.redeliveryEnabled = true;
            payload.maxRedeliveryCount = 0;
        }
    }

    anydata spoolVal = meta[META_MAX_MSG_SPOOL];
    if spoolVal is int {
        payload.maxMsgSpoolUsage = spoolVal;
    } else if spoolVal is string {
        int|error parsed = int:fromString(spoolVal);
        if parsed is int {
            payload.maxMsgSpoolUsage = parsed;
        } else {
            return error(string `invalid meta value for '${META_MAX_MSG_SPOOL}': "${spoolVal}", expected an integer`);
        }
    }

    anydata permVal = meta[META_NON_OWNER_PERMISSION];
    if permVal is string {
        SolaceQueuePermission|error perm = permVal.cloneWithType(SolaceQueuePermission);
        if perm is SolaceQueuePermission {
            payload.permission = perm;
        } else {
            return error(string `invalid meta value for '${META_NON_OWNER_PERMISSION}': "${permVal}", expected an "no-access" or "read-only" or "consume" or "modify-topic" or "delete"`);
        }
    }

    anydata dcVal = meta[META_DELIVERY_COUNT_ENABLED];
    if dcVal is boolean {
        payload.deliveryCountEnabled = dcVal;
    } else if dcVal is string {
        if dcVal == "true" || dcVal == "false" {
            payload.deliveryCountEnabled = dcVal == "true";
        } else {
            return error(string `invalid meta value for '${META_DELIVERY_COUNT_ENABLED}': "${dcVal}", expected boolean or "true"/"false"`);
        }
    } else if dcVal !is () {
        return error(string `invalid meta value for '${META_DELIVERY_COUNT_ENABLED}': expected boolean or string`);
    }

    anydata ttlVal = meta[META_RESPECT_TTL];
    if ttlVal is boolean {
        payload.respectTtlEnabled = ttlVal;
    } else if ttlVal is string {
        if ttlVal == "true" || ttlVal == "false" {
            payload.respectTtlEnabled = ttlVal == "true";
        } else {
            return error(string `invalid meta value for '${META_RESPECT_TTL}': "${ttlVal}", expected boolean or "true"/"false"`);
        }
    } else if ttlVal !is () {
        return error(string `invalid meta value for '${META_RESPECT_TTL}': expected boolean or string`);
    }

    anydata maxTtlVal = meta[META_MAX_TTL];
    if maxTtlVal is int {
        payload.maxTtl = maxTtlVal;
    } else if maxTtlVal is string {
        int|error parsed = int:fromString(maxTtlVal);
        if parsed is int {
            payload.maxTtl = parsed;
        } else {
            return error(string `invalid meta value for '${META_MAX_TTL}': "${maxTtlVal}", expected an integer`);
        }
    }

    anydata redeliveryVal = meta[META_REDELIVERY_ENABLED];
    if redeliveryVal is boolean {
        payload.redeliveryEnabled = redeliveryVal;
    } else if redeliveryVal is string {
        if redeliveryVal == "true" || redeliveryVal == "false" {
            payload.redeliveryEnabled = redeliveryVal == "true";
        } else {
            return error(string `invalid meta value for '${META_REDELIVERY_ENABLED}': "${redeliveryVal}", expected boolean or "true"/"false"`);
        }
    } else if redeliveryVal !is () {
        return error(string `invalid meta value for '${META_REDELIVERY_ENABLED}': expected boolean or string`);
    }

    anydata maxCountVal = meta[META_REDELIVERY_MAX_COUNT];
    if maxCountVal is int {
        payload.redeliveryEnabled = true;
        payload.maxRedeliveryCount = maxCountVal;
    } else if maxCountVal is string {
        int|error parsed = int:fromString(maxCountVal);
        if parsed is int {
            payload.redeliveryEnabled = true;
            payload.maxRedeliveryCount = parsed;
        } else {
            return error(string `invalid meta value for '${META_REDELIVERY_MAX_COUNT}': "${maxCountVal}", expected an integer`);
        }
    }

    anydata tryForeverVal = meta[META_REDELIVERY_TRY_FOREVER];
    if (tryForeverVal is boolean && tryForeverVal) || tryForeverVal == "true" {
        payload.redeliveryEnabled = true;
        payload.maxRedeliveryCount = 0;
    }

    return payload;
}
