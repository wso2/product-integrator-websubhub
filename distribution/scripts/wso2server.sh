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

# WSO2 Integrator: WebSubHub startup script
# This script starts, stops, and restarts the WSO2 Integrator: WebSubHub using Java
# Usage: apiserver.sh {start|stop|restart|status}

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
PID_FILE="$BASE_DIR/apiserver.pid"

# Validate Java installation
JAVA_CMD="java"
if [ -n "$JAVA_HOME" ]; then
    JAVA_CMD="$JAVA_HOME/bin/java"
fi

which $JAVA_CMD >/dev/null 2>&1 || {
    echo "Error: 'java' command could not be found in your PATH."
    echo "Please install Java and ensure it is in your PATH or set JAVA_HOME."
    exit 1
}

# Set default JVM options if not already set
if [ -z "$JAVA_OPTS" ]; then
    JAVA_OPTS="-Xms256m -Xmx1024m"
fi

# Find the JAR file
JAR_FILE=$(find "$LIB_DIR" -name "*.jar" | head -n 1)

if [ -z "$JAR_FILE" ]; then
    echo "Error: No JAR file found in $LIB_DIR"
    exit 1
fi

# Function to start the server
startServer() {
    if [ -e "$PID_FILE" ]; then
        if ps -p $(cat "$PID_FILE") > /dev/null; then
            echo "WSO2 Integrator: WebSubHub is already running as process $(cat $PID_FILE)"
            exit 0
        fi
    fi
    
    echo "Starting WSO2 WSO2 Integrator: WebSubHub..."
    
    # Start the server in background with nohup
    nohup env BAL_CONFIG_FILES="$CONF_DIR/Config.toml" "$JAVA_CMD" $JAVA_OPTS -jar "$JAR_FILE" > /dev/null 2>&1 &
    PID=$!
    echo $PID > "$PID_FILE"
    
    # Check if process started successfully
    sleep 2
    if ps -p $PID > /dev/null; then
        echo "WSO2 Integrator: WebSubHub started successfully with process ID $PID"
    else
        echo "Failed to start WSO2 Integrator: WebSubHub"
        rm -f "$PID_FILE"
        exit 1
    fi
}

# Function to stop the server
stopServer() {
    if [ ! -e "$PID_FILE" ]; then
        echo "WSO2 Integrator: WebSubHub is not running"
        return
    fi
    
    PID=$(cat "$PID_FILE")
    if ! ps -p $PID > /dev/null; then
        echo "WSO2 Integrator: WebSubHub is not running"
        rm -f "$PID_FILE"
        return
    fi
    
    echo "Stopping WSO2 Integrator: WebSubHub (PID: $PID)..."
    kill -TERM $PID
    
    # Wait for graceful shutdown
    for i in {1..30}; do
        if ! ps -p $PID > /dev/null; then
            echo "WSO2 Integrator: WebSubHub stopped successfully"
            rm -f "$PID_FILE"
            return
        fi
        sleep 1
    done
    
    # Force kill if still running
    echo "Forcing WSO2 Integrator: WebSubHub shutdown..."
    kill -KILL $PID > /dev/null 2>&1
    rm -f "$PID_FILE"
    echo "WSO2 Integrator: WebSubHub stopped"
}

# Function to restart the server
restartServer() {
    echo "Restarting WSO2 Integrator: WebSubHub..."
    stopServer
    sleep 3
    startServer
}

# Parse command line argument
if [ "$1" = "start" ]; then
    startServer
elif [ "$1" = "stop" ]; then
    stopServer
elif [ "$1" = "restart" ]; then
    restartServer
elif [ "$1" = "status" ]; then
    if [ -e "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p $PID > /dev/null; then
            echo "WSO2 Integrator: WebSubHub is running (PID: $PID)"
        else
            echo "WSO2 Integrator: WebSubHub is not running"
            rm -f "$PID_FILE"
        fi
    else
        echo "WSO2 Integrator: WebSubHub is not running"
    fi
else
    # Default behavior - start in foreground
    if [ -z "$1" ]; then
        echo "Starting WSO2 Integrator: WebSubHub in foreground..."
        echo "Using JAVA_CMD: $JAVA_CMD"
        echo "Using JAVA_OPTS: $JAVA_OPTS"
        echo "JAR: $JAR_FILE"
        echo "Config: $CONF_DIR/Config.toml"
        exec env BAL_CONFIG_FILES="$CONF_DIR/Config.toml" "$JAVA_CMD" $JAVA_OPTS -jar "$JAR_FILE"
    else
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
    fi
fi
