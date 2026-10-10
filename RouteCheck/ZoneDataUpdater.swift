import Foundation
import ZTLCore

/// Scarica dal repository i dati del Comune rigenerati ogni settimana da GitHub Actions,
/// così le modifiche a varchi e zone arrivano senza reinstallare l'app.
@MainActor
enum ZoneDataUpdater {
    static let baseURL = URL(string: "https://raw.githubusercontent.com/faghy/ZTLive/main/Resources/")!
    /// Tra un controllo e l'altro.
    static let interval: TimeInterval = 6 * 3600

    private static let defaults = UserDefaults.standard

    /// Data dell'ultimo file scaricato con dati nuovi; `nil` = si usano quelli inclusi nell'app.
    static var lastUpdate: Date? {
        defaults.object(forKey: "dataUpdatedAt") as? Date
    }

    static func cachedURL(for file: String) -> URL? {
        prepareCache()
        let url = directory.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Controlla se ci sono dati nuovi (al massimo ogni `interval`) e li carica. `true` se sono cambiati.
    @discardableResult
    static func updateIfNeeded(force: Bool = false) async -> Bool {
        prepareCache()
        if !force, let last = defaults.object(forKey: "dataCheckedAt") as? Date, -last.timeIntervalSinceNow < interval {
            return false
        }
        defaults.set(Date(), forKey: "dataCheckedAt")

        var changed = false
        for file in ZoneData.gateFiles {
            changed = await download(file.name) { !(try GateLoader.load(geoJSON: $0, zone: file.zone)).isEmpty } || changed
        }
        changed = await download(ZoneData.zonesFile) { !(try LocalZoneLoader.load(json: $0)).isEmpty } || changed

        if changed {
            defaults.set(Date(), forKey: "dataUpdatedAt")
            ZoneData.reload()
        }
        return changed
    }

    /// Scarica il file solo se è cambiato (ETag) e lo salva se si legge correttamente.
    private static func download(_ file: String, isValid: (Data) throws -> Bool) async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent(file), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let etagKey = "dataETag.\(file)"
        if let etag = defaults.string(forKey: etagKey), cachedURL(for: file) != nil {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        guard let result = try? await URLSession.shared.data(for: request),
              let http = result.1 as? HTTPURLResponse, http.statusCode == 200,
              (try? isValid(result.0)) == true else { return false }
        let data = result.0

        let destination = directory.appendingPathComponent(file)
        // Lo stesso contenuto di quello in uso non conta come aggiornamento.
        let current = (try? Data(contentsOf: destination))
            ?? Bundle.main.url(forResource: file, withExtension: nil).flatMap { try? Data(contentsOf: $0) }
        defaults.set(http.value(forHTTPHeaderField: "ETag"), forKey: etagKey)
        guard data != current else { return false }
        do {
            try data.write(to: destination, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZoneData", isDirectory: true)
    }

    /// Una nuova versione dell'app include dati almeno altrettanto recenti: i file scaricati prima si eliminano.
    private static func prepareCache() {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        guard defaults.string(forKey: "dataBuild") != build else { return }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("dataETag.") || key == "dataUpdatedAt" || key == "dataCheckedAt" {
            defaults.removeObject(forKey: key)
        }
        defaults.set(build, forKey: "dataBuild")
    }
}
