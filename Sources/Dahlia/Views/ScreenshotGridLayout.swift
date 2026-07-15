import SwiftUI

enum ScreenshotGridLayout: String, CaseIterable, Identifiable {
    case large
    case medium
    case small

    var id: String { rawValue }

    var minimumWidth: CGFloat {
        switch self {
        case .large: 200
        case .medium: 150
        case .small: 110
        }
    }

    var label: String {
        switch self {
        case .large: L10n.large
        case .medium: L10n.medium
        case .small: L10n.small
        }
    }

    var systemImage: String {
        switch self {
        case .large: "rectangle.grid.1x2"
        case .medium: "square.grid.2x2"
        case .small: "square.grid.3x3"
        }
    }
}
