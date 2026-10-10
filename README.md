# ZTLive

App iOS che avvisa quando ti avvicini a un varco ZTL di Milano (Area C, Area B, ZTL locali) mentre navighi con Google Maps, in auto o in moto.

Gli avvisi arrivano come **Live Activity**, visibile su CarPlay, schermata di blocco e Dynamic Island, e opzionalmente a voce.

## Stato: prototipo

Questo primo prototipo serve a verificare che:

1. la Live Activity si aggiorni in background mentre Google Maps è in primo piano;
2. la Live Activity compaia su CarPlay, in auto e sul TFT della moto;
3. l'app si installi e funzioni con un Apple ID gratuito tramite SideStore.

Funzioni presenti:

- varchi di Area C e Area B dagli open data del Comune di Milano;
- avviso circa 400 m prima del varco nella direzione di marcia, livello "imminente" sotto i 120 m;
- filtro per veicolo: in moto l'Area C viene ignorata;
- orari di Area B e Area C (feriali 7:30–19:30), disattivabili per le prove;
- modalità simulazione, per provare Live Activity e CarPlay da fermi.

## Struttura

| Percorso | Contenuto |
|---|---|
| `Packages/ZTLCore` | Logica pura (geometria, varchi, orari), testata anche su Linux |
| `App` | App SwiftUI: GPS in background, Live Activity, voce |
| `Widget` | Estensione con la grafica della Live Activity |
| `Shared` | Modello dati condiviso tra app ed estensione |
| `Resources` | Dataset dei varchi in GeoJSON |
| `project.yml` | Definizione del progetto per XcodeGen |

## Build

Non serve un Mac: ogni push su `main` compila l'app su GitHub Actions. L'IPA non firmata viene pubblicata nella release [`prototype`](../../releases/tag/prototype).

I test della logica si possono eseguire ovunque ci sia Swift:

```sh
swift test --package-path Packages/ZTLCore
```

## Installazione con SideStore

1. Installa [SideStore](https://sidestore.io) sull'iPhone seguendo la guida ufficiale. La configurazione iniziale richiede un computer, anche Linux.
2. Dall'iPhone scarica `ZTLive.ipa` dalla release `prototype`.
3. In SideStore: **My Apps → +** e scegli il file scaricato.
4. SideStore rinnova la firma ogni 7 giorni in automatico.
5. Al primo avvio concedi la posizione. Controlla anche che le Live Activity siano attive in Impostazioni → ZTLive.

## Dati

Fonte: [Portale Open Data del Comune di Milano](https://dati.comune.milano.it), licenza CC BY 4.0.

- [Varchi Area C](https://dati.comune.milano.it/dataset/ds82_infogeo_varchi_elettronici_localizzazione_) (ds82)
- [Varchi Area B](https://dati.comune.milano.it/dataset/ds959-varchi-areab) (ds959)
- [Aree pedonali e ZTL](https://dati.comune.milano.it/dataset/ds51_trafficotrasporti_aree_pedonali_ztl) (ds51), da integrare nelle prossime versioni

Le informazioni hanno valore indicativo: fanno fede la segnaletica e gli atti ufficiali del Comune.
