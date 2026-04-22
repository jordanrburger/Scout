import SwiftUI
import AppKit

/// Editorial + native-macOS design system.
///
/// Source of truth for the Scout refresh: warm paper + deep ink surfaces,
/// muted accent, priority hues at matched chroma, and a typographic system
/// that mirrors the handoff bundle's Newsreader / JetBrains Mono / SF stack.
enum DS {

    // MARK: - Semantic palette

    /// Paper is the page. Sunk is a recessed well. Raised is a lifted card.
    enum Paper {
        static let base   = Color("Paper",       bundle: nil, fallbackLight: .sRGB(0.985, 0.984, 0.975, 1), fallbackDark: .sRGB(0.145, 0.147, 0.160, 1))
        static let sunk   = Color("PaperSunk",   bundle: nil, fallbackLight: .sRGB(0.960, 0.958, 0.948, 1), fallbackDark: .sRGB(0.118, 0.120, 0.132, 1))
        static let raised = Color("PaperRaised", bundle: nil, fallbackLight: .sRGB(1.000, 0.999, 0.995, 1), fallbackDark: .sRGB(0.180, 0.182, 0.197, 1))
    }

    /// Ink is the foreground type. 1 is primary, 4 is the faintest UI hint.
    enum Ink {
        static let p1 = Color(fallbackLight: .sRGB(0.125, 0.130, 0.195, 1), fallbackDark: .sRGB(0.950, 0.948, 0.940, 1))
        static let p2 = Color(fallbackLight: .sRGB(0.310, 0.315, 0.380, 1), fallbackDark: .sRGB(0.780, 0.775, 0.760, 1))
        static let p3 = Color(fallbackLight: .sRGB(0.510, 0.510, 0.565, 1), fallbackDark: .sRGB(0.600, 0.598, 0.585, 1))
        static let p4 = Color(fallbackLight: .sRGB(0.660, 0.660, 0.700, 1), fallbackDark: .sRGB(0.440, 0.438, 0.425, 1))
    }

    /// Hairline rules.
    enum Rule {
        static let soft = Color(fallbackLight: .sRGB(0.91, 0.905, 0.890, 1), fallbackDark: .sRGB(0.240, 0.244, 0.260, 1))
        static let hard = Color(fallbackLight: .sRGB(0.87, 0.865, 0.848, 1), fallbackDark: .sRGB(0.300, 0.305, 0.325, 1))
    }

    /// Editorial amber accent. `ink` is the readable-on-paper variant.
    enum Accent {
        static let fill = Color(fallbackLight: .sRGB(0.745, 0.540, 0.240, 1), fallbackDark: .sRGB(0.915, 0.790, 0.470, 1))
        static let ink  = Color(fallbackLight: .sRGB(0.555, 0.380, 0.120, 1), fallbackDark: .sRGB(0.940, 0.840, 0.560, 1))
        static let wash = Color(fallbackLight: .sRGB(0.975, 0.945, 0.880, 1), fallbackDark: .sRGB(0.310, 0.250, 0.140, 1))
    }

    /// Priority hues sit in the same chroma family on purpose — they read as a
    /// set, not a stoplight.
    enum Priority {
        static let urgent   = Color(fallbackLight: .sRGB(0.750, 0.310, 0.200, 1), fallbackDark: .sRGB(0.880, 0.450, 0.340, 1))
        static let todo     = Color(fallbackLight: .sRGB(0.840, 0.640, 0.170, 1), fallbackDark: .sRGB(0.910, 0.760, 0.340, 1))
        static let watch    = Color(fallbackLight: .sRGB(0.390, 0.600, 0.390, 1), fallbackDark: .sRGB(0.500, 0.740, 0.520, 1))
        static let personal = Color(fallbackLight: .sRGB(0.540, 0.440, 0.740, 1), fallbackDark: .sRGB(0.700, 0.620, 0.880, 1))
        static let done     = Color(fallbackLight: .sRGB(0.620, 0.620, 0.640, 1), fallbackDark: .sRGB(0.520, 0.520, 0.535, 1))
    }

