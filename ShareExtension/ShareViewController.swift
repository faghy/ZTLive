import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Riceve il percorso condiviso da Google Maps (Condividi → ZTLive) e mostra l'esito del controllo.
final class ShareViewController: UIViewController {
    private let model = RouteCheckModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareRootView(
            model: model,
            open: { [weak self] url in self?.openInGoogleMaps(url) },
            close: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        )
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        Task {
            model.check(await sharedText())
        }
    }

    /// Google Maps condivide un link, a volte dentro un testo ("Indicazioni per ...: https://...").
    private func sharedText() async -> String {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        var texts = items.compactMap { $0.attributedContentText?.string }
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                texts.append(url.absoluteString)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                texts.append(text)
            }
        }
        return texts.joined(separator: " ")
    }

    /// Le estensioni non possono aprire link direttamente: si passa dall'applicazione nella catena dei responder.
    /// Se non è possibile, il link viene copiato per incollarlo in Google Maps.
    private func openInGoogleMaps(_ url: URL) {
        guard application() != nil else {
            UIPasteboard.general.url = url
            model.notice = "Link copiato: aprilo incollandolo in Safari o in Google Maps."
            return
        }
        GoogleMapsOpener.open(url) { [weak self] target, completion in
            self?.application()?.open(target, options: [:]) { success in
                completion(success)
                if success {
                    self?.extensionContext?.completeRequest(returningItems: nil)
                }
            }
        }
    }

    private func application() -> UIApplication? {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                return application
            }
            responder = current.next
        }
        return nil
    }
}

private struct ShareRootView: View {
    @ObservedObject var model: RouteCheckModel
    let open: (URL) -> Void
    let close: () -> Void

    var body: some View {
        NavigationStack {
            List {
                RouteCheckSections(model: model, open: open)
            }
            .navigationTitle("ZTLive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine", action: close)
                }
            }
        }
    }
}
