import AppKit
import SwiftUI

struct ProjectManagementView: View {
    var sidebarViewModel: SidebarViewModel

    @State private var selectedProjectId: UUID?
    @State private var projectSearchText = ""
    @State private var isShowingProjectCreation = false
    @State private var newProjectName = ""
    @State private var isShowingProjectCreationError = false
    @State private var projectCreationErrorMessage = ""
    @State private var projectDescription = ""
    @State private var descriptionStatusMessage: String?
    @State private var descriptionSaveFailed = false
    @State private var lastSavedProjectDescription = ""
    @State private var descriptionSaveTask: Task<Void, Never>?

    private let sidebarWidth: CGFloat = 300

    var body: some View {
        NavigationSplitView {
            projectSidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: sidebarWidth, max: 360)
        } detail: {
            selectedProjectDetail
        }
        .frame(minWidth: 900, minHeight: 580)
        .onAppear {
            selectInitialProjectIfNeeded()
            loadProjectDescription(for: selectedProjectId)
        }
        .onChange(of: sidebarViewModel.allProjectItems) { _, projects in
            reconcileSelection(with: projects)
        }
        .onChange(of: selectedProjectId) { oldProjectId, newProjectId in
            descriptionSaveTask?.cancel()
            persistProjectDescriptionIfNeeded(for: oldProjectId)
            loadProjectDescription(for: newProjectId)
        }
        .onChange(of: projectDescription) { _, _ in
            scheduleProjectDescriptionSave()
        }
        .onDisappear {
            descriptionSaveTask?.cancel()
            persistProjectDescriptionIfNeeded(for: selectedProjectId)
        }
    }

    private var projectNodes: [ProjectTreeNode] {
        ProjectTreeNode.buildNodes(from: sidebarViewModel.allProjectItems)
    }

    private var filteredProjectNodes: [ProjectTreeNode] {
        let query = projectSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return projectNodes }
        return projectNodes.compactMap { $0.filtered(matching: query) }
    }

    private var selectedProject: ProjectOverviewItem? {
        guard let selectedProjectId else { return nil }
        return sidebarViewModel.allProjectItems.first(where: { $0.projectId == selectedProjectId })
    }

    private var trimmedNewProjectName: String {
        newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var projectSidebar: some View {
        List(selection: $selectedProjectId) {
            if filteredProjectNodes.isEmpty {
                ContentUnavailableView {
                    Label(
                        sidebarViewModel.allProjectItems.isEmpty ? L10n.noProjectsYet : L10n.noResultsFound,
                        systemImage: "folder"
                    )
                }
                .listRowSeparator(.hidden)
            } else {
                OutlineGroup(filteredProjectNodes, children: \.children) { node in
                    ProjectManagementRow(node: node, isSelected: selectedProjectId == node.id)
                        .tag(node.id)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(L10n.projects)
        .searchable(text: $projectSearchText, prompt: L10n.searchProjects)
        .toolbar {
            ToolbarItem {
                Button(L10n.newProject, systemImage: "plus", action: presentProjectCreation)
                    .disabled(AppSettings.shared.currentVault == nil)
                    .help(L10n.newProject)
            }
        }
        .alert(L10n.newProject, isPresented: $isShowingProjectCreation) {
            TextField(L10n.projectName, text: $newProjectName)
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.create, action: createProject)
                .disabled(trimmedNewProjectName.isEmpty)
        }
        .alert(L10n.projectCreationFailed, isPresented: $isShowingProjectCreationError) {} message: {
            Text(projectCreationErrorMessage)
        }
    }

    @ViewBuilder
    private var selectedProjectDetail: some View {
        if AppSettings.shared.currentVault == nil {
            ContentUnavailableView {
                Label(L10n.noVaultSelected, systemImage: "externaldrive")
            } description: {
                Text(L10n.projectManagementNoVaultDescription)
            }
        } else if let selectedProject {
            projectDetailForm(for: selectedProject)
                .navigationTitle(selectedProject.projectName)
        } else {
            ContentUnavailableView {
                Label(L10n.projects, systemImage: "folder")
            } description: {
                Text(L10n.selectProjectToManageDescription)
            }
        }
    }

    private func projectDetailForm(for project: ProjectOverviewItem) -> some View {
        Form {
            Section {
                Label(L10n.meetingCount(project.meetingCount), systemImage: "text.bubble")
                    .foregroundStyle(.secondary)

                if project.missingOnDisk {
                    Label(L10n.missingOnDisk, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            descriptionSection
            destinationSection(for: project)
        }
        .formStyle(.grouped)
    }

    private var descriptionSection: some View {
        Section {
            TextField(L10n.projectDescriptionPlaceholder, text: $projectDescription, axis: .vertical)
                .lineLimit(6 ... 12)

            if let descriptionStatusMessage {
                SettingsStatusMessage(
                    text: descriptionStatusMessage,
                    systemImage: descriptionSaveFailed ? "exclamationmark.triangle" : "checkmark.circle",
                    tint: descriptionSaveFailed ? .orange : .secondary
                )
            }
        } header: {
            Text(L10n.projectDescription)
        } footer: {
            Text(L10n.projectDescriptionHelp)
        }
    }

    private func destinationSection(for project: ProjectOverviewItem) -> some View {
        Section {
            projectFolderRow(for: project)
        } header: {
            Text(L10n.summaryDestinations)
        } footer: {
            Text(L10n.summaryDestinationsDescription)
        }
    }

    private func projectFolderRow(for project: ProjectOverviewItem) -> some View {
        LabeledContent {
            Button {
                openProjectFolder(for: project)
            } label: {
                Label(L10n.openInFinder, systemImage: "folder")
            }
            .disabled(projectFolderURL(for: project) == nil)
        } label: {
            Text(L10n.localSummaryFolder)
            Text(projectFolderPath(for: project) ?? L10n.noVaultSelected)
        }
    }

    private func selectInitialProjectIfNeeded() {
        guard selectedProjectId == nil else { return }
        selectedProjectId = sidebarViewModel.allProjectItems.first?.projectId
    }

    private func presentProjectCreation() {
        newProjectName = ""
        isShowingProjectCreation = true
    }

    private func createProject() {
        let projectName = trimmedNewProjectName
        guard !projectName.isEmpty else { return }

        let projectId: UUID
        if let existingProject = sidebarViewModel.allProjectItems.first(where: {
            $0.projectName.caseInsensitiveCompare(projectName) == .orderedSame
        }) {
            projectId = existingProject.projectId
        } else {
            guard let project = sidebarViewModel.fetchOrCreateProject(name: projectName) else {
                projectCreationErrorMessage = sidebarViewModel.lastError ?? L10n.projectCreationFailedDescription
                isShowingProjectCreationError = true
                return
            }
            projectId = project.record.id
        }

        projectSearchText = ""
        selectedProjectId = projectId
    }

    private func reconcileSelection(with projects: [ProjectOverviewItem]) {
        if let selectedProjectId, projects.contains(where: { $0.projectId == selectedProjectId }) {
            return
        }
        selectedProjectId = projects.first?.projectId
    }

    private func projectFolderURL(for project: ProjectOverviewItem) -> URL? {
        guard AppSettings.shared.currentVault != nil else { return nil }
        return sidebarViewModel.projectURL(for: project.projectName)
    }

    private func projectFolderPath(for project: ProjectOverviewItem) -> String? {
        projectFolderURL(for: project)?.path
    }

    private func openProjectFolder(for project: ProjectOverviewItem) {
        guard let url = projectFolderURL(for: project) else { return }
        NSWorkspace.shared.open(url)
    }

    private func loadProjectDescription(for projectId: UUID?) {
        let description = projectId.flatMap(sidebarViewModel.projectDescription(id:)) ?? ""
        projectDescription = description
        lastSavedProjectDescription = description
        descriptionStatusMessage = nil
    }

    private func scheduleProjectDescriptionSave() {
        guard let selectedProjectId,
              projectDescription != lastSavedProjectDescription else { return }
        descriptionSaveTask?.cancel()
        descriptionSaveTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(450))
            } catch {
                return
            }
            persistProjectDescriptionIfNeeded(for: selectedProjectId)
        }
    }

    private func persistProjectDescriptionIfNeeded(for projectId: UUID?) {
        guard let projectId,
              projectDescription != lastSavedProjectDescription else { return }

        if sidebarViewModel.updateProjectDescription(id: projectId, description: projectDescription) {
            lastSavedProjectDescription = projectDescription
            descriptionStatusMessage = L10n.saved
            descriptionSaveFailed = false
        } else {
            descriptionStatusMessage = L10n.projectDescriptionSaveFailed
            descriptionSaveFailed = true
        }
    }
}

private struct ProjectManagementRow: View {
    let node: ProjectTreeNode
    let isSelected: Bool

    private var project: ProjectOverviewItem {
        node.project
    }

    var body: some View {
        Label {
            HStack(spacing: 6) {
                Text(node.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)

                ProjectMeetingCountBadge(count: node.meetingCount, isSelected: isSelected)

                Spacer(minLength: 0)

                if project.missingOnDisk {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .orange)
                        .help(L10n.missingOnDisk)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        } icon: {
            Image(systemName: project.missingOnDisk ? "folder.badge.questionmark" : "folder")
                .foregroundStyle(project.missingOnDisk ? .orange : (isSelected ? .white : .secondary))
        }
    }

    private var accessibilityLabel: String {
        var label = "\(node.displayName), \(L10n.meetingCount(node.meetingCount))"
        if project.missingOnDisk {
            label += ", \(L10n.missingOnDisk)"
        }
        return label
    }
}

private struct ProjectMeetingCountBadge: View {
    let count: Int
    let isSelected: Bool

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(isSelected ? Color.white : Color(nsColor: .secondaryLabelColor))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(minWidth: 18)
            .background(backgroundColor, in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityHidden(true)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.white.opacity(0.20)
        }
        return Color(nsColor: .secondaryLabelColor).opacity(0.14)
    }
}
