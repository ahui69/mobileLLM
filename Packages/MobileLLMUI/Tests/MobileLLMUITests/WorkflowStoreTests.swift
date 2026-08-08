// SPDX-License-Identifier: MIT

import XCTest
import AgentContracts
@testable import MobileLLMUI

// TEST-ID: AHT-WORKFLOW-001
@MainActor
final class WorkflowStoreTests: XCTestCase {
    func testSaveLoadRoundTripAndRunningFlag() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("workflow-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkflowStore(directory: directory)
        let workflowID = UUID()
        let summary = WorkflowSummary(
            id: workflowID,
            title: "Research",
            conversationID: UUID(),
            plan: try WorkflowPlan(
                goal: "Research",
                phases: [WorkflowPhasePlan(
                    sequence: 1,
                    title: "Goal",
                    acceptanceCriteria: "Done",
                    childInstructions: ["Research"]
                )]
            ),
            status: .running,
            rootRunID: AgentRunID(rawValue: UUID())
        )

        try await store.save(summary)
        XCTAssertTrue(store.hasRunningWorkflow)
        XCTAssertEqual(store.messageRecord(workflowID: workflowID)?.title, "Research")

        let reloaded = WorkflowStore(directory: directory)
        reloaded.load()
        XCTAssertEqual(reloaded.summary(workflowID: workflowID), summary)
        XCTAssertTrue(reloaded.hasRunningWorkflow)
    }

    func testCompletedWorkflowStopsRunningAndRefreshFires() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("workflow-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkflowStore(directory: directory)
        let workflowID = UUID()
        var changed: [UUID] = []
        store.onWorkflowChanged = { changed.append($0) }

        try await store.save(WorkflowSummary(id: workflowID, title: "T", status: .running))
        var completed = try XCTUnwrap(store.summary(workflowID: workflowID))
        completed.status = .completed
        completed.endTime = Date()
        try await store.save(completed)

        XCTAssertEqual(changed, [workflowID, workflowID])
        XCTAssertFalse(store.hasRunningWorkflow)
        XCTAssertEqual(store.messageRecord(workflowID: workflowID)?.status, .completed)
    }

    func testLoadingRunningWorkflowNeverResumesUntilExplicitAction() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("workflow-resume-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workflowID = UUID()
        let writer = WorkflowStore(directory: directory)
        try await writer.save(WorkflowSummary(id: workflowID, title: "Interrupted", status: .running))

        let reloaded = WorkflowStore(directory: directory)
        var resumeCount = 0
        reloaded.resumeHandler = { id in
            XCTAssertEqual(id, workflowID)
            resumeCount += 1
        }
        reloaded.load()

        XCTAssertEqual(resumeCount, 0, "neutral launch must not restart durable work")
        XCTAssertFalse(reloaded.executingWorkflowIDs.contains(workflowID))
        await reloaded.resume(workflowID: workflowID)
        XCTAssertEqual(resumeCount, 1)
        XCTAssertTrue(reloaded.executingWorkflowIDs.contains(workflowID))
        XCTAssertTrue(reloaded.resumingWorkflowIDs.isEmpty)
    }

    func testResumeFailureIsVisibleAndDoesNotChangeDurableRunningState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("workflow-resume-error-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workflowID = UUID()
        let writer = WorkflowStore(directory: directory)
        try await writer.save(WorkflowSummary(id: workflowID, title: "Interrupted", status: .running))
        let store = WorkflowStore(directory: directory)
        store.load()
        struct ResumeFailure: LocalizedError {
            var errorDescription: String? { "fixture failed" }
        }
        store.resumeHandler = { _ in throw ResumeFailure() }

        await store.resume(workflowID: workflowID)

        XCTAssertEqual(store.summary(workflowID: workflowID)?.status, .running)
        XCTAssertEqual(store.lastError, "Workflow could not resume: fixture failed")
        XCTAssertFalse(store.executingWorkflowIDs.contains(workflowID))
        XCTAssertTrue(store.resumingWorkflowIDs.isEmpty)
    }
}
