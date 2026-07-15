import SwiftUI

struct ScreenshotManagementToolbar: View {
    @Binding var layout: ScreenshotGridLayout
    @Binding var isSelecting: Bool
    let selectedCount: Int
    let canSelectAll: Bool
    let isDeletionDisabled: Bool
    let selectAll: () -> Void
    let deleteSelected: () -> Void

    var body: some View {
        HStack {
            Picker(L10n.layout, selection: $layout) {
                ForEach(ScreenshotGridLayout.allCases) { layout in
                    Label(layout.label, systemImage: layout.systemImage)
                        .tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            if isSelecting {
                Text(L10n.selectedCount(selectedCount))
                    .foregroundStyle(.secondary)

                Button(L10n.selectAll, action: selectAll)
                    .disabled(!canSelectAll)

                Button(L10n.delete, systemImage: "trash", role: .destructive, action: deleteSelected)
                    .disabled(selectedCount == 0 || isDeletionDisabled)
            }

            Button(isSelecting ? L10n.done : L10n.select) {
                isSelecting.toggle()
            }
            .disabled(!isSelecting && isDeletionDisabled)
        }
        .buttonStyle(.bordered)
    }
}
