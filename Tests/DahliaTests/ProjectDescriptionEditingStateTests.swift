import Foundation
@testable import Dahlia

#if canImport(Testing)
import Testing

@MainActor
struct ProjectDescriptionEditingStateTests {
    @Test
    func restoredDraftKeepsPersistedDescriptionAsSaveBaseline() {
        let state = ProjectDescriptionEditingState(
            persistedText: "Saved description",
            draftText: "Unsaved description"
        )

        #expect(state.text == "Unsaved description")
        #expect(state.persistedText == "Saved description")
        #expect(state.hasUnsavedChanges)
    }

    @Test
    func missingProjectDoesNotRemainAFailedDraft() throws {
        let database = try AppDatabaseManager(path: ":memory:")
        let viewModel = SidebarViewModel()
        let deletedProjectId = UUID.v7()
        viewModel.setAppDatabase(database)
        viewModel.stageProjectDescriptionDraft(id: deletedProjectId, description: "Unsaved description")

        let result = viewModel.updateProjectDescription(
            id: deletedProjectId,
            description: "Unsaved description"
        )

        #expect(result == .projectNotFound)
        #expect(viewModel.projectDescriptionDraft(id: deletedProjectId) == nil)
    }
}
#endif
