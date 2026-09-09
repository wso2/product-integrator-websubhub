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

import ballerina/crypto;
import ballerina/http;
import ballerina/log;
import ballerina/os;

import ballerinax/solace;

const KEYSTORE_PATH = "WEBSUBHUB_KEYSTORE_PATH";
const KEYSTORE_PASSWORD = "WEBSUBHUB_KEYSTORE_PASSWORD";
const TRUSTSTORE_PATH = "WEBSUBHUB_TRUSTSTORE_PATH";
const TRUSTSTORE_PASSWORD = "WEBSUBHUB_TRUSTSTORE_PASSWORD";
const ENABLE_MSGSTORE_MTLS = "ENABLE_MSGSTORE_MTLS";

isolated function extractSolaceSecureSocketConfig(solace:SecureSocket? config) returns solace:SecureSocket? {
    solace:KeyStore? extractedKeyStore = extractSolaceKeystoreConfig(config?.keyStore);
    solace:TrustStore? extractedTrustStore = extractSolaceTruststoreConfig(config?.trustStore);

    if config is solace:SecureSocket {
        var {keyStore, trustStore, ...conf} = config;
        return {
            keyStore: extractedKeyStore,
            trustStore: extractedTrustStore,
            ...conf
        };
    }

    if extractedKeyStore is () && extractedTrustStore is () {
        return;
    }

    return {
        keyStore: extractedKeyStore,
        trustStore: extractedTrustStore
    };
}

isolated function extractSolaceKeystoreConfig(solace:KeyStore? config) returns solace:KeyStore? {
    boolean mTlsEnabled = os:getEnv(ENABLE_MSGSTORE_MTLS) == "true";
    if !mTlsEnabled {
        log:printDebug("[Solace MessageStore] Ignoring keystore configurations as mTLS is disabled for Solace");
        return;
    }

    var keystore = getSecureStoreFromEnv(KEYSTORE_PATH, KEYSTORE_PASSWORD);
    if keystore !is () {
        return {
            location: keystore.path,
            password: keystore.password
        };
    }
    log:printDebug("[Solace MessageStore] Ignoring keystore env override: both WEBSUBHUB_KEYSTORE_PATH and WEBSUBHUB_KEYSTORE_PASSWORD must be set");
    return config;
}

isolated function extractSolaceTruststoreConfig(solace:TrustStore? config) returns solace:TrustStore? {
    var truststore = getSecureStoreFromEnv(TRUSTSTORE_PATH, TRUSTSTORE_PASSWORD);
    if truststore !is () {
        return {
            location: truststore.path,
            password: truststore.password
        };
    }
    log:printDebug("[Solace MessageStore] Ignoring truststore env override: both WEBSUBHUB_TRUSTSTORE_PATH and WEBSUBHUB_TRUSTSTORE_PASSWORD must be set");
    return config;
}

isolated function extractSolaceAdminSecureSocketConfig(http:ClientSecureSocket? config) returns http:ClientSecureSocket? {
    crypto:KeyStore|http:CertKey? extractedKeyStore = extractSolaceAdminKeystoreConfig(config?.'key);
    crypto:TrustStore|string? extractedTrustStore = extractSolaceAdminTruststoreConfig(config?.'cert);

    if config is http:ClientSecureSocket {
        var {'key, cert, ...conf} = config;
        return {
            'key: extractedKeyStore,
            'cert: extractedTrustStore,
            ...conf
        };
    }

    if extractedKeyStore is () && extractedTrustStore is () {
        return;
    }

    return {
        'key: extractedKeyStore,
        'cert: extractedTrustStore
    };
}

isolated function extractSolaceAdminKeystoreConfig(crypto:KeyStore|http:CertKey? 'key) returns crypto:KeyStore|http:CertKey? {
    boolean mTlsEnabled = os:getEnv(ENABLE_MSGSTORE_MTLS) == "true";
    if !mTlsEnabled {
        log:printDebug("[Solace MessageStore Admin] Ignoring keystore configurations as mTLS is disabled for Solace");
        return;
    }

    var keystore = getSecureStoreFromEnv(KEYSTORE_PATH, KEYSTORE_PASSWORD);
    if keystore !is () {
        return {
            path: keystore.path,
            password: keystore.password
        };
    }
    log:printDebug("[Solace MessageStore Admin] Ignoring keystore env override: both WEBSUBHUB_KEYSTORE_PATH and WEBSUBHUB_KEYSTORE_PASSWORD must be set");
    return 'key;
}

isolated function extractSolaceAdminTruststoreConfig(crypto:TrustStore|string? 'cert) returns crypto:TrustStore|string? {
    var truststore = getSecureStoreFromEnv(TRUSTSTORE_PATH, TRUSTSTORE_PASSWORD);
    if truststore !is () {
        return {
            path: truststore.path,
            password: truststore.password
        };
    }
    log:printDebug("[Solace MessageStore Admin] Ignoring truststore env override: both WEBSUBHUB_TRUSTSTORE_PATH and WEBSUBHUB_TRUSTSTORE_PASSWORD must be set");
    return 'cert;
}

isolated function getSecureStoreFromEnv(string storePathKey, string storePasswordKey) returns record {|string path; string password;|}? {
    string path = os:getEnv(storePathKey);
    string password = os:getEnv(storePasswordKey);
    if path == "" || password == "" {
        return;
    }
    return {path, password};
}
