================================================================================
                        WSO2 Integrator: WebSubHub 0.1.0
================================================================================

Welcome to the WSO2 Integrator: WebSubHub 0.1.0 release.

WSO2 Integrator: WebSubHub is a WebSub compliant hub implementation built on the
Ballerina programming language. It enables organizations to adopt event-driven
architectures by supporting standardized publish-subscribe communication over
HTTP(S). WebSub is a W3C recommendation that defines a simple, open, and
decentralized protocol for real-time publisher-subscriber communication.

WSO2 Integrator: WebSubHub consists of two main components working
together: the WebSubHub service which manages topics, processes subscriptions,
and delivers updates to subscribers, and the Consolidator service which
provides state snapshots and manages state synchronization. Both services are
required for the system to function. The system uses Apache Kafka as a
pluggable messaging backend for persistence, ensuring fault tolerance and
scalability.

WSO2 Integrator: WebSubHub is developed on top of the Ballerina
programming language, a cloud-native platform designed for integration
scenarios. This enables easy deployment in containerized and cloud
environments while providing powerful capabilities for building
event-driven microservice-based architectures.

To learn more about WSO2 Integrator: WebSubHub, visit the documentation at
https://wso2.github.io/docs-websubhub/


Key Features
=============

Event Distribution & Delivery:
    - WebSub protocol compliance (W3C standard for publish-subscribe over HTTP)
    - Real-time event distribution to subscribers
    - HTTP(S) based publish-subscribe communication
    - At-least-once delivery guarantee for reliable message delivery
    - Configurable automatic retry mechanisms with exponential backoff
    - Retry on specific HTTP status codes (500, 502, 503)
    - Configurable delivery timeout settings
    - Topic-based content distribution and management

Scalability & Architecture:
    - Pluggable messaging backend with Apache Kafka support
    - Horizontal scalability with multiple hub instances
    - Distributed state synchronization via Consolidator service
    - In-memory caching with Kafka persistence for optimal performance
    - Efficient batch processing for high-throughput scenarios
    - Configurable Kafka producer and consumer settings
    - State snapshot and recovery mechanisms

Security & Management:
    - JWT-based authentication via JWKS endpoints
    - OAuth2 client credentials flow support
    - Scope-based authorization (register_topic, deregister_topic, subscribe,
      unsubscribe, content_update)
    - External Identity Provider integration (tested with WSO2 IS 7.1)
    - Subscriber verification and management with intent validation
    - Health check endpoints for monitoring and orchestration
    - Configurable security (can be disabled for development)

Cloud-Native & Deployment:
    - Container-ready with Docker support
    - Easy deployment in cloud environments
    - Simple configuration via TOML files
    - Startup scripts for Unix/Mac and Windows platforms
    - Configurable JVM options for performance tuning
    - Support for distributed deployments with state synchronization


System Requirements
===================

1. Minimum memory - 2GB (1GB per service recommended for distributed deployment)

2. Processor - 1 Core/vCPU 1.1GHz or higher (multi-core recommended for
   production use)

3. Java SE Development Kit (JDK) version 21
   - Oracle JDK or OpenJDK (Adoptium recommended)

4. Apache Kafka (required for message persistence)
   - Recommended version: 3.x or higher
   - Must be running and accessible before starting WebSubHub services

5. External Identity Provider (optional, for JWT authentication)
   - Tested with WSO2 Identity Server 7.1
   - Must support OAuth2 client credentials and JWKS endpoints

6. To build WSO2 Integrator: WebSubHub from source:
   - Ballerina SwanLake 2201.13.1
   - Gradle 8.x or later


Installation & Running
======================

Prerequisites:
--------------
Ensure Apache Kafka is running and accessible (default: localhost:9092).

For quick setup with Docker:
    docker run -d -p 9092:9092 apache/kafka:latest


Installation:
-------------
1. Extract the wso2websubhub-distribution-0.1.0.zip file

2. The distribution contains both services:
   - wso2websubhub-0.1.0 (WebSubHub service)
   - wso2websubhub-consolidator-0.1.0 (Consolidator service)


