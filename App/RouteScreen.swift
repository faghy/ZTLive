import SwiftUI

/// Controllo di un percorso condiviso da Google Maps, incollandone il link.
struct RouteScreen: View {
    @StateObject private var model = RouteCheckModel()
    @State private var link = ""
    @FocusState private var linkFocused: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Link di Google Maps", text: $link)
                        .focused($linkFocused)
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(check)
                    HStack {
                        PasteButton(payloadType: String.self) { strings in
                            Task { @MainActor in
                                link = strings.first ?? ""
                                check()
                            }
                        }
                        .labelStyle(.titleAndIcon)
                        Spacer()
                        Button("Controlla", action: check)
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
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fine") { linkFocused = false }
                }
            }
        }
    }

    private func check() {
        linkFocused = false
        guard !link.isEmpty else { return }
        model.check(link)
    }
}
