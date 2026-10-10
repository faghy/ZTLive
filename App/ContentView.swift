import CoreLocation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Stato") {
                    HStack(spacing: 14) {
                        Image(systemName: model.state.symbol)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(model.state.tint)
                        VStack(alignment: .leading) {
                            Text(model.state.headline)
                                .font(.headline)
                            Text(modeText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(model.state.distanceText)
                            .font(.title2.bold())
                            .monospacedDigit()
                    }
                    LabeledContent("Aggiornamenti GPS", value: "\(model.gpsUpdates)")
                    LabeledContent("Varchi caricati", value: "\(model.gatesCount)")
                    LabeledContent("Posizione", value: authorizationText)
                    LabeledContent("Live Activity", value: model.liveActivitiesEnabled ? "Abilitate" : "Disabilitate")
                }

                Section("Impostazioni") {
                    Picker("Veicolo", selection: $model.vehicle) {
                        ForEach(Vehicle.allCases) { vehicle in
                            Text(vehicle.label).tag(vehicle)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Avvisi vocali", isOn: $model.voiceEnabled)
                    Toggle("Varchi Area B", isOn: $model.includeAreaB)
                    Toggle("Ignora orari (prove)", isOn: $model.ignoreSchedule)
                }

                Section {
                    Button("Avvia monitoraggio reale") { model.startMonitoring() }
                    Button("Avvia simulazione") { model.startSimulation() }
                    Button("Ferma", role: .destructive) { model.stop() }
                        .disabled(model.mode == .off)
                } header: {
                    Text("Prova")
                } footer: {
                    Text("Simulazione: avvicinamento finto a un varco ogni 2 secondi. Avviala, apri Google Maps e collega CarPlay: la Live Activity deve continuare ad aggiornarsi. Il contatore GPS conferma che l'app lavora in background.")
                }
            }
            .navigationTitle("ZTLive")
        }
    }

    private var modeText: String {
        switch model.mode {
        case .off: return "Fermo"
        case .real: return "Monitoraggio reale"
        case .simulation: return "Simulazione"
        }
    }

    private var authorizationText: String {
        switch model.authorization {
        case .authorizedAlways: return "Sempre"
        case .authorizedWhenInUse: return "Mentre usi l'app"
        case .denied, .restricted: return "Negata"
        default: return "Da chiedere"
        }
    }
}
