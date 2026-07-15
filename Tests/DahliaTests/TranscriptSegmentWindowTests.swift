#if canImport(Testing)
    import Testing
    @testable import Dahlia

    struct TranscriptSegmentWindowTests {
        @Test
        func movingThroughLongTranscriptKeepsRenderedRangeBounded() {
            let ids = Array(0 ..< 1000)
            var window = TranscriptSegmentWindow<Int>(capacity: 100, pageSize: 50)

            #expect(window.range(in: ids, id: \.self) == 900 ..< 1000)

            for _ in 0 ..< 20 {
                window.shiftEarlier(in: ids, id: \.self)
                #expect(window.range(in: ids, id: \.self).count <= 100)
            }

            #expect(window.range(in: ids, id: \.self) == 0 ..< 100)

            for _ in 0 ..< 20 {
                window.shiftLater(in: ids, id: \.self)
                #expect(window.range(in: ids, id: \.self).count <= 100)
            }

            #expect(window.range(in: ids, id: \.self) == 900 ..< 1000)
        }

        @Test
        func frozenWindowDoesNotMoveWhenSegmentsAreAppended() {
            var ids = Array(0 ..< 200)
            var window = TranscriptSegmentWindow<Int>()
            window.freeze(in: ids, id: \.self)

            ids.append(contentsOf: 200 ..< 250)
            #expect(window.range(in: ids, id: \.self) == 100 ..< 200)

            window.followLatest()

            #expect(window.range(in: ids, id: \.self) == 150 ..< 250)
        }

        @Test
        func shortTranscriptUsesItsEntireRange() {
            let ids = Array(0 ..< 40)
            let window = TranscriptSegmentWindow<Int>(capacity: 100, pageSize: 50)

            #expect(window.range(in: ids, id: \.self) == 0 ..< 40)
        }

        @Test
        func frozenWindowTracksItsAnchorWhenEarlierElementsAreRemoved() {
            var ids = Array(0 ..< 200)
            var window = TranscriptSegmentWindow<Int>()
            window.freeze(in: ids, id: \.self)

            ids.remove(at: 120)

            #expect(window.range(in: ids, id: \.self) == 99 ..< 199)
            #expect(ids[window.range(in: ids, id: \.self)].last == 199)
        }
    }
#endif
