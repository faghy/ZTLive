import ActivityKit
import SwiftUI
import WidgetKit

struct GateLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GateActivityAttributes.self) { context in
            GateActivityView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.symbol)
                        .font(.title)
                        .foregroundStyle(context.state.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.distanceText)
                        .font(.title2.bold())
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.headline)
                        .font(.headline)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: context.state.symbol)
                    .foregroundStyle(context.state.tint)
            } compactTrailing: {
                Text(context.state.distanceText)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: context.state.symbol)
                    .foregroundStyle(context.state.tint)
            }
        }
        // .small è il formato usato da CarPlay e Apple Watch.
        .supplementalActivityFamilies([.small, .medium])
    }
}

struct GateActivityView: View {
    @Environment(\.activityFamily) private var family
    let state: GateActivityAttributes.ContentState

    var body: some View {
        if family == .small {
            compact
        } else {
            regular
        }
    }

    /// Layout grande e leggibile a colpo d'occhio, pensato per lo schermo CarPlay.
    private var compact: some View {
        HStack(spacing: 10) {
            Image(systemName: state.symbol)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(state.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.distanceText)
                    .font(.system(size: 28, weight: .heavy))
                    .monospacedDigit()
                Text(state.status == .clear ? "Via libera" : state.gateName)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(8)
    }

    private var regular: some View {
        HStack(spacing: 14) {
            Image(systemName: state.symbol)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(state.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.headline)
                    .font(.headline)
                    .lineLimit(1)
                Text("Veicolo: \(state.vehicle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(state.distanceText)
                .font(.system(size: 30, weight: .heavy))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding()
    }
}
