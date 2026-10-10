import SwiftUI
import ZTLCore

/// Risultato del controllo percorso, usato nell'app e nell'estensione di condivisione.
struct RouteCheckSections: View {
    @ObservedObject var model: RouteCheckModel
    /// Apre un link in Google Maps.
    let open: (URL) -> Void

    var body: some View {
        Section {
            Picker("Veicolo", selection: $model.vehicle) {
                ForEach(Vehicle.allCases) { vehicle in
                    Text(vehicle.label).tag(vehicle)
                }
            }
            .pickerStyle(.segmented)
        }

        switch model.phase {
        case .idle:
            EmptyView()
        case .loading:
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Controllo il percorso…")
                }
            }
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        case .done(let analysis):
            results(analysis)
        }
    }

    @ViewBuilder
    private func results(_ analysis: RouteAnalysis) -> some View {
        Section("Percorso") {
            LabeledContent("Da", value: analysis.result.originLabel)
            LabeledContent("A", value: analysis.result.destinationLabel)
            if let main = analysis.result.options.first {
                LabeledContent("Tempo stimato", value: "\(Int((main.travelTime / 60).rounded())) min · \(kilometers(main.distance))")
            }
        }

        Section {
            if analysis.mainHits.isEmpty {
                Label("Nessuna ZTL lungo il percorso", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                ForEach(analysis.mainHits, id: \.zoneID) { hit in
                    HStack(spacing: 12) {
                        Image(systemName: hit.zone.hasGates ? "camera.fill" : "xmark.octagon.fill")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading) {
                            Text(hit.zone.label).font(.headline)
                            Text(hit.name).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(hit.passTime, style: .time)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(analysis.mainHits.isEmpty ? "Esito" : "Il percorso attraversa")
        }

        if !analysis.mainHits.isEmpty {
            Section {
                if let alternative = analysis.cleanAlternative, let link = analysis.alternativeLink {
                    LabeledContent(
                        "Alternativa senza ZTL",
                        value: "\(analysis.extraMinutes == 0 ? "stesso tempo" : "+\(analysis.extraMinutes) min") · \(kilometers(alternative.distance))"
                    )
                    Button {
                        open(link)
                    } label: {
                        Label("Apri in Google Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.headline)
                    }
                } else {
                    Text("Nessuna alternativa senza ZTL tra quelle proposte da Apple Maps. Valuta un parcheggio fuori dalla zona.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Come evitarle")
            }
        }

        if let notice = model.notice {
            Section {
                Label(notice, systemImage: "doc.on.clipboard")
            }
        }

        Section {
            EmptyView()
        } footer: {
            Text("Il controllo usa i percorsi di Apple Maps tra gli stessi punti: Google Maps potrebbe scegliere strade diverse. Gli orari di passaggio sono stimati partendo adesso.")
        }
    }

    private func kilometers(_ meters: Double) -> String {
        String(format: "%.1f km", meters / 1000).replacingOccurrences(of: ".", with: ",")
    }
}

/// Apre il link nell'app Google Maps, o nel browser se l'app non c'è.
enum GoogleMapsOpener {
    static func open(_ url: URL, using openURL: @escaping (URL, @escaping (Bool) -> Void) -> Void) {
        guard let appURL = GoogleMapsLink.appURL(for: url) else {
            openURL(url) { _ in }
            return
        }
        openURL(appURL) { accepted in
            if !accepted {
                openURL(url) { _ in }
            }
        }
    }
}
