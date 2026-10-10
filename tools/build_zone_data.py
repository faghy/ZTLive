#!/usr/bin/env python3
"""Genera Resources/zone_locali.json dal dataset ds51 (aree pedonali e ZTL) del Comune di Milano.

Uso: python3 tools/build_zone_data.py [percorso/disciplina_aree.geojson]
Senza argomenti scarica il dataset dal portale open data.

Il dataset non ha un campo orari: quando le note li riportano li trascriviamo in SCHEDULES,
altrimenti la zona è considerata sempre attiva (meglio un avviso in più che una multa).
"""
import json
import re
import sys
import urllib.request
from pathlib import Path

SOURCE_URL = (
    "https://dati.comune.milano.it/dataset/d7d9179a-8228-427f-9c86-1e30154be4fe/resource/"
    "d788b26b-31b4-4e57-992d-276a1280c8c2/download/disciplina_aree.geojson"
)
OUTPUT = Path(__file__).resolve().parent.parent / "Resources" / "zone_locali.json"

KINDS = {"ZTL": "ztl", "AP": "pedestrian", "AREA_C": "areaC", "AREA_B": "areaB"}
# Perimetri di Area B e C: servono a controllare i percorsi; durante la guida si usano i varchi.
NAMES = {"AREA_C": "Area C", "AREA_B": "Area B"}

ALL_DAYS = [1, 2, 3, 4, 5, 6, 7]  # 1 = lunedì ... 7 = domenica


def window(days, start, end):
    """Fascia oraria che inizia nei `days`; se `end` <= `start` prosegue nel giorno dopo."""
    to_minutes = lambda s: int(s[:2]) * 60 + int(s[3:])
    return {"days": days, "from": to_minutes(start), "to": to_minutes(end) or 1440}


# Orari trascritti dalle note del dataset (campo "note").
NAVIGLI_NOTTURNA = [window(ALL_DAYS, "20:00", "07:00")]
SCHEDULES = {
    210: NAVIGLI_NOTTURNA,
    212: NAVIGLI_NOTTURNA,
    213: NAVIGLI_NOTTURNA,
    214: NAVIGLI_NOTTURNA,
    224: [window(ALL_DAYS, "22:00", "06:00")],  # Arco della Pace
    # Ascanio Sforza: lun-gio 19:00-6:00, dal venerdì alle 19:00 al lunedì alle 6:00.
    1102: [
        window([1, 2, 3, 4], "19:00", "06:00"),
        window([5], "19:00", "24:00"),
        window([6, 7], "00:00", "24:00"),
        window([1], "00:00", "06:00"),
    ],
}

# Zone escluse: non si applicano ad auto e moto o non hanno un orario prevedibile.
EXCLUDED = {
    203: "Cavalcavia Monte Ceneri: divieto notturno per i mezzi pesanti, auto in deroga",
    1023: "San Siro Eventi: attiva solo nei giorni di partite e concerti",
}

MOTO_ALLOWED = re.compile(r"\bmoto\b|motocicl", re.IGNORECASE)


def pretty_name(name):
    name = " ".join((name or "").split())
    name = re.sub(r"^(ZTL|AP)\s+", "", name)
    return name.title() if name.isupper() else name


def is_expired(properties):
    end = properties.get("val_fine")
    return end is not None and end[:10] < "2026-01-01"


def rings(geometry):
    """Tutti gli anelli del MultiPolygon, coordinate [lat, lon] arrotondate."""
    result = []
    for polygon in geometry["coordinates"]:
        for ring in polygon:
            result.append([[round(lat, 6), round(lon, 6)] for lon, lat in ring])
    return result


def main():
    if len(sys.argv) > 1:
        data = json.loads(Path(sys.argv[1]).read_text())
    else:
        with urllib.request.urlopen(SOURCE_URL, timeout=60) as response:
            data = json.load(response)

    zones = []
    for feature in data["features"]:
        properties = feature["properties"]
        kind = KINDS.get(properties["tipo"])
        zone_id = properties["id_amat"]
        if kind is None or zone_id in EXCLUDED or is_expired(properties):
            continue
        zones.append({
            "id": zone_id,
            "name": NAMES.get(properties["tipo"]) or pretty_name(properties["nome"]),
            "kind": kind,
            "motoAllowed": bool(MOTO_ALLOWED.search(properties.get("deroghe") or "")),
            "schedule": SCHEDULES.get(zone_id),
            "rings": rings(feature["geometry"]),
        })

    zones.sort(key=lambda zone: zone["id"])
    OUTPUT.write_text(json.dumps(zones, ensure_ascii=False, separators=(",", ":")))
    counts = {kind: sum(zone["kind"] == kind for zone in zones) for kind in KINDS.values()}
    print(f"{OUTPUT.name}: {len(zones)} zone {counts}")


if __name__ == "__main__":
    main()
