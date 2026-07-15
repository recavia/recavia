import SwiftUI

struct TranscriptTabView: View {
    private enum ScrollMetrics {
        static let bottomAnchorID = "transcript-bottom"
        static let followThreshold: CGFloat = 32
        static let loadMoreThreshold: CGFloat = 24
    }

    private struct EdgeProximity: Equatable {
        let isNearBottom: Bool
        let isNearTop: Bool
        let contentOffsetY: CGFloat
    }

    private struct SegmentStructure: Equatable {
        let count: Int
        let latestConfirmedID: TranscriptSegment.ID?
    }

    @ObservedObject var store: TranscriptStore
    let isListening: Bool
    let showsRecordingIndicator: Bool
    let showsTranslatedText: Bool
    let batchTranscriptionState: BatchTranscriptionState?
    let confirmBatchTranscription: () -> Void
    let retryBatchTranscription: () -> Void
    let discardFailedBatchTranscription: () -> Void

    /// 過去へ移動しても ForEach の要素数が増えない固定容量の表示 window。
    @State private var segmentWindow = TranscriptSegmentWindow<TranscriptSegment.ID>()
    @State private var didCompleteInitialBottomScroll = false
    /// 上端到達時の onAppear が連射しないようにする単発フラグ。
    /// 一度 false に倒したら、ユーザーが上端から離れた瞬間 (`!isNearTop`) にのみ再アームする。
    /// Spinner が表示領域に留まり続けるケースで誤って再ロードが走るのを防ぐ。
    @State private var canLoadMoreFromTop = true
    @State private var canLoadMoreFromBottom = true
    @State private var isWindowShiftPending = false
    /// resetWindowAndScrollToBottom 中の deferred scroll を保持し、リセット連発時に古い Task を cancel する。
    @State private var pendingScrollTask: Task<Void, Never>?

    /// ForEach の ID 照合対象を固定容量に制限する。
    private var windowedSegments: ArraySlice<TranscriptSegment> {
        store.segments[windowRange]
    }

    private var windowRange: Range<Int> {
        segmentWindow.range(in: store.segments, id: \.id)
    }

    private var hasMoreAbove: Bool {
        windowRange.lowerBound > 0
    }

    private var hasMoreBelow: Bool {
        windowRange.upperBound < store.segments.count
    }

    private var segmentStructure: SegmentStructure {
        let latestConfirmedID = store.segments
            .lastIndex(where: \.isConfirmed)
            .map { store.segments[$0].id }
        return SegmentStructure(count: store.segments.count, latestConfirmedID: latestConfirmedID)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let batchTranscriptionState {
                BatchTranscriptionStatusView(
                    state: batchTranscriptionState,
                    confirm: confirmBatchTranscription,
                    retry: retryBatchTranscription,
                    discard: discardFailedBatchTranscription
                )
            }

            if store.segments.isEmpty, !isListening || batchTranscriptionState != nil {
                ContentUnavailableView {
                    Label(L10n.transcript, systemImage: "waveform.badge.microphone")
                } description: {
                    Text(L10n.transcriptEmpty)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                transcriptScrollView
            }
        }
    }

    private var transcriptScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if hasMoreAbove {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .onAppear {
                                loadEarlierSegmentsIfNeeded(using: proxy)
                            }
                    }

                    let timeBase = store.timeBase
                    let recordingSessions = store.recordingSessions
                    ForEach(windowedSegments) { segment in
                        TranscriptRowView(
                            segment: segment,
                            timestamp: Formatters.elapsedHHmmss(
                                at: segment.startTime,
                                sessionId: segment.sessionId,
                                sessions: recordingSessions,
                                fallbackTimeBase: timeBase
                            ),
                            showsTranslatedText: showsTranslatedText,
                            allowsTextSelection: !isListening
                        )
                        .equatable()
                    }

                    if hasMoreBelow {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .onAppear {
                                loadLaterSegmentsIfNeeded(using: proxy)
                            }
                    }

