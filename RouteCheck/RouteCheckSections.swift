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

        if !model.details.isEmpty {
            Section {
                DisclosureGroup("Dettagli") {
                    Text(model.details.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
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
                Label(analysis.destinationZone == nil ? "Nessuna ZTL lungo il percorso" : "Nessuna ZTL lungo il percorso in auto", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                if let zone = analysis.destinationZone {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.walk")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading) {
                            Text("La destinazione è in \(zone.zone.label)").font(.headline)
                            Text("\(zone.name): in auto arrivi a circa \(meters(analysis.lastLegDistance)), poi prosegui senza auto.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
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

        if let reopens = analysis.areaCReopens {
            Section {
                Label("Area C non attiva ora: riapre \(reopeningText(reopens))", systemImage: "info.circle")
            }
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
                    Text("Nessuna alternativa in auto senza ZTL tra quelle proposte da Apple Maps: puoi lasciare l'auto prima della zona e proseguire con un altro mezzo.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Come evitarle")
            }
        }

        if analysis.needsLastLeg {
            lastLeg(analysis)
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

    /// Stesso percorso in auto fino a poco prima della zona, poi a piedi, in bici o con i mezzi.
    @ViewBuilder
    private func lastLeg(_ analysis: RouteAnalysis) -> some View {
        let switchPoint = analysis.switchPoint
        Section {
            Picker("Mezzo", selection: $model.lastLegMode) {
                ForEach(TravelMode.lastLegModes, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if let switchPoint {
                VStack(alignment: .leading, spacing: 2) {
                    Text("1. In auto fino a \(model.switchPointName ?? "poco prima della ZTL")")
                    Text(analysis.mainHits.isEmpty ? "Fine del percorso in auto, al bordo della zona." : "Stesso percorso, ti fermi prima di entrare.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    open(analysis.drivingLegLink(to: switchPoint))
                } label: {
                    Label("Apri in Google Maps", systemImage: "car.fill")
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(switchPoint == nil ? "" : "2. ")\(model.lastLegMode.label) fino a \(analysis.result.destinationLabel)")
                Text("Circa \(meters(analysis.lastLegDistance)) rimasti")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                open(analysis.lastLegLink(from: switchPoint, mode: model.lastLegMode))
            } label: {
                Label("Apri in Google Maps", systemImage: model.lastLegMode.symbol)
            }
        } header: {
            Text(switchPoint == nil ? "Prosegui senza auto" : analysis.mainHits.isEmpty ? "Ultimo tratto senza auto" : "Lascia l'auto prima della ZTL")
        } footer: {
            if switchPoint != nil {
                Text("Google Maps non accetta due mezzi nello stesso link: apri il primo tratto e, arrivato, torna qui per il secondo.")
            }
        }
    }

    /// "oggi alle 7:30", "domani alle 7:30", "lunedì alle 7:30".
    private func reopeningText(_ date: Date) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(date) {
            day = "oggi"
        } else if calendar.isDateInTomorrow(date) {
            day = "domani"
        } else {
            day = date.formatted(Date.FormatStyle().weekday(.wide).locale(Locale(identifier: "it_IT")))
        }
        return "\(day) alle \(date.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .omitted)).minute().locale(Locale(identifier: "it_IT"))))"
    }

    /// Sotto il chilometro in metri arrotondati, sopra in chilometri.
    private func meters(_ value: Double) -> String {
        value < 1000 ? "\(Int((value / 10).rounded()) * 10) m" : kilometers(value)
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

extension TravelMode {
    static let lastLegModes: [TravelMode] = [.walking, .bicycling, .transit]

    var label: String {
        switch self {
        case .driving: return "In auto"
        case .walking: return "A piedi"
        case .bicycling: return "In bici"
        case .transit: return "Con i mezzi"
        }
    }

    var symbol: String {
        switch self {
        case .driving: return "car.fill"
        case .walking: return "figure.walk"
        case .bicycling: return "bicycle"
        case .transit: return "tram.fill"
        }
    }
}
