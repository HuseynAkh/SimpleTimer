import SwiftUI
#if os(iOS)
import UIKit
#endif

/// One palette for iPhone, Live Activities and Apple Watch.
enum Palette {
    static let names = ["violet", "orange", "teal", "green", "rose", "blue"]

    private static func components(_ name: String) -> (Double, Double, Double) {
        switch name {
        case "orange": (0.96, 0.44, 0.12)
        case "teal": (0.04, 0.67, 0.62)
        case "green": (0.37, 0.65, 0.23)
        case "rose": (0.86, 0.30, 0.48)
        case "blue": (0.25, 0.52, 0.92)
        default: (0.57, 0.40, 0.89)
        }
    }

    static func color(_ name: String) -> Color {
        let base = components(name)
        return Color(red: base.0, green: base.1, blue: base.2)
    }

    static func chartColor(_ name: String) -> Color {
        #if os(iOS)
        Color(UIColor { traits in
            let base = components(name)
            let scale = traits.userInterfaceStyle == .dark ? 1.0 : 0.75
            return UIColor(red: base.0 * scale, green: base.1 * scale, blue: base.2 * scale, alpha: 1)
        })
        #else
        color(name)
        #endif
    }
}
