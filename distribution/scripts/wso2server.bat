@echo off
rem ---------------------------------------------------------------------------
rem Copyright (c) 2025, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
rem
rem WSO2 Inc. licenses this file to you under the Apache License,
rem Version 2.0 (the "License"); you may not use this file except
rem in compliance with the License.
rem You may obtain a copy of the License at
rem
rem     http://www.apache.org/licenses/LICENSE-2.0
rem
rem Unless required by applicable law or agreed to in writing,
rem software distributed under the License is distributed on an
rem "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
rem KIND, either express or implied. See the License for the
rem specific language governing permissions and limitations
rem under the License.
rem ---------------------------------------------------------------------------

rem Ballerina API Server startup script
rem This script starts the Ballerina API server

rem Get standard environment variables
set "PRGDIR=%~dp0"
for %%F in ("%PRGDIR%..") do set "BASE_DIR=%%~fF"
set "LIB_DIR=%BASE_DIR%\lib"
set "CONF_DIR=%BASE_DIR%\conf"

rem Validate Ballerina installation
where bal >nul 2>nul
if %errorlevel% neq 0 (
    echo Error: 'bal' command could not be found in your PATH.
    echo Please install Ballerina and ensure it is in your PATH.
    exit /b 1
)
set "BAL_CMD=bal"

rem Find the JAR file
set "JAR_FILE="
for /f "delims=" %%F in ('dir /b /s "%LIB_DIR%\*.jar"') do (
    set "JAR_FILE=%%F"
    goto jar_found
)

:jar_found
if not defined JAR_FILE (
    echo Error: No JAR file found in %LIB_DIR%
    exit /b 1
)

echo Starting API Server...
echo JAR: %JAR_FILE%
echo Config: %CONF_DIR%\Config.toml

rem Run the Ballerina module with configuration
set "BAL_CONFIG_FILES=%CONF_DIR%\Config.toml"
"%BAL_CMD%" run "%JAR_FILE%"
