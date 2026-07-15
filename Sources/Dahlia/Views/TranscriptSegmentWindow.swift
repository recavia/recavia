struct TranscriptSegmentWindow<ID: Equatable>: Equatable {
    static var defaultCapacity: Int { 100 }
    static var defaultPageSize: Int { 50 }

    let capacity: Int
    let pageSize: Int
    private var fixedUpperBound: Int?
    private var fixedLastID: ID?

    init(
        capacity: Int = Self.defaultCapacity,
        pageSize: Int = Self.defaultPageSize
    ) {
        precondition(capacity > 0)
        precondition(pageSize > 0 && pageSize <= capacity)
        self.capacity = capacity
        self.pageSize = pageSize
    }

    var isFollowingLatest: Bool {
        fixedUpperBound == nil
    }

    func range<Element>(
        in elements: [Element],
        id: KeyPath<Element, ID>
    ) -> Range<Int> {
        let upperBound = resolvedUpperBound(in: elements, id: id)
        return max(0, upperBound - capacity) ..< upperBound
    }

    mutating func freeze<Element>(
        in elements: [Element],
        id: KeyPath<Element, ID>
    ) {
        setFixedUpperBound(elements.count, in: elements, id: id)
    }

    mutating func followLatest() {
        fixedUpperBound = nil
        fixedLastID = nil
    }

    @discardableResult
    mutating func shiftEarlier<Element>(
        in elements: [Element],
        id: KeyPath<Element, ID>
    ) -> Bool {
        let currentRange = range(in: elements, id: id)
        guard currentRange.lowerBound > 0 else { return false }

        let newLowerBound = max(0, currentRange.lowerBound - pageSize)
        setFixedUpperBound(min(elements.count, newLowerBound + capacity), in: elements, id: id)
        return true
    }

    @discardableResult
    mutating func shiftLater<Element>(
        in elements: [Element],
        id: KeyPath<Element, ID>
    ) -> Bool {
        let currentRange = range(in: elements, id: id)
        guard currentRange.upperBound < elements.count else { return false }

        setFixedUpperBound(min(elements.count, currentRange.upperBound + pageSize), in: elements, id: id)
        return true
    }

    private func resolvedUpperBound<Element>(
        in elements: [Element],
        id: KeyPath<Element, ID>
    ) -> Int {
        if let fixedLastID,
           let anchorIndex = elements.lastIndex(where: { $0[keyPath: id] == fixedLastID }) {
            return anchorIndex + 1
        }

        return min(fixedUpperBound ?? elements.count, elements.count)
    }

    private mutating func setFixedUpperBound<Element>(
        _ upperBound: Int,
        in elements: [Element],
        id: KeyPath<Element, ID>
    ) {
        let clampedUpperBound = min(max(0, upperBound), elements.count)
        fixedUpperBound = clampedUpperBound
        fixedLastID = clampedUpperBound > 0 ? elements[clampedUpperBound - 1][keyPath: id] : nil
    }
}
