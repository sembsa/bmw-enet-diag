// Theme - BMW-inspired accents on standard macOS materials: BMW blue, the three-colour stripe, status colours.
import EnetCore
import SwiftUI

enum Theme {
    static let blue = Color(red: 0.11, green: 0.41, blue: 0.83)       // #1C69D4
    static let navy = Color(red: 0.04, green: 0.12, blue: 0.23)       // #0B1F3A
    static let red = Color(red: 0.84, green: 0.16, blue: 0.16)
    static let lightBlue = Color(red: 0.33, green: 0.65, blue: 0.93)
}

/// The three-colour motorsport stripe.
struct Stripe: View {
    var height: CGFloat = 4
    var body: some View {
        HStack(spacing: 0) { Theme.lightBlue; Theme.navy; Theme.red }
            .frame(height: height).clipShape(Capsule())
    }
}

extension Fault {
    var statusText: String { active ? "ACTIVE" : pending ? "PENDING" : "STORED" }
    var statusColor: Color { active ? Theme.red : pending ? .orange : .secondary }
    var kindSymbol: String {
        switch kind {
        case "engine": "engine.combustion"
        case "drive": "gearshape.2"
        case "chassis": "steeringwheel"
        case "safety": "airbag.fill"
        case "assist": "camera.viewfinder"
        case "body": "car.side"
        case "lights": "headlight.high.beam"
        case "infotainment": "music.note.tv"
        default: "cpu"
        }
    }
}

extension Hint.Severity {
    var color: Color { switch self { case .workshop: Theme.red; case .watch: .orange; case .info: Theme.blue } }
    var label: String {
        switch self {
        case .workshop: t("Do warsztatu", "Workshop")
        case .watch: t("Obserwuj", "Watch")
        case .info: t("Informacja", "Info")
        }
    }
    var symbol: String { switch self { case .workshop: "wrench.and.screwdriver.fill"; case .watch: "eye.fill"; case .info: "info.circle.fill" } }
}

extension Finding.Level {
    var color: Color { switch self { case .ok: .green; case .watch: .orange; case .problem: Theme.red; case .unknown: .secondary } }
    var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .watch: "exclamationmark.circle.fill"
        case .problem: "xmark.octagon.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

struct Pill: View {
    let text: String, color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.bold)).tracking(0.5)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// A rounded card on the window's material.
struct Card<Content: View>: View {
    var title: String? = nil
    var symbol: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Label(title, systemImage: symbol ?? "circle").font(.headline).foregroundStyle(.secondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
    }
}

/// Section title with the stripe under it.
struct Header: View {
    let title: String, subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.largeTitle.weight(.semibold))
            Text(subtitle).foregroundStyle(.secondary)
            Stripe(height: 3).frame(width: 64)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
