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
    var statusText: String { active ? t("Aktywny", "Active") : pending ? t("Oczekuje", "Pending") : t("Zapisany", "Stored") }
    /// The control unit in the owner's language: "Silnik (DME)".
    var unitText: String {
        let pl: [String: String] = [
            "12": "Silnik", "13": "Silnik 2", "18": "Skrzynia biegów", "29": "Hamulce / ESP", "30": "Wspomaganie kierownicy",
            "01": "Poduszki powietrzne", "37": "Audio", "40": "Moduł nadwozia", "10": "Bramka (gateway)", "5D": "Kamera przednia",
            "60": "Zegary", "61": "Telematyka", "63": "iDrive", "64": "Czujniki parkowania", "2C": "Czujniki parkowania",
            "78": "Klimatyzacja", "1D": "Zbiornik paliwa", "21": "Radar przedni", "43": "Reflektor lewy", "44": "Reflektor prawy",
            "6D": "Fotel", "56": "Dach", "38": "Napęd xDrive", "0D": "Klapa bagażnika", "67": "Kontroler iDrive",
            "45": "Kamera kierowcy", "23": "Czujniki asystentów", "06": "Kamery", "76": "Amortyzatory", "39": "Wspomaganie hamulca",
        ]
        let en: [String: String] = [
            "12": "Engine", "13": "Engine 2", "18": "Gearbox", "29": "Brakes / stability", "30": "Power steering",
            "01": "Airbags", "37": "Audio", "40": "Body module", "10": "Gateway", "5D": "Front camera",
            "60": "Instrument cluster", "61": "Telematics", "63": "iDrive", "64": "Parking sensors", "2C": "Parking sensors",
            "78": "Climate", "1D": "Fuel tank", "21": "Front radar", "43": "Left headlight", "44": "Right headlight",
            "6D": "Seat", "56": "Roof", "38": "xDrive", "0D": "Tailgate", "67": "iDrive controller",
            "45": "Driver camera", "23": "Assist sensors", "06": "Cameras", "76": "Dampers", "39": "Brake booster",
        ]
        let short = unit.split(separator: " ").first.map(String.init) ?? unit      // DME, DSC, KAFAS …
        guard let name = (Lang.current == .pl ? pl : en)[address] else { return unit }
        return short.hasPrefix("ECU") ? name : "\(name) (\(short))"
    }
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
