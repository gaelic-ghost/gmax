//
//  BashShellIntegrationTests.swift
//  gmaxTests
//
//  Created by Gale Williams on 4/24/26.
//

import Foundation
@testable import gmax
import Testing

@MainActor
struct BashShellIntegrationTests {
    @Test func `environment overlay configures rcfile for bash shells`() {
        let fileManager = FileManager.default
        let rootDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: rootDirectory) }

        let overlay = BashShellIntegration.environmentOverlay(
            shellExecutable: "/bin/bash",
            baseEnvironment: ["HOME": "/tmp/original-home"],
            fileManager: fileManager,
            rootDirectory: rootDirectory,
        )

        #expect(overlay["GMAX_ORIGINAL_HOME"] == "/tmp/original-home")
        #expect(overlay["GMAX_SHELL_INTEGRATION"] == "1")
        #expect(overlay[BashShellIntegration.rcfileEnvironmentKey] == rootDirectory.appendingPathComponent("bash/gmax-bashrc").path)
    }

    @Test func `launch arguments use generated bash rcfile`() {
        let arguments = BashShellIntegration.launchArguments(
            environment: [BashShellIntegration.rcfileEnvironmentKey: "/tmp/gmax-bashrc"],
        )

        #expect(arguments == ["--rcfile", "/tmp/gmax-bashrc", "-i"])
    }

    @Test func `install writes bash rcfile and marker hooks`() throws {
        let fileManager = FileManager.default
        let rootDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: rootDirectory) }

        let rcfileURL = try BashShellIntegration.install(
            originalHomeDirectory: "/tmp/original-home",
            fileManager: fileManager,
            rootDirectory: rootDirectory,
        )

        let rcfile = try String(contentsOf: rcfileURL)

        #expect(fileManager.fileExists(atPath: rcfileURL.path))
        #expect(rcfile.contains(". /etc/profile"))
        #expect(rcfile.contains(". \"${GMAX_ORIGINAL_HOME:-/tmp/original-home}/.bash_profile\""))
        #expect(rcfile.contains(". \"${GMAX_ORIGINAL_HOME:-/tmp/original-home}/.bashrc\""))
        #expect(rcfile.contains("PROMPT_COMMAND='gmax_prompt_command'"))
        #expect(rcfile.contains("trap 'gmax_preexec_trap' DEBUG"))
        #expect(rcfile.contains("if [[ -n \"${GMAX_AT_PROMPT:-}\" ]]; then"))
        #expect(rcfile.contains("export GMAX_AT_PROMPT=1"))
        #expect(rcfile.contains("gmax() {"))
        #expect(rcfile.contains("exec /bin/bash --rcfile \"${GMAX_BASH_INTEGRATION_RCFILE}\" -i"))
        #expect(rcfile.contains("gmax_emit_osc '133;A'"))
        #expect(rcfile.contains("gmax_emit_osc '133;C'"))
        #expect(rcfile.contains("gmax_emit_osc \"133;D;${status}\""))
        #expect(rcfile.contains("gmax_emit_osc \"7;file://"))
    }

    @Test func `environment overlay stays empty for non-bash shells`() {
        let overlay = BashShellIntegration.environmentOverlay(
            shellExecutable: "/bin/zsh",
            baseEnvironment: [:],
        )

        #expect(overlay.isEmpty)
    }
}
