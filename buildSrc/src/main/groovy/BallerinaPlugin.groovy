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
import org.gradle.api.file.DuplicatesStrategy
import org.gradle.api.tasks.Exec
import org.gradle.internal.os.OperatingSystem

class BallerinaPlugin implements Plugin<Project> {
    void apply(Project project) {
        project.apply plugin: 'base'

        project.tasks.register('balBuild', Exec) {
            commandLine BalUtils.executeBalCommand('build')
        }

        project.tasks.register('balClean', Exec) {
            commandLine BalUtils.executeBalCommand('clean')
        }

        project.tasks.register('updateTomlFiles') {
            def projectVersion = project.version
            def ballerinaVersion = project.ballerinaDistributionVersion
            def workspaceDir = project.projectDir

            doLast {
                workspaceDir.listFiles()
                        .findAll { it.isDirectory() && new File(it, "Ballerina.toml").exists() }
                        .each { dir ->
                            def buildConfigDir = new File("${project.rootDir}/build-config/resources/${dir.name}")
                            if (!buildConfigDir.exists()) return

                            project.copy {
                                from(buildConfigDir) {
                                    include '**/Ballerina.toml'
                                    filter { line ->
                                        line.replace('@toml.version@', projectVersion)
                                                .replace('@ballerina.version@', ballerinaVersion)
                                    }
                                }
                                into dir
                                duplicatesStrategy = DuplicatesStrategy.INCLUDE
                            }
                        }
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
                def isWindows = OperatingSystem.current().isWindows()

                project.projectDir.listFiles()
                        .findAll { dir ->
                            dir.isDirectory() && new File(dir, "Ballerina.toml").exists()
                        }
                        .each { dir ->

                            def ballerinaToml = dir.toPath().resolve("Ballerina.toml")
                            def dependenciesToml = dir.toPath().resolve("Dependencies.toml")
                            def commitMessage = "[Automated] Updating ${dir.name} package versions"

                            def gitCommand = isWindows
                                    ? "git add \"${ballerinaToml}\" \"${dependenciesToml}\" && git commit -m \"${commitMessage}\""
                                    : "git add \"${ballerinaToml}\" \"${dependenciesToml}\" && git commit -m '${commitMessage}'"

                            project.exec {
                                workingDir project.projectDir
                                ignoreExitValue true
                                commandLine(
                                        isWindows ? 'cmd' : 'sh',
                                        isWindows ? '/c' : '-c',
                                        gitCommand
                                )
                            }
                        }
            }
        }
    }
}
