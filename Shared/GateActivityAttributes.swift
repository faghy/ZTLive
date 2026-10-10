import ActivityKit
import SwiftUI

/// Dati della Live Activity, condivisi tra app ed estensione widget.
struct GateActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Status: Int, Codable, Hashable, Comparable {
            case clear
            case approaching
            case imminent

            static func < (lhs: Status, rhs: Status) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }

        var status: Status
        var gateName: String
        var zone: String
        /// Metri dal varco, arrotondati a 10 m.
        var distance: Int
        var vehicle: String

        static func clear(vehicle: String) -> ContentState {
            ContentState(status: .clear, gateName: "", zone: "", distance: 0, vehicle: vehicle)
        }
    }

    var title: String
}

extension GateActivityAttributes.ContentState {
    var symbol: String {
        switch status {
        case .clear: return "checkmark.shield.fill"
        case .approaching: return "exclamationmark.triangle.fill"
        case .imminent: return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch status {
        case .clear: return .green
        case .approaching: return .orange
        case .imminent: return .red
        }
    }

    var headline: String {
        status == .clear ? "Nessun varco vicino" : "\(zone) · \(gateName)"
    }

    var distanceText: String {
        status == .clear ? "—" : "\(distance) m"
    }
}
