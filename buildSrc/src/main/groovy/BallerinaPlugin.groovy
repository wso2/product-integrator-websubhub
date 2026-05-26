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

        // Applies vendored patches to third-party Ballerina packages that have not yet
        // shipped the required fixes upstream.  Each patch lives under:
        //   build-config/patches/<org>-<package>/<version>/
        // and is overlaid onto the corresponding bala in ~/.ballerina/ before the build.
        //
        // Current patches:
        //   xlibb-solace/0.4.1 — adds `dmqEligible` field to the Message record and sets
        //       jcsmpMessage.setDMQEligible() in the native JAR.
        //       Remove once xlibb/solace 0.4.2+ (or equivalent) is published to central.
        project.tasks.register('applyThirdPartyPatches') {
            def patchesRoot = new File("${project.rootDir}/build-config/patches")

            onlyIf { patchesRoot.exists() && patchesRoot.listFiles()?.any { it.isDirectory() } }

            doLast {
                def balHome = "${System.getProperty('user.home')}/.ballerina"
                def ballerinaVersion = project.ballerinaDistributionVersion

                patchesRoot.listFiles()?.findAll { it.isDirectory() }?.each { patchPkg ->
                    // patchPkg.name format: "<org>-<package>" e.g. "xlibb-solace"
                    def parts = patchPkg.name.split('-', 2)
                    if (parts.length != 2) {
                        println "Skipping patch directory with unexpected name: ${patchPkg.name}"
                        return
                    }
                    def org = parts[0]
                    def pkg = parts[1]

                    patchPkg.listFiles()?.findAll { it.isDirectory() }?.each { versionDir ->
                        def version = versionDir.name
                        def balaTarget = "${balHome}/repositories/central.ballerina.io/bala/${org}/${pkg}/${version}/java21"
                        def cacheBase = "${balHome}/repositories/central.ballerina.io/cache-${ballerinaVersion}/${org}/${pkg}/${version}"

                        // Pre-pull the package so the bala exists in cache before we overwrite files.
                        // Ignore exit value — the package may already be cached.
                        println "Pulling ${org}/${pkg}:${version} from Ballerina Central..."
                        project.exec {
                            commandLine BalUtils.executeBalCommand("pull ${org}/${pkg}:${version}")
                            ignoreExitValue true
                        }

                        println "Overlaying patch files for ${org}/${pkg}:${version}..."
                        project.copy {
                            from versionDir
                            into balaTarget
                            duplicatesStrategy = DuplicatesStrategy.INCLUDE
                        }

                        // Clear compiled caches so Ballerina picks up the patched sources/JAR.
                        [
                            new File("${cacheBase}/bir/solace.bir"),
                            new File("${cacheBase}/java21/xlibb-solace-${version}.jar")
                        ].each { f ->
                            if (f.exists()) {
                                f.delete()
                                println "Cleared cache: ${f}"
                            }
                        }
                        println "Patch applied: ${org}/${pkg}:${version}"
                    }
                }
            }
        }

        project.tasks.named('balBuild') {
            dependsOn project.tasks.named('applyThirdPartyPatches')
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
