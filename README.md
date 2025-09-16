<img src="https://wso2.cachefly.net/wso2/sites/all/image_resources/wso2-branding-logos/wso2-logo-orange.png" alt="WSO2 logo" width=30% height=30% />

# WSO2 Integrator: WebSubHub

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Join the community on Discord](https://img.shields.io/badge/Join%20us%20on%20Discord-wso2-orange)](https://discord.com/invite/wso2)
[![X](https://img.shields.io/twitter/follow/wso2.svg?style=social&label=Follow%20Us)](https://twitter.com/intent/follow?screen_name=wso2)

**WSO2 Integrator: WebSubHub** is a [WebSub](https://www.w3.org/TR/websub/) compliant hub implementation built on [Ballerina](https://ballerina.io/). It enables organizations to adopt event-driven architectures by supporting publish-subscribe communication over HTTP(S). WebSubHub can be configured with the message broker of your choice as its persistence layer, making it ideal for scalable, real-time event distribution across services, applications, and systems.

## Why `WSO2 Integrator: WebSubHub`?

`WSO2 Integrator: WebSubHub` simplifies the adoption of event-driven architectures by enabling organizations to build standardized publish–subscribe communication flows over HTTP(S).

* **Pluggable messaging backend** – Integrates with the messaging broker or persistence layer of your choice for scalability and fault tolerance.
* **Real-time event distribution** – Pushes events instantly to subscribers, enabling responsive and dynamic applications.
* **Enterprise-ready** – Ideal for building event-driven microservice-based architectures across services, systems, and organizations.
* **Cloud-native deployment** – Easily deployable in containerized and cloud environments to support modern infrastructure needs.

## Contribute to `WSO2 Integrator: WebSubHub`

If you are planning to contribute to the development efforts of `WSO2 Integrator: WebSubHub`, you can do so by checking out the latest development version. The `main` branch holds the latest unreleased source code.

### Prerequisites

* Java SE Development Kit (JDK) version 21.
  * [Oracle](https://www.oracle.com/java/technologies/downloads/)
  * [OpenJDK](https://adoptium.net/)
* [Ballerina SwanLake 2201.12.8](https://ballerina.io/downloads/)

### Build from the source

Please follow the steps below to build `WSO2 Integrator: WebSubHub` from the source code.

1. Clone or download the source code from this repository (https://github.com/wso2/product-integrator-websubhub).

2. Run the Gradle build command from the root directory of the repository.

  ```sh
  ./gradlew clean build
  ```

3. The generated distribution artifacts can be found at `distribution/build/distributions` directory.

## Report product issues

### Open an issue

Help us make our software better! Submit any bug reports or feature requests through [`WSO2 Integrator: WebSubHub` GitHub](https://github.com/wso2/product-integrator-websubhub) repo.

### Report security issues

Please **do not** report security issues via GitHub issues. Instead, follow the [WSO2 Security Vulnerability Reporting Guidelines](https://security.docs.wso2.com/en/latest/security-reporting/vulnerability-reporting-guidelines/).

## Join the community!

- Join the conversation on [Discord](https://discord.gg/wso2).
- Learn more by reading articles from our [library](https://wso2.com/library/?area=integration).

## Get commercial support

You can take advantage of a WSO2 on-prem product subscription for the full range of software product benefits needed in your enterprise, like expert support, continuous product updates, vulnerability monitoring, and access to the licensed distribution for commercial use.

To learn more, check [WSO2 Subscription](https://wso2.com/subscription/).

## Can you fill out this survey?

WSO2 wants to learn more about our open source software (OSS) community and your communication preferences to serve you better. In addition, we may reach out to a small number of respondents to ask additional questions and offer a small gift.

The survey is available at: [WSO2 Open Source Software Communication Survey](https://forms.gle/h5q4M3K7vyXba3bK6)

--------------------------------------------------------------------------------
(c) Copyright 2012 - 2025 WSO2 Inc.
