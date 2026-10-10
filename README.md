# ZTLive

**English** · [Italiano](README.it.md)

iOS app that warns you when you are approaching a Milan restricted traffic zone gate (Area C, Area B, local ZTLs) while navigating with Google Maps, by car or by motorcycle.

Alerts are shown as a **Live Activity**, visible on CarPlay, the Lock Screen and the Dynamic Island, with optional voice announcements.

## Features

- **Area C and Area B gates** from the City of Milan open data: alert about 400 m before a gate in your direction of travel, "imminent" level below 120 m.
- **Local ZTLs and pedestrian areas** (Brera, Sarpi, Navigli, Ticinese…): alert when your direction of travel leads into the zone, up to 300 m ahead.
- **Schedules**: Area B and C on weekdays 7:30–19:30, public holidays excluded (national holidays and Sant'Ambrogio). Local ZTLs and pedestrian areas follow the hours listed in the dataset notes; where none are given, the zone is treated as always active.
- **Car or motorcycle**: on a motorcycle, Area C and zones whose exemptions allow motorcycles are ignored. The vehicle is recognised from the connected device (CarPlay, helmet intercom) after you pick it once.
- **Colour-coded Live Activity** (orange when approaching, red when imminent), shown on CarPlay on top of Google Maps; when the road is clear it shrinks to a small green shield.
- **Optional voice alerts** that briefly duck navigation or music.
- **Simulation mode** to test the Live Activity and CarPlay while parked.

Tested on an iPhone 15 Pro Max running iOS 27.0.1: background updates with Google Maps in the foreground, CarPlay in a car and on the TFT display of a Honda Africa Twin (audio in the helmet with the intercom connected).

## Project layout

| Path | Contents |
|---|---|
| `Packages/ZTLCore` | Pure logic (geometry, gates, schedules), also tested on Linux |
| `App` | SwiftUI app: background GPS, Live Activity, voice |
| `Widget` | Extension that renders the Live Activity |
| `Shared` | Data model shared by the app and the extension |
| `Resources` | Gates (City of Milan GeoJSON) and local zones (`zone_locali.json`) |
| `tools/build_zone_data.py` | Regenerates `zone_locali.json` from dataset ds51, with schedules and exclusions |
| `project.yml` | Project definition for XcodeGen |

## Build

No Mac required: every push to `main` builds the app on GitHub Actions. The unsigned IPA is published in the [`prototype`](../../releases/tag/prototype) release.

The logic tests run anywhere Swift is available:

```sh
swift test --package-path Packages/ZTLCore
```

## Installing with SideStore

1. Install [SideStore](https://sidestore.io) on your iPhone following the official guide. The initial setup needs a computer (Linux works too).
2. On the iPhone, download `ZTLive.ipa` from the `prototype` release.
3. In SideStore: **My Apps → +** and pick the downloaded file.
4. SideStore automatically renews the signature every 7 days.
5. On first launch, allow location access and make sure Live Activities are enabled in Settings → ZTLive.

## Data

Source: [City of Milan Open Data portal](https://dati.comune.milano.it), CC BY 4.0 licence.

- [Area C gates](https://dati.comune.milano.it/dataset/ds82_infogeo_varchi_elettronici_localizzazione_) (ds82)
- [Area B gates](https://dati.comune.milano.it/dataset/ds959-varchi-areab) (ds959)
- [Pedestrian areas and ZTLs](https://dati.comune.milano.it/dataset/ds51_trafficotrasporti_aree_pedonali_ztl) (ds51)

To refresh the local zones: `python3 tools/build_zone_data.py`.

This information is indicative only: road signs and the City's official acts always prevail.
