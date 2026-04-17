//
//  PaneTreeMutationTests.swift
//  gmaxTests
//
//  Created by Gale Williams on 4/14/26.
//

import CoreGraphics
import Testing
@testable import gmax

@MainActor
struct PaneTreeMutationTests {
	@Test func splitReturnsFalseWhenThePaneDoesNotExist() throws {
		let existingPane = PaneLeaf()
		let insertedPane = PaneLeaf()
		let originalRoot = PaneNode.leaf(existingPane)
		var root = originalRoot

		let didSplit = root.split(
			paneID: PaneID(),
			direction: .right,
			newPane: insertedPane
		)

		#expect(didSplit == false)
		#expect(extractLeaf(from: root)?.id == existingPane.id)
		#expect(root.leaves().count == 1)
		#expect(extractLeaf(from: originalRoot)?.id == existingPane.id)
	}

	@Test func splitLeafReplacesLeafWithExpectedSplit() throws {
		let originalPane = PaneLeaf()
		let insertedPane = PaneLeaf()
		var root = PaneNode.leaf(originalPane)

		let didSplit = root.split(
			paneID: originalPane.id,
			direction: .right,
			newPane: insertedPane,
			initialFraction: 0.4
		)

		#expect(didSplit)
		let split = try #require(extractSplit(from: root))
		#expect(split.axis == .horizontal)
		#expect(split.fraction == 0.4)
		#expect(extractLeaf(from: split.first)?.id == originalPane.id)
		#expect(extractLeaf(from: split.second)?.id == insertedPane.id)
		#expect(root.leaves().count == 2)
	}

	@Test func splitNestedLeafRewritesOnlyTheTargetBranch() throws {
		let leftPane = PaneLeaf()
		let targetPane = PaneLeaf()
		let insertedPane = PaneLeaf()
		var root = PaneNode.split(
			PaneSplit(
				axis: .horizontal,
				fraction: 0.5,
				first: .leaf(leftPane),
				second: .leaf(targetPane)
			)
		)

		let didSplit = root.split(
			paneID: targetPane.id,
			direction: .down,
			newPane: insertedPane
		)

		#expect(didSplit)
		let outerSplit = try #require(extractSplit(from: root))
		#expect(outerSplit.axis == .horizontal)
		#expect(extractLeaf(from: outerSplit.first)?.id == leftPane.id)

		let nestedSplit = try #require(extractSplit(from: outerSplit.second))
		#expect(nestedSplit.axis == .vertical)
		#expect(extractLeaf(from: nestedSplit.first)?.id == targetPane.id)
		#expect(extractLeaf(from: nestedSplit.second)?.id == insertedPane.id)
		#expect(root.leaves().map(\.id) == [leftPane.id, targetPane.id, insertedPane.id])
	}

	@Test func removePaneCollapsesTheParentToTheSurvivingSibling() throws {
		let leftPane = PaneLeaf()
		let rightPane = PaneLeaf()
		let root = PaneNode.split(
			PaneSplit(
				axis: .horizontal,
				fraction: 0.5,
				first: .leaf(leftPane),
				second: .leaf(rightPane)
			)
		)

		let collapsedNode = try #require(root.removingPane(id: rightPane.id))
		#expect(extractLeaf(from: collapsedNode)?.id == leftPane.id)
		#expect(root.leaves().map(\.id) == [leftPane.id, rightPane.id])
	}

	@Test func removeNestedPaneCollapsesOnlyTheNestedBranch() throws {
		let leftPane = PaneLeaf()
		let topRightPane = PaneLeaf()
		let bottomRightPane = PaneLeaf()
		var root = PaneNode.split(
			PaneSplit(
				axis: .horizontal,
				fraction: 0.5,
				first: .leaf(leftPane),
				second: .split(
					PaneSplit(
						axis: .vertical,
						fraction: 0.5,
						first: .leaf(topRightPane),
						second: .leaf(bottomRightPane)
					)
				)
			)
		)

		let updatedRoot = try #require(root.removingPane(id: topRightPane.id))
		let outerSplit = try #require(extractSplit(from: updatedRoot))
		#expect(extractLeaf(from: outerSplit.first)?.id == leftPane.id)
		#expect(extractLeaf(from: outerSplit.second)?.id == bottomRightPane.id)
		#expect(root.leaves().map(\.id) == [leftPane.id, topRightPane.id, bottomRightPane.id])
	}

