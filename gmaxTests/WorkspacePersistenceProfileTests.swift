//
//  WorkspacePersistenceProfileTests.swift
//  gmaxTests
//
//  Created by Codex on 4/15/26.
//

import Foundation
import Testing
@testable import gmax

struct WorkspacePersistenceProfileTests {
	@Test func debugBuildDefaultsToDebugStoreWhenNoEnvironmentOverridesExist() {
		#if DEBUG
		let processInfo = ProcessInfoStub(environment: [:])
		#expect(WorkspacePersistenceProfile.appDefault(processInfo: processInfo) == .debugOnDisk)
		#endif
	}

	@Test func explicitPersistenceProfileEnvironmentOverrideWins() {
		let processInfo = ProcessInfoStub(
			environment: [WorkspacePersistenceProfile.environmentKey: WorkspacePersistenceProfile.productionOnDisk.rawValue]
		)

		#expect(WorkspacePersistenceProfile.appDefault(processInfo: processInfo) == .productionOnDisk)
	}

	@Test func uiTestResetEnvironmentSelectsUITestStoreWhenNoExplicitProfileExists() {
		let processInfo = ProcessInfoStub(
			environment: [WorkspacePersistenceProfile.uiTestResetStateEnvironmentKey: "1"]
		)

		#expect(WorkspacePersistenceProfile.appDefault(processInfo: processInfo) == .uiTestOnDisk)
	}

	@Test func storeFileNamesStayDistinctAcrossOnDiskProfiles() {
		#expect(WorkspacePersistenceProfile.productionOnDisk.storeFileName == "WorkspaceStore.sqlite")
		#expect(WorkspacePersistenceProfile.debugOnDisk.storeFileName == "WorkspaceStore.debug.sqlite")
		#expect(WorkspacePersistenceProfile.uiTestOnDisk.storeFileName == "WorkspaceStore.ui-test.sqlite")
		#expect(WorkspacePersistenceProfile.inMemory.storeFileName == nil)
	}

	@Test func cleanupURLsIncludeSQLiteSidecarFilesForOnDiskProfiles() {
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
