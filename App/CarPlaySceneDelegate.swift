// Copyright (C) 2026 Serafino Christian
// SPDX-License-Identifier: GPL-3.0-or-later

import CarPlay
import Combine

/// Schermata di ZTLive su CarPlay (categoria Driving Task): stato dell'avviso e pulsante per avviare o fermare.
///
/// Non ancora attiva: serve il permesso CarPlay di Apple (`com.apple.developer.carplay-driving-task`).
/// Quando arriva, si aggiungono l'entitlement e la scena `CPTemplateApplicationSceneSessionRoleApplication`
/// in `project.yml`, con questa classe come delegate.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    /// Apple chiede di non aggiornare i template più spesso di ogni 10 secondi.
    private static let minimumRefresh: TimeInterval = 10

    private let model = AppModel.shared
    private var interfaceController: CPInterfaceController?
    private var template: CPInformationTemplate?
    private var subscriptions = Set<AnyCancellable>()
    private var lastRefresh = Date.distantPast
    private var lastStatus: AppModel.State.Status?
    private var lastMode: RunMode?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        let template = CPInformationTemplate(title: "ZTLive", layout: .leading, items: items(), actions: actions())
        self.template = template
        interfaceController.setRootTemplate(template, animated: false, completion: nil)
        lastRefresh = Date()
        lastStatus = model.state.status
        lastMode = model.mode

        model.$state
            .combineLatest(model.$mode)
            .receive(on: RunLoop.main)
            .sink { [weak self] state, mode in
                MainActor.assumeIsolated { self?.refresh(status: state.status, mode: mode) }
            }
            .store(in: &subscriptions)
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        subscriptions.removeAll()
        template = nil
        self.interfaceController = nil
    }

    /// Un cambio di livello (via libera → avvicinamento → imminente) o di modalità si mostra subito,
    /// la sola distanza al massimo ogni 10 s.
    private func refresh(status: AppModel.State.Status, mode: RunMode) {
        guard let template else { return }
        let now = Date()
        guard status != lastStatus || mode != lastMode || now.timeIntervalSince(lastRefresh) >= Self.minimumRefresh else { return }
        lastRefresh = now
        lastStatus = status
        lastMode = mode
        template.items = items()
        template.actions = actions()
    }

    private func items() -> [CPInformationItem] {
        let state = model.state
        guard model.mode != .off else {
            return [CPInformationItem(title: "Avvisi spenti", detail: "Premi Avvia per essere avvisato prima dei varchi")]
        }
        var items = [CPInformationItem(title: statusTitle(state.status), detail: state.headline)]
        if state.status != .clear {
            items.append(CPInformationItem(title: "Distanza", detail: state.distanceText))
        }
        items.append(CPInformationItem(title: "Veicolo", detail: state.vehicle))
        if model.mode == .simulation {
            items.append(CPInformationItem(title: "Simulazione", detail: "I varchi non sono reali"))
        }
        return items
    }

    private func actions() -> [CPTextButton] {
        if model.mode == .off {
            return [CPTextButton(title: "Avvia", textStyle: .confirm) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.startMonitoring() }
            }]
        }
        return [CPTextButton(title: "Ferma", textStyle: .cancel) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.stop() }
        }]
    }

    private func statusTitle(_ status: AppModel.State.Status) -> String {
        switch status {
        case .clear: return "Via libera"
        case .approaching: return "Varco in avvicinamento"
        case .imminent: return "Varco imminente"
        }
    }
}
