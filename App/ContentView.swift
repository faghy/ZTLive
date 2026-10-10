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
                    LabeledContent("Varchi e zone", value: "\(model.gatesCount) varchi · \(model.zonesCount) zone")
                    LabeledContent("Posizione", value: authorizationText)
                    LabeledContent("Live Activity", value: model.liveActivitiesEnabled ? "Abilitate" : "Disabilitate")
                }

                Section {
                    Picker("Veicolo", selection: $model.vehicle) {
                        ForEach(Vehicle.allCases) { vehicle in
                            Text(vehicle.label).tag(vehicle)
                        }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Collegato a", value: deviceText)
                } header: {
                    Text("Veicolo")
                } footer: {
                    Text("Con CarPlay o l'interfono collegati, scegli il veicolo una volta: ZTLive lo ricorderà e lo selezionerà da solo le volte successive.")
                }

                Section {
                    Toggle("Avvisi vocali", isOn: $model.voiceEnabled)
                    Toggle("ZTL e aree pedonali", isOn: $model.includeLocalZones)
                    Toggle("Varchi Area B", isOn: $model.includeAreaB)
                    Toggle("Ignora orari (prove)", isOn: $model.ignoreSchedule)
                } header: {
                    Text("Avvisi")
                } footer: {
                    Text("Area C: solo in auto, feriali 7:30-19:30 esclusi i festivi. ZTL e aree pedonali: sempre attive, salvo gli orari indicati dal Comune; ignorate in moto se le moto sono ammesse.")
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

    private var deviceText: String {
        guard let device = model.connectedDevice else { return "Nessun dispositivo" }
        return model.vehicleIsAutomatic ? "\(device.name) (automatico)" : device.name
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
