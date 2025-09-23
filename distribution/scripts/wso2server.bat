@REM ---------------------------------------------------------------------------
@REM Copyright (c) 2025, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
@REM
@REM WSO2 Inc. licenses this file to you under the Apache License,
@REM Version 2.0 (the "License"); you may not use this file except
@REM in compliance with the License.
@REM You may obtain a copy of the License at
@REM
@REM     http://www.apache.org/licenses/LICENSE-2.0
@REM
@REM Unless required by applicable law or agreed to in writing,
@REM software distributed under the License is distributed on an
@REM "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
@REM KIND, either express or implied. See the License for the
@REM specific language governing permissions and limitations
@REM under the License.
@REM ---------------------------------------------------------------------------

@echo off
rem WSO2 Integrator: WebSubHub startup script
rem This script starts, stops, and restarts the WSO2 Integrator: WebSubHub using Java
rem Usage: apiserver.bat {start|stop|restart|status}

rem Get standard environment variables
set "PRGDIR=%~dp0"
for %%F in ("%PRGDIR%..") do set "BASE_DIR=%%~fF"
set "LIB_DIR=%BASE_DIR%\lib"
set "CONF_DIR=%BASE_DIR%\conf"
set "PID_FILE=%BASE_DIR%\apiserver.pid"

rem Validate Java installation
set "JAVA_CMD=java"
if defined JAVA_HOME (
    set "JAVA_CMD=%JAVA_HOME%\bin\java.exe"
)

where "%JAVA_CMD%" >nul 2>nul
if %errorlevel% neq 0 (
    echo Error: 'java' command could not be found in your PATH.
    echo Please install Java and ensure it is in your PATH or set JAVA_HOME.
    exit /b 1
)

rem Set default JVM options if not already set
if not defined JAVA_OPTS (
    set "JAVA_OPTS=-Xms256m -Xmx1024m"
)

rem Set default config file path if not already set
if not defined BAL_CONFIG_FILES (
    set "BAL_CONFIG_FILES=%CONF_DIR%\Config.toml"
)

rem Find the JAR file
set "JAR_FILE="
for /f "delims=" %%F in ('dir /b /s "%LIB_DIR%\*.jar" 2^>nul') do (
    set "JAR_FILE=%%F"
    goto jar_found
)

:jar_found
if not defined JAR_FILE (
    echo Error: No JAR file found in %LIB_DIR%
    exit /b 1
)

rem Parse command line arguments
if "%~1"=="start" goto startServer
if "%~1"=="stop" goto stopServer
if "%~1"=="restart" goto restartServer
if "%~1"=="status" goto statusServer
if "%~1"=="" goto runForeground
goto usage

:startServer
if exist "%PID_FILE%" (
    for /f %%p in ('type "%PID_FILE%"') do (
        tasklist /FI "PID eq %%p" 2>nul | find /I "java.exe" >nul
        if not errorlevel 1 (
            echo WSO2 Integrator: WebSubHub is already running as process %%p
            exit /b 0
        )
    )
)

echo Starting WSO2 WSO2 Integrator: WebSubHub...
start /B "" "%JAVA_CMD%" %JAVA_OPTS% -jar "%JAR_FILE%"

rem Get the PID of the started process
for /f "tokens=2" %%i in ('tasklist /FI "IMAGENAME eq java.exe" /FO CSV ^| find /V "PID" ^| find /V """PID"""') do (
    set "SERVER_PID=%%~i"
)

if defined SERVER_PID (
    echo %SERVER_PID% > "%PID_FILE%"
    echo WSO2 Integrator: WebSubHub started successfully with process ID %SERVER_PID%
) else (
    echo Failed to start WSO2 Integrator: WebSubHub
    exit /b 1
)
goto end

:stopServer
if not exist "%PID_FILE%" (
    echo WSO2 Integrator: WebSubHub is not running
    goto end
)

for /f %%p in ('type "%PID_FILE%"') do set "SERVER_PID=%%p"
tasklist /FI "PID eq %SERVER_PID%" 2>nul | find /I "java.exe" >nul
if errorlevel 1 (
    echo WSO2 Integrator: WebSubHub is not running
    del "%PID_FILE%" 2>nul
    goto end
)

echo Stopping WSO2 Integrator: WebSubHub ^(PID: %SERVER_PID%^)...
taskkill /PID %SERVER_PID% >nul 2>nul
timeout /T 5 /NOBREAK >nul

rem Check if process stopped
tasklist /FI "PID eq %SERVER_PID%" 2>nul | find /I "java.exe" >nul
if not errorlevel 1 (
    echo Forcing WSO2 Integrator: WebSubHub shutdown...
    taskkill /F /PID %SERVER_PID% >nul 2>nul
)

del "%PID_FILE%" 2>nul
echo WSO2 Integrator: WebSubHub stopped
goto end

:restartServer
echo Restarting WSO2 Integrator: WebSubHub...
call :stopServer
timeout /T 3 /NOBREAK >nul
call :startServer
goto end

:statusServer
if exist "%PID_FILE%" (
    for /f %%p in ('type "%PID_FILE%"') do (
        set "SERVER_PID=%%p"
        tasklist /FI "PID eq %%p" 2>nul | find /I "java.exe" >nul
        if not errorlevel 1 (
            echo WSO2 Integrator: WebSubHub is running ^(PID: %%p^)
        ) else (
            echo WSO2 Integrator: WebSubHub is not running
            del "%PID_FILE%" 2>nul
        )
    )
) else (
    echo WSO2 Integrator: WebSubHub is not running
)
goto end

:runForeground
echo Starting WSO2 WSO2 Integrator: WebSubHub in foreground...
echo Using JAVA_CMD: %JAVA_CMD%
echo Using JAVA_OPTS: %JAVA_OPTS%
echo JAR: %JAR_FILE%
echo Config: %BAL_CONFIG_FILES%
"%JAVA_CMD%" %JAVA_OPTS% -jar "%JAR_FILE%"
goto end

:usage
echo Usage: %0 {start^|stop^|restart^|status}
exit /b 1

:end
