//
//  TerminalLaunchContextBuilderTests.swift
//  gmaxTests
//
//  Created by Gale Williams on 4/24/26.
//

import Foundation
@testable import gmax
import Testing

@MainActor
struct TerminalLaunchContextBuilderTests {
    @Test func `shell integration plan uses login mode for zsh`() {
        let plan = TerminalLaunchContextBuilder.makeShellIntegrationPlan(
            shellExecutable: "/bin/zsh",
            baseEnvironment: ["ZDOTDIR": "/tmp/original-zdotdir"],
            fileManager: .default,
        )

        #expect(plan.arguments == ["-l"])
        #expect(plan.environment["ZDOTDIR"] != nil)
    }

    @Test func `live builder base environment carries shell handoff wrappers`() {
        let fileManager = FileManager.default
        let processInfo = ProcessInfo.processInfo

        let builder = TerminalLaunchContextBuilder.live(
            processInfo: processInfo,
            fileManager: fileManager,
        )

        #expect(builder.baseEnvironment[BashShellIntegration.rcfileEnvironmentKey] != nil)
        #expect(builder.baseEnvironment[ZshShellIntegration.wrapperZdotdirEnvironmentKey] != nil)
        #expect(builder.baseEnvironment[FishShellIntegration.wrapperConfigHomeEnvironmentKey] != nil)
    }

    @Test func `shell integration plan uses rcfile path for bash`() throws {
        let plan = TerminalLaunchContextBuilder.makeShellIntegrationPlan(
            shellExecutable: "/bin/bash",
            baseEnvironment: ["HOME": "/tmp/original-home"],
            fileManager: .default,
        )

        let rcfilePath = try #require(plan.environment[BashShellIntegration.rcfileEnvironmentKey])

        #expect(plan.arguments == ["--rcfile", rcfilePath, "-i"])
    }

    @Test func `shell integration plan keeps login mode for fish`() {
        let plan = TerminalLaunchContextBuilder.makeShellIntegrationPlan(
            shellExecutable: "/opt/homebrew/bin/fish",
            baseEnvironment: ["XDG_CONFIG_HOME": "/tmp/original-xdg"],
            fileManager: .default,
        )

        #expect(plan.arguments == ["-l"])
        #expect(plan.environment["XDG_CONFIG_HOME"] != nil)
    }

    @Test func `shell integration plan falls back for unsupported shells`() {
        let plan = TerminalLaunchContextBuilder.makeShellIntegrationPlan(
            shellExecutable: "/bin/sh",
            baseEnvironment: [:],
            fileManager: .default,
        )

        #expect(plan.arguments == ["-l"])
        #expect(plan.environment.isEmpty)
    }
}
