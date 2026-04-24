//
//  ZshShellIntegrationTests.swift
//  gmaxTests
//
//  Created by Gale Williams on 4/24/26.
//

import Foundation
@testable import gmax
import Testing

@MainActor
struct ZshShellIntegrationTests {
    @Test func `environment overlay configures zdotdir for zsh shells`() {
        let fileManager = FileManager.default
        let rootDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: rootDirectory) }

        let overlay = ZshShellIntegration.environmentOverlay(
            shellExecutable: "/bin/zsh",
            baseEnvironment: ["ZDOTDIR": "/tmp/original-zdotdir"],
            fileManager: fileManager,
            rootDirectory: rootDirectory,
        )

        #expect(overlay["GMAX_ORIGINAL_ZDOTDIR"] == "/tmp/original-zdotdir")
        #expect(overlay["GMAX_SHELL_INTEGRATION"] == "1")
        #expect(overlay["ZDOTDIR"] == rootDirectory.appendingPathComponent("zsh", isDirectory: true).path)
    }

    @Test func `install writes zsh wrapper files and shell integration snippet`() throws {
        let fileManager = FileManager.default
        let rootDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: rootDirectory) }

        let wrapperDirectory = try ZshShellIntegration.install(
            originalZdotdir: "/tmp/original-zdotdir",
            fileManager: fileManager,
            rootDirectory: rootDirectory,
        )

        let zshrc = try String(contentsOf: wrapperDirectory.appendingPathComponent(".zshrc"))
        let integrationScript = try String(
            contentsOf: wrapperDirectory.appendingPathComponent("gmax-shell-integration.zsh"),
        )

        #expect(fileManager.fileExists(atPath: wrapperDirectory.appendingPathComponent(".zshenv").path))
        #expect(fileManager.fileExists(atPath: wrapperDirectory.appendingPathComponent(".zprofile").path))
        #expect(fileManager.fileExists(atPath: wrapperDirectory.appendingPathComponent(".zlogin").path))
        #expect(zshrc.contains("typeset -g GMAX_SHELL_INTEGRATION_WRAPPER_ZDOTDIR=\"${ZDOTDIR:-}\""))
        #expect(zshrc.contains("source \"${GMAX_SHELL_INTEGRATION_WRAPPER_ZDOTDIR}/gmax-shell-integration.zsh\""))
        #expect(integrationScript.contains("gmax_emit_osc '133;A'"))
        #expect(integrationScript.contains("gmax_emit_osc '133;C'"))
        #expect(integrationScript.contains("gmax_emit_osc \"133;D;${status}\""))
        #expect(integrationScript.contains("gmax_emit_osc \"7;file://"))
    }

    @Test func `wrapper zshrc sources integration from stable wrapper path`() throws {
        let fileManager = FileManager.default
        let rootDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: rootDirectory) }

        let wrapperDirectory = try ZshShellIntegration.install(
            originalZdotdir: "/tmp/original-zdotdir",
            fileManager: fileManager,
            rootDirectory: rootDirectory,
        )

        let zshrc = try String(contentsOf: wrapperDirectory.appendingPathComponent(".zshrc"))

        #expect(!zshrc.contains("source \"${ZDOTDIR}/gmax-shell-integration.zsh\""))
        #expect(zshrc.contains("GMAX_SHELL_INTEGRATION_WRAPPER_ZDOTDIR"))
    }

    @Test func `environment overlay stays empty for non-zsh shells`() {
        let overlay = ZshShellIntegration.environmentOverlay(
            shellExecutable: "/bin/bash",
            baseEnvironment: [:],
        )

        #expect(overlay.isEmpty)
    }
}
