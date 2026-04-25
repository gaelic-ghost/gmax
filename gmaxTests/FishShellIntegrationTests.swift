//
//  FishShellIntegrationTests.swift
//  gmaxTests
//
//  Created by Gale Williams on 4/24/26.
//

import Foundation
@testable import gmax
import Testing

@MainActor
struct FishShellIntegrationTests {
    @Test func `environment overlay configures xdg home for fish shells`() {
        let fileManager = FileManager.default
        let rootDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: rootDirectory) }

        let overlay = FishShellIntegration.environmentOverlay(
            shellExecutable: "/opt/homebrew/bin/fish",
            baseEnvironment: ["XDG_CONFIG_HOME": "/tmp/original-xdg"],
            fileManager: fileManager,
            rootDirectory: rootDirectory,
        )

        #expect(overlay["GMAX_ORIGINAL_XDG_CONFIG_HOME"] == "/tmp/original-xdg")
        #expect(overlay["GMAX_SHELL_INTEGRATION"] == "1")
        #expect(overlay["XDG_CONFIG_HOME"] == rootDirectory.appendingPathComponent("fish/xdg").path)
    }

    @Test func `install writes fish config and marker hooks`() throws {
        let fileManager = FileManager.default
        let rootDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: rootDirectory) }

        let wrapperConfigHome = try FishShellIntegration.install(
            originalXDGConfigHome: "/tmp/original-xdg",
            fileManager: fileManager,
            rootDirectory: rootDirectory,
        )

        let configScript = try String(
            contentsOf: wrapperConfigHome.appendingPathComponent("fish/config.fish"),
        )
        let integrationScript = try String(
            contentsOf: wrapperConfigHome.appendingPathComponent("fish/gmax-shell-integration.fish"),
        )

        #expect(configScript.contains("set gmax_original_xdg_config_home \"/tmp/original-xdg\""))
        #expect(configScript.contains("for file in $gmax_original_fish_config_dir/conf.d/*.fish"))
        #expect(configScript.contains("source \"$gmax_original_fish_config_dir/config.fish\""))
        #expect(configScript.contains("source (status dirname)/gmax-shell-integration.fish"))
        #expect(integrationScript.contains("function gmax"))
        #expect(integrationScript.contains("exec /bin/bash --rcfile \"$GMAX_BASH_INTEGRATION_RCFILE\" -i $argv"))
        #expect(integrationScript.contains("function gmax_prompt_started --on-event fish_prompt"))
        #expect(integrationScript.contains("function gmax_command_started --on-event fish_preexec"))
        #expect(integrationScript.contains("function gmax_command_finished --on-event fish_postexec"))
        #expect(integrationScript.contains("function gmax_command_errored --on-event fish_posterror"))
        #expect(integrationScript.contains("function gmax_pwd_changed --on-variable PWD"))
        #expect(integrationScript.contains("gmax_emit_osc '133;A'"))
        #expect(integrationScript.contains("gmax_emit_osc '133;C'"))
        #expect(integrationScript.contains("gmax_emit_osc \"133;D;$status\""))
        #expect(integrationScript.contains("gmax_emit_osc \"7;file://localhost$absolute_path\""))
    }

    @Test func `environment overlay stays empty for non-fish shells`() {
        let overlay = FishShellIntegration.environmentOverlay(
            shellExecutable: "/bin/zsh",
            baseEnvironment: [:],
        )

        #expect(overlay.isEmpty)
    }
}
