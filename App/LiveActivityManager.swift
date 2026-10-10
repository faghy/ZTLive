import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    private var activity: Activity<GateActivityAttributes>?
    private var lastState: GateActivityAttributes.ContentState?

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var isRunning: Bool {
        activity != nil
    }

    func start(state: GateActivityAttributes.ContentState) {
        endAll()
        do {
            activity = try Activity.request(
                attributes: GateActivityAttributes(title: "ZTLive"),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            lastState = state
        } catch {
            print("Live Activity non avviata: \(error)")
        }
    }

    /// Aggiorna solo se lo stato è cambiato. `alert` accende lo schermo e mostra il banner espanso.
    func update(_ state: GateActivityAttributes.ContentState, alert: AlertConfiguration? = nil) {
        guard let activity, state != lastState else { return }
        lastState = state
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(120))
        Task {
            await activity.update(content, alertConfiguration: alert)
        }
    }

    /// Chiude anche eventuali Live Activity rimaste aperte da sessioni precedenti.
    func endAll() {
        // Elenco letto subito, prima che `start` ne crei una nuova.
        let existing = Activity<GateActivityAttributes>.activities
        activity = nil
        lastState = nil
        Task {
            for activity in existing {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