                    if showsRecordingIndicator {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                            Text(L10n.recognizing)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .padding(.leading, 68)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(ScrollMetrics.bottomAnchorID)
                }
                .padding(8)
            }
            .onAppear {
                resetWindowAndScrollToBottom(using: proxy)
            }
            .onChange(of: store.segments.first?.id) { _, _ in
                resetWindowAndScrollToBottom(using: proxy)
            }
            .onScrollGeometryChange(for: EdgeProximity.self) { geometry in
                let distanceFromBottom = geometry.contentSize.height
                    - geometry.contentOffset.y
                    - geometry.containerSize.height
                return EdgeProximity(
                    isNearBottom: distanceFromBottom <= ScrollMetrics.followThreshold,
                    isNearTop: geometry.contentOffset.y <= ScrollMetrics.loadMoreThreshold,
                    contentOffsetY: geometry.contentOffset.y
                )
            } action: { previousProximity, proximity in
                let isFollowingLatest = proximity.isNearBottom && !hasMoreBelow
                if isFollowingLatest {
                    segmentWindow.followLatest()
                } else if didCompleteInitialBottomScroll,
                          segmentWindow.isFollowingLatest,
                          abs(proximity.contentOffsetY - previousProximity.contentOffsetY) > 0.5 {
                    // Content growth alone must not disable follow mode; only viewport movement does.
                    segmentWindow.freeze(in: store.segments, id: \.id)
                }
                if !proximity.isNearTop {
                    canLoadMoreFromTop = true
                }
                if !proximity.isNearBottom {
                    canLoadMoreFromBottom = true
                }
            }
            .onChange(of: segmentStructure) { _, _ in
                guard segmentWindow.isFollowingLatest else { return }
                scrollToBottom(using: proxy)
            }
        }
    }

    private func loadEarlierSegmentsIfNeeded(using proxy: ScrollViewProxy) {
        guard didCompleteInitialBottomScroll,
              !segmentWindow.isFollowingLatest,
              canLoadMoreFromTop,
              !isWindowShiftPending else { return }
        let currentRange = windowRange
        guard !currentRange.isEmpty else { return }
        let anchorID = store.segments[currentRange.lowerBound].id

        canLoadMoreFromTop = false
        guard segmentWindow.shiftEarlier(in: store.segments, id: \.id) else { return }
        restoreScrollPosition(to: anchorID, anchor: .top, using: proxy)
    }

    private func loadLaterSegmentsIfNeeded(using proxy: ScrollViewProxy) {
        guard didCompleteInitialBottomScroll,
              !segmentWindow.isFollowingLatest,
              canLoadMoreFromBottom,
              !isWindowShiftPending else { return }
        let currentRange = windowRange
        guard !currentRange.isEmpty else { return }
        let anchorID = store.segments[currentRange.upperBound - 1].id

        canLoadMoreFromBottom = false
        guard segmentWindow.shiftLater(in: store.segments, id: \.id) else { return }
        restoreScrollPosition(to: anchorID, anchor: .bottom, using: proxy)
    }

    private func resetWindowAndScrollToBottom(using proxy: ScrollViewProxy) {
        didCompleteInitialBottomScroll = false
        canLoadMoreFromTop = true
        canLoadMoreFromBottom = true
        isWindowShiftPending = false
        segmentWindow.followLatest()

        scheduleDeferredScroll {
            // LazyVStack の初期レイアウト確定後にスクロールするため、1 ターン譲る。
            scrollToBottom(using: proxy)
            didCompleteInitialBottomScroll = true
        }
    }

    private func restoreScrollPosition(
        to id: TranscriptSegment.ID,
        anchor: UnitPoint,
        using proxy: ScrollViewProxy
    ) {
        isWindowShiftPending = true
        scheduleDeferredScroll {
            proxy.scrollTo(id, anchor: anchor)
            isWindowShiftPending = false
        }
    }

    private func scheduleDeferredScroll(_ action: @escaping @MainActor () -> Void) {
        pendingScrollTask?.cancel()
        pendingScrollTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            action()
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(ScrollMetrics.bottomAnchorID, anchor: .bottom)
        }
    }
}
