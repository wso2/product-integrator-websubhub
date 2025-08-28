#!/bin/bash
# ---------------------------------------------------------------------------
# Copyright (c) 2025, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
#
# WSO2 Inc. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied. See the License for the
# specific language governing permissions and limitations
# under the License.
# ---------------------------------------------------------------------------

# Ballerina API Server startup script
# This script starts the Ballerina API server

# resolve links - $0 may be a softlink
PRG="$0"

while [ -h "$PRG" ]; do
    ls=`ls -ld "$PRG"`
    link=`expr "$ls" : '.*-> \(.*\)`
    if expr "$link" : '.*/.*' > /dev/null; then
        PRG="$link"
    else
        PRG=`dirname "$PRG"`/"$link"
    fi
done

# Get standard environment variables
PRGDIR=`dirname "$PRG"`
BASE_DIR=`cd "$PRGDIR/.." ; pwd`
LIB_DIR="$BASE_DIR/lib"
CONF_DIR="$BASE_DIR/conf"

# Validate Ballerina installation
BAL_CMD="bal"
if ! command -v "$BAL_CMD" >/dev/null 2>&1; then
    echo "Error: '$BAL_CMD' command could not be found in your PATH."
    echo "Please install Ballerina and ensure it is in your PATH."
    exit 1
fi

# Find the JAR file
JAR_FILE=$(find "$LIB_DIR" -name "*.jar" | head -n 1)

if [ -z "$JAR_FILE" ]; then
    echo "Error: No JAR file found in $LIB_DIR"
    exit 1
fi

echo "Starting WSO2 Server..."
echo "JAR: $JAR_FILE"
echo "Config: $CONF_DIR/Config.toml"

# Run the Ballerina module with configuration
exec env BAL_CONFIG_FILES="$CONF_DIR/Config.toml" "$BAL_CMD" run "$JAR_FILE"