    /// Status feedback colors (meeting-now, success, warn, error).
    enum Status {
        static let ok   = Color(fallbackLight: .sRGB(0.300, 0.580, 0.385, 1), fallbackDark: .sRGB(0.430, 0.720, 0.500, 1))
        static let warn = Color(fallbackLight: .sRGB(0.720, 0.510, 0.180, 1), fallbackDark: .sRGB(0.880, 0.660, 0.300, 1))
        static let err  = Color(fallbackLight: .sRGB(0.750, 0.280, 0.200, 1), fallbackDark: .sRGB(0.880, 0.420, 0.340, 1))
    }

    // MARK: - Typography

    /// Reading voice. Falls back to Apple's "New York" serif on macOS.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if NSFont(name: "Newsreader", size: size) != nil {
            return .custom("Newsreader", size: size).weight(weight)
        }
        if NSFont(name: "New York", size: size) != nil {
            return .custom("New York", size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .serif)
    }

    /// IDs, timestamps, key counts.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if NSFont(name: "JetBrains Mono", size: size) != nil {
            return .custom("JetBrains Mono", size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    /// UI chrome (buttons, labels, filters). SF Pro on macOS.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // MARK: - Kind → priority mapping

    /// Map a section kind to its priority dot hue. Keeps the existing
    /// `ActionSection.Kind` API intact.
    static func priorityColor(_ kind: ActionSection.Kind) -> Color {
        switch kind {
        case .urgent:   return Priority.urgent
        case .todo:     return Priority.todo
        case .watching: return Priority.watch
        case .personal: return Priority.personal
        case .done:     return Priority.done
        case .focus:    return Accent.fill
        case .meetings: return Accent.fill
        case .digest:   return Ink.p3
        case .neutral:  return Ink.p4
        }
    }

    /// Small glyph shown in section headers (matches the handoff bundle).
    static func kindGlyph(_ kind: ActionSection.Kind) -> String {
        switch kind {
        case .urgent:   return "🔴"
        case .todo:     return "🟡"
        case .watching: return "🟢"
        case .personal: return "🏡"
        case .focus:    return "💡"
        case .meetings: return "📅"
        case .done:     return "✓"
        case .digest:   return "📋"
        case .neutral:  return "·"
        }
    }
}

// MARK: - Color bridging

private extension Color {
    /// Light/dark sRGB fallback pair — renders the editorial palette without
    /// requiring asset-catalog entries.
    init(fallbackLight: NSColor, fallbackDark: NSColor) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil
            return dark ? fallbackDark : fallbackLight
        })
    }

    /// Optional named asset with sRGB fallback for machines without the
    /// asset catalog updated yet.
    init(_ name: String, bundle: Bundle?, fallbackLight: NSColor, fallbackDark: NSColor) {
        if NSColor(named: NSColor.Name(name), bundle: bundle) != nil {
            self = Color(nsColor: NSColor(named: NSColor.Name(name), bundle: bundle)!)
        } else {
            self.init(fallbackLight: fallbackLight, fallbackDark: fallbackDark)
        }
    }
}

private extension NSColor {
    static func sRGB(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - Shared surfaces

/// Editorial card chrome. Uses the raised paper fill with a hairline rule —
/// no drop shadows (they eat scroll perf).
struct EditorialCard: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(DS.Paper.raised))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(DS.Rule.soft, lineWidth: 0.5))
    }
}

extension View {
    func editorialCard(padding: CGFloat = 16, cornerRadius: CGFloat = 8) -> some View {
        modifier(EditorialCard(padding: padding, cornerRadius: cornerRadius))
    }
}

/// The small boxed chip/pill used for deep-links, tags, and action buttons.
struct EditorialChipBackground: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(DS.Paper.raised)
            RoundedRectangle(cornerRadius: 5).strokeBorder(DS.Rule.hard, lineWidth: 0.5)
        }
    }
}

/// A single hairline rule, full width, for separating editorial sections.
struct EditorialRule: View {
    var color: Color = DS.Rule.soft
    var body: some View {
        Rectangle().fill(color).frame(height: 0.5)
    }
}
