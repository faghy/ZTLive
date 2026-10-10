import ActivityKit
import SwiftUI
import WidgetKit

struct GateLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GateActivityAttributes.self) { context in
            GateActivityView(state: context.state)
                .activityBackgroundTint(context.state.status == .clear ? Color.black.opacity(0.75) : context.state.tint)
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

    /// Formato CarPlay: sopra la mappa di Google Maps, deve leggersi con un'occhiata.
    /// A strada libera resta solo un piccolo scudo, per coprire il meno possibile.
    @ViewBuilder
    private var compact: some View {
        if state.status == .clear {
            Image(systemName: state.symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(state.tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 10) {
                Image(systemName: state.symbol)
                    .font(.system(size: 34, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(state.distanceText)
                        .font(.system(size: 30, weight: .heavy))
                        .monospacedDigit()
                    Text(state.headline)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(state.tint)
        }
    }

    private var regular: some View {
        HStack(spacing: 14) {
            Image(systemName: state.symbol)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(state.status == .clear ? state.tint : .white)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.headline)
                    .font(.headline)
                    .lineLimit(1)
                Text("Veicolo: \(state.vehicle)")
                    .font(.caption)
                    .opacity(0.8)
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