	@Test func removePaneReturnsTheOriginalTreeWhenThePaneDoesNotExist() throws {
		let leftPane = PaneLeaf()
		let rightPane = PaneLeaf()
		var root = PaneNode.split(
			PaneSplit(
				axis: .horizontal,
				fraction: 0.5,
				first: .leaf(leftPane),
				second: .leaf(rightPane)
			)
		)

		let result = try #require(root.removingPane(id: PaneID()))

			let resultSplit = try #require(extractSplit(from: result))
			let originalSplit = try #require(extractSplit(from: root))
			#expect(resultSplit.id == originalSplit.id)
			#expect(resultSplit.axis == originalSplit.axis)
			#expect(resultSplit.fraction == originalSplit.fraction)
		#expect(root.leaves().map(\.id) == [leftPane.id, rightPane.id])
	}

	@Test func updateSplitFractionOnlyMutatesTheMatchingSplit() throws {
		let leftPane = PaneLeaf()
		let topRightPane = PaneLeaf()
		let bottomRightPane = PaneLeaf()
		let nestedSplit = PaneSplit(
			axis: .vertical,
			fraction: 0.3,
			first: .leaf(topRightPane),
			second: .leaf(bottomRightPane)
		)
		let outerSplit = PaneSplit(
			axis: .horizontal,
			fraction: 0.6,
			first: .leaf(leftPane),
			second: .split(nestedSplit)
		)
		var root = PaneNode.split(outerSplit)

		let didUpdate = root.updateSplitFraction(splitID: nestedSplit.id, fraction: 0.7)

		#expect(didUpdate)
		let resolvedOuterSplit = try #require(extractSplit(from: root))
		#expect(resolvedOuterSplit.fraction == 0.6)
		let resolvedNestedSplit = try #require(extractSplit(from: resolvedOuterSplit.second))
		#expect(resolvedNestedSplit.fraction == 0.7)
	}

	@Test func updateSplitFractionReturnsFalseWhenTheSplitDoesNotExist() throws {
		let leftPane = PaneLeaf()
		let rightPane = PaneLeaf()
		let originalSplit = PaneSplit(
			axis: .horizontal,
			fraction: 0.5,
			first: .leaf(leftPane),
			second: .leaf(rightPane)
		)
		let originalRoot = PaneNode.split(originalSplit)
		var root = originalRoot

		let didUpdate = root.updateSplitFraction(splitID: SplitID(), fraction: 0.8)

		#expect(didUpdate == false)
		let resolvedSplit = try #require(extractSplit(from: root))
		let expectedSplit = try #require(extractSplit(from: originalRoot))
		#expect(resolvedSplit.id == expectedSplit.id)
		#expect(resolvedSplit.axis == expectedSplit.axis)
		#expect(resolvedSplit.fraction == expectedSplit.fraction)
	}

	@Test func removePaneAfterNestedSplitPreservesTheOtherNestedLeaf() throws {
		let firstPane = PaneLeaf()
		let secondPane = PaneLeaf()
		let insertedPane = PaneLeaf()
		var root = PaneNode.split(
			PaneSplit(
				axis: .horizontal,
				fraction: 0.5,
				first: .leaf(firstPane),
				second: .leaf(secondPane)
			)
		)

		let didSplit = root.split(
			paneID: secondPane.id,
			direction: .down,
			newPane: insertedPane
		)
		let removalResult = root.removingPane(id: secondPane.id)

		#expect(didSplit)
		let collapsedRoot = try #require(removalResult)
		let outerSplit = try #require(extractSplit(from: collapsedRoot))
		#expect(extractLeaf(from: outerSplit.first)?.id == firstPane.id)
		#expect(extractLeaf(from: outerSplit.second)?.id == insertedPane.id)
		#expect(collapsedRoot.leaves().map(\.id) == [firstPane.id, insertedPane.id])
	}
}

@MainActor
private func extractLeaf(from node: PaneNode) -> PaneLeaf? {
	guard case .leaf(let leaf) = node else {
		return nil
	}
	return leaf
}

@MainActor
private func extractSplit(from node: PaneNode) -> PaneSplit? {
	guard case .split(let split) = node else {
		return nil
	}
	return split
}
