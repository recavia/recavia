enum CodexChatPendingInput {
    case manual(String)
    case liveTranscript(String, wasTruncated: Bool)
}
