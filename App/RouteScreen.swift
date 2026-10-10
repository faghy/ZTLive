import SwiftUI

/// Controllo di un percorso condiviso da Google Maps, incollandone il link.
struct RouteScreen: View {
    @StateObject private var model = RouteCheckModel()
    @State private var link = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Link di Google Maps", text: $link, axis: .vertical)
                        .lineLimit(1...3)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        PasteButton(payloadType: String.self) { strings in
                            Task { @MainActor in
                                link = strings.first ?? ""
                                model.check(link)
                            }
                        }
                        .labelStyle(.titleAndIcon)
                        Spacer()
                        Button("Controlla") { model.check(link) }
                            .disabled(link.isEmpty)
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Link")
                } footer: {
                    Text("In Google Maps imposta il percorso, tocca Condividi e scegli ZTLive. Oppure copia il link e incollalo qui.")
                }

                RouteCheckSections(model: model) { url in
                    GoogleMapsOpener.open(url) { target, completion in
                        openURL(target) { completion($0) }
                    }
                }
            }
            .navigationTitle("Percorso")
        }
    }
}