Starting the Consolidator Service:
-----------------------------------
The Consolidator service is required and must be started FIRST.

1. Navigate to the wso2websubhub-consolidator-0.1.0 directory

2. Configure Apache Kafka connection in conf/Config.toml:
   [websubhub.consolidator.config.kafka.connection]
   bootstrapServers = "localhost:9092"

3. Run the startup script:
   - Unix/Mac: ./bin/wso2websubhub-consolidator.sh
   - Windows: bin\wso2websubhub-consolidator.bat

4. The Consolidator service will start on port 10001


Starting the WebSubHub Service:
--------------------------------
Start the WebSubHub service AFTER the Consolidator is running.

1. Navigate to the wso2websubhub-0.1.0 directory

2. Configure Apache Kafka connection in conf/Config.toml:
   [websubhub.config.store.kafka]
   bootstrapServers = "localhost:9092"

3. Run the startup script:
   - Unix/Mac: ./bin/wso2websubhub.sh
   - Windows: bin\wso2websubhub.bat

4. The WebSubHub service will start on port 9000 (HTTPS by default)

5. Verify the service is running:
   curl -k https://localhost:9000/health

IMPORTANT: The hub will fail to start if the Consolidator is not running, as
it requires the Consolidator to fetch the initial state snapshot during startup.


Quick Start Examples:
--------------------
Register a topic:
    curl -X POST https://localhost:9000/hub \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "hub.mode=register" -d "hub.topic=my-topic" -k

Publish content to a topic:
    curl -X POST "https://localhost:9000/hub?hub.mode=publish&hub.topic=my-topic" \
      -H "Content-Type: application/json" \
      -d '{"message": "Hello WebSub"}' -k

Subscribe to a topic:
    curl -X POST https://localhost:9000/hub \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "hub.mode=subscribe" \
      -d "hub.topic=my-topic" \
      -d "hub.callback=https://your-callback-url" \
      -d "hub.secret=your-secret" -k


WSO2 Integrator: WebSubHub Distribution Directory Structure
============================================================

The distribution contains both WebSubHub and Consolidator services:

    DISTRIBUTION_HOME
            |--- LICENSE
            |       Apache License 2.0 under which WSO2 Integrator: WebSubHub
            |       is distributed.
            |
            |--- README.md
            |       Product README with basic information.
            |
            |--- wso2websubhub-0.1.0
            |       WebSubHub service directory.
            |       |
            |       |--- bin
            |       |       Contains startup and shutdown scripts.
            |       |       |--- wso2websubhub.sh (Unix/Mac startup script)
            |       |       |--- wso2websubhub.bat (Windows startup script)
            |       |
            |       |--- conf
            |       |       Contains server configuration files.
            |       |       |--- Config.toml (Main configuration file)
            |       |       |--- resources
            |       |               Contains keystores and resource files.
            |       |               |--- wso2websubhub.jks (TLS keystore)
            |       |
            |       |--- lib
            |       |       Contains the executable JAR files for WebSubHub.
            |       |       |--- websubhub.jar
            |       |
            |       |--- LICENSE
            |       |--- README.md
            |
            |--- wso2websubhub-consolidator-0.1.0
                    Consolidator service directory.
                    |
                    |--- bin
                    |       Contains startup and shutdown scripts.
                    |       |--- wso2websubhub-consolidator.sh (Unix/Mac)
                    |       |--- wso2websubhub-consolidator.bat (Windows)
                    |
                    |--- conf
                    |       Contains server configuration files.
                    |       |--- Config.toml (Main configuration file)
                    |       |--- resources
                    |
                    |--- lib
                    |       Contains the executable JAR files for Consolidator.
                    |       |--- websubhub.consolidator.jar
                    |
                    |--- LICENSE
                    |--- README.md


Configuration
=============

The main configuration file is located at conf/Config.toml. Key configuration
options include:

Server Settings:
    - Server port and unique instance ID for distributed deployments
    - HTTPS/TLS configuration with keystore path and password
    - Example:
      [websubhub.config.server]
      port = 9000
      id = "websubhub-1"

