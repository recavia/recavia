import SwiftUI

struct CodexChatComposerInputRow: View {
    @Bindable var session: CodexChatSessionModel
    @Binding var isMeetingPickerPresented: Bool
    let suggestions: [CodexChatMeetingReference]
    let highlightedMeetingID: UUID?
    let onShowImageImporter: () -> Void
    let onShowMeetingPicker: () -> Void
    let onSelectMeeting: (CodexChatMeetingReference) -> Void
    let onSubmit: () -> Void
    let onMoveCommand: (MoveCommandDirection) -> Void
    let onExitCommand: () -> Void
    let onHover: (HoverPhase) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            HStack(spacing: 4) {
                Button(L10n.attachChatImages, systemImage: "paperclip", action: onShowImageImporter)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(width: CodexChatDesign.controlSize, height: CodexChatDesign.controlSize)
                    .background(.quaternary, in: Circle())
                    .contentShape(Circle())
                    .help(L10n.attachChatImages)

                Button(L10n.addMeetingReference, systemImage: "plus", action: onShowMeetingPicker)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(width: CodexChatDesign.controlSize, height: CodexChatDesign.controlSize)
                    .background(.quaternary, in: Circle())
                    .contentShape(Circle())
                    .help(L10n.addMeetingReference)
                    .popover(isPresented: $isMeetingPickerPresented, arrowEdge: .top) {
                        CodexChatMeetingPicker(
                            references: suggestions,
                            highlightedID: highlightedMeetingID,
                            onSelect: onSelectMeeting
                        )
                    }
            }

            TextField(L10n.messageCodex, text: $session.draft, axis: .vertical)
                .font(.body)
                .textFieldStyle(.plain)
                .lineLimit(1 ... 5)
                .padding(.leading, 8)
                .padding(.vertical, 6)
                .contentShape(.rect)
                .onContinuousHover(perform: onHover)
                .accessibilityLabel(L10n.messageCodex)
                .onSubmit(onSubmit)
                .onMoveCommand(perform: onMoveCommand)
                .onExitCommand(perform: onExitCommand)

            if session.isLoading, session.models.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: CodexChatDesign.controlSize, height: CodexChatDesign.controlSize)
                    .accessibilityLabel(L10n.chatModelLoading)
            } else if !session.models.isEmpty {
                CodexChatConfigurationButton(session: session)
            }

            if session.isGenerating, !session.canSend {
                CodexChatActionButton(
                    label: L10n.stopGenerating,
                    systemImage: "stop.fill",
                    isEnabled: true,
                    action: session.stop
                )
            } else {
                CodexChatActionButton(
                    label: L10n.sendMessage,
                    systemImage: "arrow.up",
                    isEnabled: session.canSend,
                    action: session.sendDraft
                )
            }
        }
    }
}
