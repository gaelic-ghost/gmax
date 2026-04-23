//
//  WorkspacePersistenceProfileTests.swift
//  gmaxTests
//
//  Created by Codex on 4/15/26.
//

import CoreData
import Foundation
@testable import gmax
import Testing

struct WorkspacePersistenceProfileTests {
    @Test func `background save interval default and normalization stay stable`() {
        #expect(WorkspacePersistenceDefaults.defaultBackgroundSaveIntervalMinutes == 5)
        #expect(WorkspacePersistenceDefaults.normalizedBackgroundSaveIntervalMinutes(0) == 1)
        #expect(WorkspacePersistenceDefaults.normalizedBackgroundSaveIntervalMinutes(5) == 5)
    }

    @Test func `restore workspaces on launch falls back to system default when no explicit setting exists`() {
        let userDefaults = UserDefaults(suiteName: "WorkspacePersistenceProfileTests.restore-default")!
        userDefaults.removePersistentDomain(forName: "WorkspacePersistenceProfileTests.restore-default")
        let globalDefaults = UserDefaults(suiteName: "WorkspacePersistenceProfileTests.restore-global")!
        globalDefaults.removePersistentDomain(forName: "WorkspacePersistenceProfileTests.restore-global")

        #expect(
            WorkspacePersistenceDefaults.restoreWorkspacesOnLaunch(
                userDefaults: userDefaults,
                globalDefaults: globalDefaults,
            ) == true
        )
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

    @Test func `hosted unit tests default to the in memory store`() {
        let processInfo = ProcessInfoStub(
            environment: [WorkspacePersistenceProfile.xCTestConfigurationFilePathEnvironmentKey: "/tmp/gmax-tests.xctestconfiguration"],
        )

        #expect(WorkspacePersistenceProfile.appDefault(processInfo: processInfo) == .inMemory)
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

    @MainActor
    @Test func `managed object model provides migration defaults for required timestamp fields`() throws {
        let model = WorkspacePersistenceController.makeManagedObjectModel()
        let workspaceEntity = try #require(model.entitiesByName["WorkspaceEntity"])
        let windowEntity = try #require(model.entitiesByName["WorkspaceWindowEntity"])
        let membershipEntity = try #require(model.entitiesByName["WindowWorkspaceMembershipEntity"])
        let placementEntity = try #require(model.entitiesByName["WorkspacePlacementEntity"])

        let workspaceCreatedAt = workspaceEntity.attributesByName["createdAt"]
        let workspaceUpdatedAt = workspaceEntity.attributesByName["updatedAt"]
        let workspaceLastActiveAt = workspaceEntity.attributesByName["lastActiveAt"]
        let workspaceRecentWindowID = workspaceEntity.attributesByName["recentWindowID"]
        let workspaceRecentSortOrder = workspaceEntity.attributesByName["recentSortOrder"]
        let windowCreatedAt = windowEntity.attributesByName["createdAt"]
        let windowUpdatedAt = windowEntity.attributesByName["updatedAt"]
        let windowLastActiveAt = windowEntity.attributesByName["lastActiveAt"]
        let windowSelectedWorkspaceID = windowEntity.attributesByName["selectedWorkspaceID"]
        let windowIsOpen = windowEntity.attributesByName["isOpen"]
        let membershipCreatedAt = membershipEntity.attributesByName["createdAt"]
        let membershipUpdatedAt = membershipEntity.attributesByName["updatedAt"]
        let membershipSortOrder = membershipEntity.attributesByName["sortOrder"]
        let placementCreatedAt = placementEntity.attributesByName["createdAt"]
        let placementUpdatedAt = placementEntity.attributesByName["updatedAt"]

        #expect(workspaceCreatedAt?.defaultValue is Date)
        #expect(workspaceUpdatedAt?.defaultValue is Date)
        #expect(workspaceLastActiveAt?.defaultValue is Date)
        #expect(workspaceRecentWindowID?.isOptional == true)
        #expect(workspaceRecentSortOrder?.defaultValue as? Int64 == 0)
        #expect(windowCreatedAt?.defaultValue is Date)
        #expect(windowUpdatedAt?.defaultValue is Date)
        #expect(windowLastActiveAt?.defaultValue is Date)
        #expect(windowSelectedWorkspaceID?.isOptional == true)
        #expect(windowIsOpen?.defaultValue as? Bool == false)
        #expect(membershipCreatedAt?.defaultValue is Date)
        #expect(membershipUpdatedAt?.defaultValue is Date)
        #expect(membershipSortOrder?.defaultValue as? Int64 == 0)
        #expect(placementCreatedAt?.defaultValue is Date)
        #expect(placementUpdatedAt?.defaultValue is Date)
        #expect(workspaceEntity.attributesByName["savedWorkspaceID"] == nil)
    }
}

private struct ProcessInfoStub: ProcessInfoReading {
    let environment: [String: String]
}
