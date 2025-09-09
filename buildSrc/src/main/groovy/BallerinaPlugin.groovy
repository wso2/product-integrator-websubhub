/*
* Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com)
*
* WSO2 LLC. licenses this file to you under the Apache License,
* Version 2.0 (the "License"); you may not use this file except
* in compliance with the License.
* You may obtain a copy of the License at
*
*    http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing,
* software distributed under the License is distributed on an
* "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
* KIND, either express or implied. See the License for the
* specific language governing permissions and limitations
* under the License.
*/

import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.tasks.Exec
import org.gradle.api.tasks.Copy
import org.gradle.internal.os.OperatingSystem
import BalUtils

class BallerinaPlugin implements Plugin<Project> {
    void apply(Project project) {
        project.apply plugin: 'base'

        project.tasks.register('balBuild', Exec) {
            commandLine BalUtils.executeBalCommand('build')
        }

        project.tasks.register('balClean', Exec) {
            commandLine BalUtils.executeBalCommand('clean')
        }

        project.tasks.register('updateTomlFiles', Copy) {
            def componentName = project.name
            def buildConfigDir = new File("${project.rootDir}/build-config/resources/${componentName}")
            def componentDirectory = project.projectDir
            def projectVersion = project.version
            from(buildConfigDir) {
                include '**/*.toml'
                filter {
                    line ->
                    line.replace('@toml.version@', projectVersion)
                }
            }
            into componentDirectory

            inputs.files project.fileTree(buildConfigDir)
            inputs.property('projectVersion', projectVersion)
            outputs.files project.fileTree(componentDirectory) {
                include '**/*.toml'
            }
        }

        project.tasks.named('build') {
            dependsOn project.rootProject.tasks.named('verifyLocalBalVersion')
            dependsOn project.tasks.named('updateTomlFiles')
            dependsOn project.tasks.named('balBuild')
            dependsOn project.tasks.named('commitTomlFiles')

            it.mustRunAfter project.rootProject.tasks.named('verifyLocalBalVersion').get()
            it.mustRunAfter project.tasks.named('updateTomlFiles').get()
        }

        project.tasks.named('clean') {
            dependsOn project.tasks.named('balClean')
        }

        project.tasks.register('commitTomlFiles') {
            dependsOn project.tasks.named('updateTomlFiles')
            doLast {
                project.exec {
                    workingDir project.projectDir
                    ignoreExitValue true
                    if (OperatingSystem.current().isWindows()) {
                        commandLine 'cmd', '/c', "git add Ballerina.toml Cloud.toml Dependencies.toml && git commit -m \"[Automated] Updating package versions\""
                    } else {
                        commandLine 'sh', '-c', "git add Ballerina.toml Cloud.toml Dependencies.toml && git commit -m '[Automated] Updating package versions'"
                    }
                }
            }
        }
    }
}
