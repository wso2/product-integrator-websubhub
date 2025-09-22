# ---------------------------------------------------------------------------
# Copyright (c) 2025, WSO2 LLC. (http://www.wso2.org).
#
# WSO2 LLC. licenses this file to you under the Apache License, 
# Version 2.0 (the "License"); you may not use this file except 
# in compliance with the License. You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an "AS IS" BASIS, 
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
# See the License for the specific language governing permissions and 
# limitations under the License.
# ---------------------------------------------------------------------------

# ---------- Build stage ----------
ARG BASE_IMAGE_DIGEST=sha256:de18608d022b1835259f2c488ac7d936735a6397ab0afdf9a508f620d75bcb3a
FROM ballerina/jvm-runtime@${BASE_IMAGE_DIGEST} AS build

# Install required tools for build stage
RUN apk add --no-cache \
    bash \
    unzip

# Copy and unpack the server distribution
ARG SERVER_NAME=wso2websubhub
ARG SERVER_VERSION=0.1.0-SNAPSHOT
ARG SERVER=${SERVER_NAME}-${SERVER_VERSION}
ARG SERVER_DIST_PATH=../../../../distribution/build/distributions

WORKDIR /home/wso2
COPY ${SERVER_DIST_PATH}/${SERVER}.zip .
RUN unzip ${SERVER}.zip -d ${SERVER} \
    && mv ${SERVER}/${SERVER}/* ${SERVER}/ \
    && rm -rf ${SERVER}.zip ${SERVER}/${SERVER}

# ---------- Runtime stage ----------
ARG BASE_IMAGE_DIGEST=sha256:de18608d022b1835259f2c488ac7d936735a6397ab0afdf9a508f620d75bcb3a
FROM ballerina/jvm-runtime@${BASE_IMAGE_DIGEST}

LABEL maintainer="WSO2 Docker Maintainers <dev@wso2.org>"

# User & group setup
ARG USER=wso2
ARG USER_ID=10001
ARG USER_GROUP=wso2
ARG USER_GROUP_ID=10001
ARG USER_HOME=/home/${USER}
ARG MOTD='printf "\nWelcome to WSO2 Docker Resources\n---------------------------------\nThis container runs a WSO2 product under Apache License 2.0.\nMore info: http://www.apache.org/licenses/LICENSE-2.0.\n"'

# Create group and user
RUN addgroup -g ${USER_GROUP_ID} ${USER_GROUP} \
    && adduser -D -u ${USER_ID} -G ${USER_GROUP} -h ${USER_HOME} ${USER} \
    && echo "${MOTD}" > /etc/profile.d/motd.sh

# Install minimal runtime dependencies
RUN apk add --no-cache \
    bash \
    gzip

# Copy server
ARG SERVER_NAME=websubhub
ARG SERVER_VERSION=0.1.0-SNAPSHOT
ARG SERVER=${SERVER_NAME}-${SERVER_VERSION}
ARG SERVER_HOME=${USER_HOME}/${SERVER}
COPY --from=build --chown=${USER_ID}:${USER_GROUP_ID} /home/wso2/${SERVER} ${SERVER_HOME}

ENV SERVER_HOME=${SERVER_HOME}
WORKDIR ${SERVER_HOME}

# Switch to non-root user
USER ${USER_ID}:${USER_GROUP_ID}

# Start the server
CMD ["bin/wso2server.sh"]
