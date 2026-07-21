import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CodexChatComposer: View {
    @Bindable var session: CodexChatSessionModel
    @State private var isMeetingPickerPresented = false
    @State private var meetingQuery = ""
    @State private var highlightedMeetingID: UUID?
    @State private var suggestions: [CodexChatMeetingReference] = []
    @State private var consumesTrailingMentionOnSelection = false
    @State private var isImageImporterPresented = false
    @State private var isImageDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !session.selectedMeetingReferenceIDs.isEmpty {
                CodexChatMeetingReferenceBar(
                    referenceIDs: session.selectedMeetingReferenceIDs,
                    referencesByID: session.meetingReferencesByID,
                    onRemove: session.removeMeetingReference
                )
            }

            if !session.attachedImages.isEmpty {
                CodexChatAttachmentStrip(
                    attachments: session.attachedImages,
                    onRemove: session.removeAttachedImage
                )
            }

            if let validationMessage = session.attachmentValidationMessage {
                CodexChatAttachmentValidationView(message: validationMessage)
            }

            CodexChatComposerInputRow(
                session: session,
                isMeetingPickerPresented: $isMeetingPickerPresented,
                suggestions: suggestions,
                highlightedMeetingID: highlightedMeetingID,
                onShowImageImporter: showImageImporter,
                onShowMeetingPicker: showMeetingPicker,
                onSelectMeeting: selectMeeting,
                onSubmit: handleSubmit,
                onMoveCommand: handleMoveCommand,
                onExitCommand: closeMeetingPicker,
                onHover: updateTextInputCursor
            )
        }
        .padding(6)
        .background {
            CodexChatComposerBackground(isDropTargeted: isImageDropTargeted)
        }
        .shadow(color: .black.opacity(0.05), radius: 12, y: 3)
        .onChange(of: session.draft, handleDraftChange)
        .onChange(of: session.availableMeetingReferences) {
            refreshSuggestionsIfPresented()
        }
        .onChange(of: session.selectedMeetingReferenceIDs) {
            refreshSuggestionsIfPresented()
        }
        .fileImporter(
            isPresented: $isImageImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true,
            onCompletion: handleImageImport
        )
        .dropDestination(for: CodexChatTransferImage.self) { images, _ in
            addTransferImages(images)
        }
        .onDropSessionUpdated(updateDropTarget)
        .pasteDestination(for: CodexChatTransferImage.self, action: addTransferImages)
    }

    private func showImageImporter() {
        isImageImporterPresented = true
    }

    private func handleImageImport(_ result: Result<[URL], any Error>) {
        switch result {
        case let .success(urls):
            Task { await session.addImageURLs(urls) }
        case let .failure(error):
            let cocoaError = error as NSError
            guard cocoaError.domain != NSCocoaErrorDomain || cocoaError.code != NSUserCancelledError else { return }
            session.reportImageAttachmentFailure()
        }
    }

    private func addTransferImages(_ images: [CodexChatTransferImage]) {
        Task { await session.addImageData(images.map(\.data)) }
    }

    private func updateDropTarget(_ dropSession: DropSession) {
        switch dropSession.phase {
        case .entering, .active:
            isImageDropTargeted = true
        case .exiting, .ended, .dataTransferCompleted:
            isImageDropTargeted = false
        @unknown default:
            isImageDropTargeted = false
        }
    }

    private func handleSubmit() {
        if isMeetingPickerPresented,
           let highlightedMeetingID,
           let reference = suggestions.first(where: { $0.id == highlightedMeetingID }) {
            selectMeeting(reference)
            return
        }
        guard NSApp.currentEvent?.modifierFlags.contains(.shift) == true else {
            session.sendDraft()
            return
        }

        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
            session.draft.append("\n")
            return
        }

        textView.insertNewlineIgnoringFieldEditor(nil)
    }

    private func handleDraftChange(_: String, _ newValue: String) {
        guard let query = CodexChatMeetingReference.trailingMentionQuery(in: newValue) else {
            if isMeetingPickerPresented {
                closeMeetingPicker()
            }
            return
        }
        meetingQuery = query
        consumesTrailingMentionOnSelection = true
        isMeetingPickerPresented = true
        refreshSuggestions()
    }

    private func showMeetingPicker() {
        meetingQuery = ""
        consumesTrailingMentionOnSelection = false
        isMeetingPickerPresented = true
        refreshSuggestions()
    }

    private func closeMeetingPicker() {
        isMeetingPickerPresented = false
        meetingQuery = ""
        highlightedMeetingID = nil
        consumesTrailingMentionOnSelection = false
    }

    private func selectMeeting(_ reference: CodexChatMeetingReference) {
        session.draft = CodexChatMeetingReference.draftAfterSelectingReference(
            session.draft,
            consumesTrailingMention: consumesTrailingMentionOnSelection
        )
        session.addMeetingReference(reference)
        closeMeetingPicker()
    }

    private func refreshSuggestionsIfPresented() {
        guard isMeetingPickerPresented else { return }
        refreshSuggestions()
    }

    private func refreshSuggestions() {
        suggestions = CodexChatMeetingReference.suggestions(
            from: session.availableMeetingReferences,
            excluding: session.selectedMeetingReferenceIDs,
            query: meetingQuery
        )
        updateHighlightedMeeting()
    }

    private func updateHighlightedMeeting() {
        guard !suggestions.contains(where: { $0.id == highlightedMeetingID }) else { return }
        highlightedMeetingID = suggestions.first?.id
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard isMeetingPickerPresented, !suggestions.isEmpty else { return }
        switch direction {
        case .up:
            highlightedMeetingID = CodexChatMeetingPickerSelection.moving(
                currentID: highlightedMeetingID,
                in: suggestions,
                by: -1
            )
        case .down:
            highlightedMeetingID = CodexChatMeetingPickerSelection.moving(
                currentID: highlightedMeetingID,
                in: suggestions,
                by: 1
            )
        default:
            return
        }
    }

    private func updateTextInputCursor(_ phase: HoverPhase) {
        switch phase {
        case .active:
            NSCursor.iBeam.set()
        case .ended:
            NSCursor.arrow.set()
        }
    }
}
