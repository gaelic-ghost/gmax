//
//  WorkspacePersistenceProfileTests.swift
//  gmaxTests
//
//  Created by Codex on 4/15/26.
//

import Foundation
@testable import gmax
import Testing

struct WorkspacePersistenceProfileTests {
    @Test func `background save interval default and normalization stay stable`() {
        #expect(WorkspacePersistenceDefaults.defaultBackgroundSaveIntervalMinutes == 5)
        #expect(WorkspacePersistenceDefaults.normalizedBackgroundSaveIntervalMinutes(0) == 1)
        #expect(WorkspacePersistenceDefaults.normalizedBackgroundSaveIntervalMinutes(5) == 5)
    }

    @Test func `debug build defaults to debug store when no environment overrides exist`() {
#if DEBUG
        let processInfo = ProcessInfoStub(environment: [:])
        #expect(WorkspacePersistenceProfile.appDefault(processInfo: processInfo) == .debugOnDisk)
#endif
    }

    @Test func `explicit persistence profile environment override wins`() {
        let processInfo = ProcessInfoStub(
            environment: [WorkspacePersistenceProfile.environmentKey: WorkspacePersistenceProfile.productionOnDisk.rawValue],
        )

        #expect(WorkspacePersistenceProfile.appDefault(processInfo: processInfo) == .productionOnDisk)
    }

    @Test func `ui test reset environment selects UI test store when no explicit profile exists`() {
        let processInfo = ProcessInfoStub(
            environment: [WorkspacePersistenceProfile.uiTestResetStateEnvironmentKey: "1"],
        )

        #expect(WorkspacePersistenceProfile.appDefault(processInfo: processInfo) == .uiTestOnDisk)
    }

    @Test func `store file names stay distinct across on disk profiles`() {
        #expect(WorkspacePersistenceProfile.productionOnDisk.storeFileName == "WorkspaceStore.sqlite")
        #expect(WorkspacePersistenceProfile.debugOnDisk.storeFileName == "WorkspaceStore.debug.sqlite")
        #expect(WorkspacePersistenceProfile.uiTestOnDisk.storeFileName == "WorkspaceStore.ui-test.sqlite")
        #expect(WorkspacePersistenceProfile.inMemory.storeFileName == nil)
    }

    @Test func `cleanup UR ls include SQ lite sidecar files for on disk profiles`() {
        let urls = WorkspacePersistenceController.storeCleanupURLs(for: .uiTestOnDisk)

        #expect(urls.count == 3)
        #expect(urls[0].lastPathComponent == "WorkspaceStore.ui-test.sqlite")
        #expect(urls[1].lastPathComponent == "WorkspaceStore.ui-test.sqlite.shm")
        #expect(urls[2].lastPathComponent == "WorkspaceStore.ui-test.sqlite.wal")
    }
}

private struct ProcessInfoStub: ProcessInfoReading {
    let environment: [String: String]
}