Message Persistence (Apache Kafka):
    - Bootstrap servers (comma-separated list for high availability)
    - Producer settings (acknowledgments, retry count)
    - Consumer settings (max poll records, polling interval, graceful close)
    - SSL/TLS support (truststore-based or certificate-based)
    - Client authentication support for secure Kafka connections
    - Example:
      [websubhub.config.store.kafka]
      bootstrapServers = "localhost:9092"

State Management:
    - Consolidator URL for retrieving state snapshots
    - State events topic and consumer ID for state synchronization
    - Example:
      [websubhub.config.state.snapshot]
      url = "http://localhost:10001"

Delivery Configuration:
    - Timeout settings for content delivery to subscribers
    - Retry configuration (count, interval, backoff factor, max wait interval)
    - HTTP status codes that trigger retry (default: 500, 502, 503)
    - Example:
      [websubhub.config.delivery.retry]
      count = 3
      interval = 3.0
      backOffFactor = 2.0

Security (Optional):
    - JWT authentication via external Identity Provider
    - JWKS endpoint URL for signature verification
    - Issuer and audience configuration for token validation
    - Scope-based authorization for operations
    - Example:
      [websubhub.config.server.auth]
      issuer = "https://localhost:9443/oauth2/token"
      audience = "websubhub"

Logging:
    - Configurable log levels (INFO, DEBUG, WARN, ERROR)
    - Example:
      [ballerina.log]
      level = "INFO"

For detailed configuration examples, refer to the online documentation at
https://wso2.github.io/docs-websubhub/


Documentation
=============

Online product documentation is available at:

    https://wso2.github.io/docs-websubhub/

Specific guides:
    Quick Start Guide:
        https://wso2.github.io/docs-websubhub/get-started/quickstart/

    External IdP Configuration:
        https://wso2.github.io/docs-websubhub/configurations/idp/

    Apache Kafka Configuration:
        https://wso2.github.io/docs-websubhub/configurations/kafka/

Additional resources:
    GitHub repository:
        https://github.com/wso2/product-integrator-websubhub

    WebSub specification (W3C):
        https://www.w3.org/TR/websub/

    Ballerina programming language:
        https://ballerina.io/


Support
=======

WSO2 Inc. offers a variety of development and production support programs,
ranging from Web-based support up through normal business hours, to premium
24x7 phone support.

For additional support information please refer to http://wso2.com/support

For more information on WSO2 Integrator: WebSubHub please visit
https://wso2.com/integration/


Known Issues
============

All known issues of WSO2 Integrator: WebSubHub are filed at:

    https://github.com/wso2/product-integrator-websubhub/issues


Issue Tracker
=============

Help us make our software better. Please submit any bug reports or feature
requests through the GitHub issue tracker:

    https://github.com/wso2/product-integrator-websubhub/issues


Crypto Notice
=============

This distribution includes cryptographic software.  The country in
which you currently reside may have restrictions on the import,
possession, use, and/or re-export to another country, of
encryption software.  BEFORE using any encryption software, please
check your country's laws, regulations and policies concerning the
import, possession, or use, and re-export of encryption software, to
see if this is permitted.  See <http://www.wassenaar.org/> for more
information.

The U.S. Government Department of Commerce, Bureau of Industry and
Security (BIS), has classified this software as Export Commodity
Control Number (ECCN) 5D002.C.1, which includes information security
software using or performing cryptographic functions with asymmetric
algorithms.  The form and manner of this Apache Software Foundation
distribution makes it eligible for export under the License Exception
ENC Technology Software Unrestricted (TSU) exception (see the BIS
Export Administration Regulations, Section 740.13) for both object
code and source code.

The following provides more details on the included cryptographic
software:

Apache Rampart   : http://ws.apache.org/rampart/
Apache WSS4J     : http://ws.apache.org/wss4j/
Apache Santuario : http://santuario.apache.org/
Bouncycastle     : http://www.bouncycastle.org/

For more information about WSO2 Integrator: WebSubHub please see
https://wso2.github.io/docs-websubhub/ or visit the GitHub repository
at https://github.com/wso2/product-integrator-websubhub

--------------------------------------------------------------------------------
(c) Copyright 2025 WSO2 LLC.
