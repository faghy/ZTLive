#!/usr/bin/env python3
"""Genera la mappa interattiva delle ZTL di Milano per il sito ztlive.it.

Uso: python3 tools/build_site_map.py percorso/milano-osm.json

Il file OSM si scarica da Overpass (strade, acqua, parchi e ferrovie del centro, `out geom`):
la query è in OSM_QUERY. Zone e varchi vengono da Resources/, gli stessi dati dell'app.
Escono due file in site/:
- ztl-map.html: frammento (stile, SVG, script) da incollare in un blocco HTML del sito;
- preview.html: pagina completa per vederlo nel browser.
Lo stile richiama Google Maps; nessuna risorsa esterna, nessun cookie.
"""
import html
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"
OUTPUT = ROOT / "site"

OSM_QUERY = """[out:json][timeout:120];
(
  way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|pedestrian|primary_link|secondary_link|tertiary_link)$"](45.440,9.150,45.492,9.232);
  way["waterway"~"^(canal|river)$"](45.440,9.150,45.492,9.232);
  way["natural"="water"](45.440,9.150,45.492,9.232);
  way["leisure"="park"](45.440,9.150,45.492,9.232);
  relation["leisure"="park"](45.440,9.150,45.492,9.232);
  way["railway"="rail"](45.440,9.150,45.492,9.232);
);
out geom qt;"""

# Area disegnata e proiezione equirettangolare: 1 unità ≈ 1,4 m.
SOUTH, WEST, NORTH, EAST = 45.440, 9.150, 45.492, 9.232
LAT0 = math.radians((SOUTH + NORTH) / 2)
SCALE = 4400 / ((EAST - WEST) * math.cos(LAT0))
WIDTH = round((EAST - WEST) * math.cos(LAT0) * SCALE)
HEIGHT = round((NORTH - SOUTH) * SCALE)
# Vista iniziale: Area C intera.
START_VIEW = (700, 800, 2650, 2380)

ROAD_CLASSES = {
    "residential": "r", "unclassified": "r", "living_street": "r",
    "tertiary": "t", "tertiary_link": "t",
    "secondary": "s", "secondary_link": "s",
    "primary": "p", "primary_link": "p",
    "trunk": "m", "motorway": "m",
    "pedestrian": "w",
}

LANDMARKS = [
    ("Duomo", 45.4641, 9.1919, "big"),
    ("Castello Sforzesco", 45.4705, 9.1795, ""),
    ("Parco Sempione", 45.4728, 9.1735, "park"),
    ("Brera", 45.4719, 9.1879, ""),
    ("Stazione Centrale", 45.4862, 9.2040, ""),
    ("Porta Garibaldi", 45.4846, 9.1873, ""),
    ("Isola", 45.4885, 9.1905, ""),
    ("Porta Venezia", 45.4747, 9.2052, ""),
    ("Giardini Montanelli", 45.4740, 9.1990, "park"),
    ("Porta Romana", 45.4518, 9.2032, ""),
    ("Darsena", 45.4529, 9.1772, "water"),
    ("Navigli", 45.4507, 9.1710, "water"),
    ("Porta Ticinese", 45.4556, 9.1811, ""),
    ("Sant'Ambrogio", 45.4624, 9.1754, ""),
    ("Cadorna", 45.4683, 9.1757, ""),
    ("Città Studi", 45.4775, 9.2255, ""),
    ("CityLife", 45.4775, 9.1560, ""),
]


def project(lat, lon):
    return ((lon - WEST) * math.cos(LAT0) * SCALE, (NORTH - lat) * SCALE)


def simplify(points, tolerance):
    """Douglas-Peucker iterativo."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        first, last = stack.pop()
        (x1, y1), (x2, y2) = points[first], points[last]
        dx, dy = x2 - x1, y2 - y1
        length = math.hypot(dx, dy)
        index, distance = 0, 0.0
        for i in range(first + 1, last):
            px, py = points[i]
            # Negli anelli chiusi il primo e l'ultimo punto coincidono: si misura dal punto.
            d = abs(dy * px - dx * py + x2 * y1 - y2 * x1) / length if length > 1e-6 else math.hypot(px - x1, py - y1)
            if d > distance:
                index, distance = i, d
        if distance > tolerance:
            keep[index] = True
            stack += [(first, index), (index, last)]
    return [p for p, k in zip(points, keep) if k]


def path(points, closed=False, tolerance=1.5):
    pts = simplify(points, tolerance)
    if len(pts) < 2:
        return ""
    out = [f"M{round(pts[0][0])} {round(pts[0][1])}"]
    px, py = round(pts[0][0]), round(pts[0][1])
    for x, y in pts[1:]:
        x, y = round(x), round(y)
        if (x, y) != (px, py):
            out.append(f"l{x - px} {y - py}")
            px, py = x, y
    return "".join(out) + ("z" if closed else "")


def osm_layers(data):
    roads = {key: [] for key in set(ROAD_CLASSES.values())}
    water_lines, water_areas, parks, rail = [], [], [], []
    for element in data["elements"]:
        tags = element.get("tags", {})
        if element["type"] == "way" and "geometry" in element:
            points = [project(p["lat"], p["lon"]) for p in element["geometry"]]
            kind = ROAD_CLASSES.get(tags.get("highway"))
            if kind and tags.get("area") != "yes":
                roads[kind].append(path(points))
            elif tags.get("waterway"):
                water_lines.append(path(points))
            elif tags.get("natural") == "water":
                water_areas.append(path(points, closed=True))
            elif tags.get("leisure") == "park":
                parks.append(path(points, closed=True))
            elif tags.get("railway") == "rail" and not tags.get("tunnel") and tags.get("service") is None:
                rail.append(path(points))
        elif element["type"] == "relation" and tags.get("leisure") == "park":
            for member in element.get("members", []):
                if member.get("role") == "outer" and "geometry" in member:
                    parks.append(path([project(p["lat"], p["lon"]) for p in member["geometry"]], closed=True))
    join = lambda items: "".join(i for i in items if i)
    return {k: join(v) for k, v in roads.items()}, join(water_lines), join(water_areas), join(parks), join(rail)


def zone_layers():
    zones = json.loads((RESOURCES / "zone_locali.json").read_text())
    groups = {"areaB": [], "areaC": [], "ztl": [], "pedestrian": []}
    for zone in zones:
        d = "".join(path([project(lat, lon) for lat, lon in ring], closed=True, tolerance=1) for ring in zone["rings"])
        groups[zone["kind"]].append((zone, d))
    return groups


def gate_layers():
    gates = []
    for file, zone in (("areac_varchi.geojson", "C"), ("areab_varchi.geojson", "B")):
        for feature in json.loads((RESOURCES / file).read_text())["features"]:
            props = feature["properties"]
            if props.get("stato") not in (None, "ATTIVI E SANZIONANTI"):
                continue
            lon, lat = feature["geometry"]["coordinates"][:2]
            name = (props.get("label") or props.get("nome") or "Varco").split(" - ", 1)[-1].title()
            x, y = project(lat, lon)
            gates.append((zone, name, round(x), round(y)))
    return gates


def schedule_text(zone):
    if zone["kind"] == "pedestrian":
        return "Area pedonale, sempre attiva"
    if zone["schedule"]:
        return "ZTL con orari: vedi cartelli e portale del Comune"
    return "ZTL, considerata sempre attiva"


def build_fragment(data):
    roads, water_lines, water_areas, parks, rail = osm_layers(data)
    zones = zone_layers()
    gates = gate_layers()
    e = html.escape

    zone_paths = []
    for kind, css in (("areaB", "zb"), ("areaC", "zc"), ("ztl", "zl"), ("pedestrian", "zp")):
        for zone, d in zones[kind]:
            label = "Area B" if kind == "areaB" else "Area C" if kind == "areaC" else zone["name"]
            info = {"areaB": "Feriali 7:30–19:30, festivi esclusi", "areaC": "Feriali 7:30–19:30, festivi esclusi · in moto non si paga"}.get(kind) or schedule_text(zone)
            zone_paths.append(f'<path class="{css}" d="{d}" data-n="{e(label)}" data-i="{e(info)}"/>')

    gate_marks = "".join(
        f'<circle class="g{z.lower()}" cx="{x}" cy="{y}" r="11" data-n="{e(name)}" data-i="Varco di Area {z}"/>'
        for z, name, x, y in gates
    )
    labels = []
    for name, lat, lon, style in LANDMARKS:
        x, y = project(lat, lon)
        labels.append(f'<text class="lb {style}" x="{round(x)}" y="{round(y)}">{e(name)}</text>')

    road_svg = "".join(f'<path class="c{k}" d="{roads[k]}"/>' for k in ("r", "t", "s", "p", "m") if roads[k])
    road_svg += "".join(f'<path class="f{k}" d="{roads[k]}"/>' for k in ("w", "r", "t", "s", "p", "m") if roads[k])

    svg = f'''<svg id="ztlm-svg" viewBox="{" ".join(map(str, START_VIEW))}" role="img" aria-labelledby="ztlm-title" preserveAspectRatio="xMidYMid meet">
<title id="ztlm-title">Mappa di Milano con Area C, Area B, ZTL, aree pedonali e varchi</title>
<rect x="-4000" y="-4000" width="{WIDTH + 8000}" height="{HEIGHT + 8000}" class="bg"/>
<g class="osm"><path class="pk" d="{parks}"/><path class="wa" d="{water_areas}"/><path class="wl" d="{water_lines}"/><path class="rl" d="{rail}"/>{road_svg}</g>
<g class="zones">{"".join(zone_paths)}</g>
<g class="labels">{"".join(labels)}<text class="lb zone" x="{round(project(45.4598, 9.1985)[0])}" y="{round(project(45.4598, 9.1985)[1])}">AREA C</text></g>
<g class="gates">{gate_marks}</g>
</svg>'''

    return TEMPLATE.replace("{{SVG}}", svg).replace("{{START}}", json.dumps(START_VIEW)).replace(
        "{{BOUNDS}}", json.dumps([0, 0, WIDTH, HEIGHT])
    ).replace("{{GATES}}", str(len(gates))).replace("{{ZONES}}", str(len(zones["ztl"]) + len(zones["pedestrian"])))


TEMPLATE = r'''<div id="ztlm" class="ztlm" data-layers="c b l p g">
<style>
#ztlm{position:relative;height:min(78vh,760px);min-height:460px;overflow:hidden;background:#f1f3f4;font-family:Roboto,"Google Sans",Arial,system-ui,sans-serif;color:#202124;border-radius:0;touch-action:none;user-select:none}
#ztlm svg{width:100%;height:100%;display:block;cursor:grab}
#ztlm.drag svg{cursor:grabbing}
#ztlm .bg{fill:#f1f3f4}
#ztlm .pk{fill:#c8e6c9}
#ztlm .wa{fill:#a8d4f5}
#ztlm .wl{fill:none;stroke:#a8d4f5;stroke-width:14;stroke-linecap:round;stroke-linejoin:round}
#ztlm .rl{fill:none;stroke:#bdc1c6;stroke-width:4;stroke-dasharray:14 10}
#ztlm .osm path[class^=c],#ztlm .osm path[class^=f]{fill:none;stroke-linecap:round;stroke-linejoin:round}
#ztlm .cr{stroke:#dadce0;stroke-width:9}#ztlm .fr{stroke:#fff;stroke-width:6}
#ztlm .ct{stroke:#dadce0;stroke-width:13}#ztlm .ft{stroke:#fff;stroke-width:10}
#ztlm .cs{stroke:#e8d27a;stroke-width:16}#ztlm .fs{stroke:#fff6c9;stroke-width:12}
#ztlm .cp{stroke:#f2b84b;stroke-width:20}#ztlm .fp{stroke:#fde293;stroke-width:15}
#ztlm .cm{stroke:#e8913a;stroke-width:24}#ztlm .fm{stroke:#f8b84e;stroke-width:18}
#ztlm .fw{stroke:#fafafa;stroke-width:5}
#ztlm .zones path{fill-rule:evenodd;cursor:pointer;transition:fill-opacity .15s}
#ztlm .zb{fill:#1a73e8;fill-opacity:.04;stroke:#1a73e8;stroke-width:6;stroke-dasharray:24 14}
#ztlm .zc{fill:#ea4335;fill-opacity:.07;stroke:#d93025;stroke-width:8}
#ztlm .zl{fill:#f9ab00;fill-opacity:.35;stroke:#e37400;stroke-width:3}
#ztlm .zp{fill:#9334e6;fill-opacity:.28;stroke:#8430ce;stroke-width:2}
#ztlm .zones path:hover{fill-opacity:.5}
#ztlm .zc:hover,#ztlm .zb:hover{fill-opacity:.12}
#ztlm .gc,#ztlm .gb{stroke:#fff;stroke-width:5;cursor:pointer}
#ztlm .gc{fill:#d93025}#ztlm .gb{fill:#1a73e8}
#ztlm .gates circle:hover,#ztlm .gates circle.on{r:17}
#ztlm .lb{font-size:calc(var(--k,2) * 12.5px);fill:#5f6368;paint-order:stroke;stroke:#fff;stroke-width:calc(var(--k,2) * 3px);stroke-linejoin:round;text-anchor:middle;pointer-events:none;font-weight:500}
#ztlm .lb.big{font-size:calc(var(--k,2) * 16px);fill:#202124;font-weight:700}
#ztlm .lb.park{fill:#188038}#ztlm .lb.water{fill:#1967d2;font-style:italic}
#ztlm .lb.zone{font-size:calc(var(--k,2) * 17px);fill:#d93025;letter-spacing:calc(var(--k,2) * 3px);font-weight:700;opacity:.75}
#ztlm:not([data-layers~=c]) .zc,#ztlm:not([data-layers~=c]) .lb.zone,#ztlm:not([data-layers~=b]) .zb,#ztlm:not([data-layers~=l]) .zl,#ztlm:not([data-layers~=p]) .zp,#ztlm:not([data-layers~=g]) .gates{display:none}
#ztlm .ztlm-top{position:absolute;top:14px;left:14px;right:14px;display:flex;gap:10px;align-items:flex-start;flex-wrap:wrap;pointer-events:none}
#ztlm .ztlm-search{pointer-events:auto;position:relative;width:min(392px,100%);background:#fff;border-radius:24px;box-shadow:0 2px 4px rgba(0,0,0,.2),0 -1px 0 rgba(0,0,0,.02);display:flex;align-items:center;height:48px;padding:0 6px 0 18px}
#ztlm .ztlm-search input{border:0;outline:0;flex:1;font:inherit;font-size:15px;background:transparent;min-width:0;color:#202124}
#ztlm .ztlm-search svg{width:24px;height:24px;flex:none;cursor:default;fill:#5f6368;margin:0 8px}
#ztlm .ztlm-res{position:absolute;top:52px;left:0;right:0;background:#fff;border-radius:12px;box-shadow:0 4px 12px rgba(0,0,0,.18);list-style:none;margin:0;padding:6px 0;max-height:280px;overflow:auto}
#ztlm .ztlm-res:empty{display:none}
#ztlm .ztlm-res li{padding:9px 18px;font-size:14px;cursor:pointer;display:flex;gap:10px;align-items:center}
#ztlm .ztlm-res li:hover,#ztlm .ztlm-res li.sel{background:#f1f3f4}
#ztlm .ztlm-res small{color:#70757a;margin-left:auto}
#ztlm .ztlm-chips{pointer-events:auto;display:flex;gap:8px;flex-wrap:wrap}
#ztlm .ztlm-chips button{font:inherit;font-size:14px;height:32px;padding:0 14px 0 10px;border-radius:16px;border:0;background:#fff;color:#3c4043;box-shadow:0 1px 3px rgba(0,0,0,.25);cursor:pointer;display:flex;align-items:center;gap:7px}
#ztlm .ztlm-chips button i{width:12px;height:12px;border-radius:50%;display:inline-block}
#ztlm .ztlm-chips button[aria-pressed=false]{background:#f1f3f4;color:#80868b;box-shadow:0 1px 2px rgba(0,0,0,.15)}
#ztlm .ztlm-chips button[aria-pressed=false] i{opacity:.3}
#ztlm .ztlm-zoom{position:absolute;right:14px;bottom:34px;display:flex;flex-direction:column;background:#fff;border-radius:8px;box-shadow:0 1px 4px rgba(0,0,0,.3);overflow:hidden}
#ztlm .ztlm-zoom button{width:40px;height:40px;border:0;background:#fff;font-size:22px;color:#666;cursor:pointer;line-height:1}
#ztlm .ztlm-zoom button+button{border-top:1px solid #e6e6e6}
#ztlm .ztlm-card{position:absolute;left:14px;bottom:34px;width:min(340px,calc(100% - 84px));background:#fff;border-radius:12px;box-shadow:0 2px 8px rgba(0,0,0,.25);padding:14px 16px}
#ztlm .ztlm-card[hidden]{display:none}
#ztlm .ztlm-card b{display:block;font-size:17px;font-weight:500;margin-bottom:3px}
#ztlm .ztlm-card span{font-size:13px;color:#5f6368}
#ztlm .ztlm-card button{position:absolute;top:8px;right:8px;border:0;background:none;font-size:18px;color:#5f6368;cursor:pointer}
#ztlm .ztlm-credit{position:absolute;right:0;bottom:0;background:rgba(255,255,255,.8);font-size:11px;color:#444;padding:2px 8px}
#ztlm .ztlm-credit a{color:#444}
@media (max-width:600px){#ztlm .ztlm-chips{order:2}#ztlm .ztlm-chips button{height:30px;font-size:13px}}
</style>
{{SVG}}
<div class="ztlm-top">
 <div class="ztlm-search" role="search">
  <input id="ztlm-q" type="search" placeholder="Cerca un varco o una zona ZTL" aria-label="Cerca un varco o una zona ZTL" autocomplete="off">
  <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M15.5 14h-.79l-.28-.27A6.47 6.47 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z"/></svg>
  <ul class="ztlm-res" id="ztlm-res" role="listbox"></ul>
 </div>
 <div class="ztlm-chips" role="group" aria-label="Livelli della mappa">
  <button type="button" data-l="c" aria-pressed="true"><i style="background:#d93025"></i>Area C</button>
  <button type="button" data-l="b" aria-pressed="true"><i style="background:#1a73e8"></i>Area B</button>
  <button type="button" data-l="l" aria-pressed="true"><i style="background:#f9ab00"></i>ZTL</button>
  <button type="button" data-l="p" aria-pressed="true"><i style="background:#9334e6"></i>Aree pedonali</button>
  <button type="button" data-l="g" aria-pressed="true"><i style="background:#5f6368"></i>Varchi ({{GATES}})</button>
 </div>
</div>
<div class="ztlm-card" id="ztlm-card" hidden aria-live="polite"><button type="button" aria-label="Chiudi">×</button><b></b><span></span></div>
<div class="ztlm-zoom"><button type="button" data-z="0.7" aria-label="Ingrandisci">+</button><button type="button" data-z="1.4" aria-label="Riduci">−</button></div>
<div class="ztlm-credit">Dati: <a href="https://dati.comune.milano.it" target="_blank" rel="noopener">Comune di Milano</a> (CC BY 4.0) · © <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a></div>
<script>
(function(){
var root=document.getElementById('ztlm'),svg=document.getElementById('ztlm-svg'),START={{START}},B={{BOUNDS}};
var v=START.slice(),card=document.getElementById('ztlm-card'),q=document.getElementById('ztlm-q'),res=document.getElementById('ztlm-res');
function apply(){var minW=300,maxW=B[2]*1.1;if(v[2]<minW){var k=minW/v[2];v[0]-=(v[2]*k-v[2])/2;v[1]-=(v[3]*k-v[3])/2;v[2]*=k;v[3]*=k}if(v[2]>maxW){var k2=maxW/v[2];v[0]+=(v[2]-v[2]*k2)/2;v[1]+=(v[3]-v[3]*k2)/2;v[2]*=k2;v[3]*=k2}
v[0]=Math.min(Math.max(v[0],B[0]-v[2]/2),B[2]-v[2]/2);v[1]=Math.min(Math.max(v[1],B[1]-v[3]/2),B[3]-v[3]/2);svg.setAttribute('viewBox',v.map(function(n){return n.toFixed(1)}).join(' '));svg.style.setProperty('--k',scale().toFixed(3))}
function scale(){var r=svg.getBoundingClientRect();return Math.max(v[2]/r.width,v[3]/r.height)}
function toMap(cx,cy){var r=svg.getBoundingClientRect(),s=scale();return[v[0]+(cx-r.left)*s-(r.width*s-v[2])/2,v[1]+(cy-r.top)*s-(r.height*s-v[3])/2]}
function zoom(k,cx,cy){var r=svg.getBoundingClientRect();if(cx===undefined){cx=r.left+r.width/2;cy=r.top+r.height/2}var p=toMap(cx,cy);v[0]=p[0]-(p[0]-v[0])*k;v[1]=p[1]-(p[1]-v[1])*k;v[2]*=k;v[3]*=k;apply()}
function fly(x,y,w){var h=w*v[3]/v[2];v=[x-w/2,y-h/2,w,h];apply()}
svg.addEventListener('wheel',function(e){e.preventDefault();zoom(e.deltaY>0?1.2:1/1.2,e.clientX,e.clientY)},{passive:false});
var pts={},last=null,moved=false;
svg.addEventListener('pointerdown',function(e){svg.setPointerCapture(e.pointerId);pts[e.pointerId]=[e.clientX,e.clientY];moved=false;root.classList.add('drag')});
svg.addEventListener('pointermove',function(e){if(!pts[e.pointerId])return;var ids=Object.keys(pts);var s=scale();
 if(ids.length===1){var dx=e.clientX-pts[e.pointerId][0],dy=e.clientY-pts[e.pointerId][1];if(Math.abs(dx)+Math.abs(dy)>3)moved=true;v[0]-=dx*s;v[1]-=dy*s;apply()}
 else if(ids.length===2){var o=pts[ids[0]===String(e.pointerId)?ids[1]:ids[0]];var d0=Math.hypot(pts[e.pointerId][0]-o[0],pts[e.pointerId][1]-o[1]),d1=Math.hypot(e.clientX-o[0],e.clientY-o[1]);if(d0>0&&d1>0){moved=true;zoom(d0/d1,(e.clientX+o[0])/2,(e.clientY+o[1])/2)}}
 pts[e.pointerId]=[e.clientX,e.clientY]});
function up(e){delete pts[e.pointerId];if(!Object.keys(pts).length)root.classList.remove('drag')}
svg.addEventListener('pointerup',up);svg.addEventListener('pointercancel',up);
function show(el){if(last)last.classList.remove('on');last=el;el.classList.add('on');card.querySelector('b').textContent=el.getAttribute('data-n');card.querySelector('span').textContent=el.getAttribute('data-i');card.hidden=false}
svg.addEventListener('click',function(e){if(moved)return;var el=e.target.closest('[data-n]');if(el){show(el)}else{card.hidden=true;if(last)last.classList.remove('on')}});
card.querySelector('button').onclick=function(){card.hidden=true;if(last)last.classList.remove('on')};
root.querySelectorAll('.ztlm-zoom button').forEach(function(b){b.onclick=function(){zoom(parseFloat(b.getAttribute('data-z')))}});
root.querySelectorAll('.ztlm-chips button').forEach(function(b){b.onclick=function(){var on=b.getAttribute('aria-pressed')!=='true';b.setAttribute('aria-pressed',on);var l=root.getAttribute('data-layers').split(' ').filter(function(x){return x&&x!==b.getAttribute('data-l')});if(on)l.push(b.getAttribute('data-l'));root.setAttribute('data-layers',l.join(' '))}});
var items=[].slice.call(svg.querySelectorAll('[data-n]')).map(function(el){return{el:el,n:el.getAttribute('data-n'),i:el.getAttribute('data-i')}});
function norm(s){return s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g,'')}
function pick(it){var b=it.el.getBBox();fly(b.x+b.width/2,b.y+b.height/2,Math.max(b.width,b.height)*3+400);show(it.el);res.innerHTML='';q.value=it.n}
q.addEventListener('input',function(){var t=norm(q.value.trim());res.innerHTML='';if(t.length<2)return;var seen={};items.filter(function(it){return norm(it.n).indexOf(t)>=0}).slice(0,40).forEach(function(it){var key=it.n+it.i;if(seen[key])return;seen[key]=1;if(res.children.length>=8)return;var li=document.createElement('li');li.setAttribute('role','option');li.textContent=it.n;var sm=document.createElement('small');sm.textContent=it.i.split(',')[0];li.appendChild(sm);li.onclick=function(){pick(it)};res.appendChild(li)})});
q.addEventListener('keydown',function(e){if(e.key==='Enter'&&res.firstChild){res.firstChild.click()}if(e.key==='Escape'){res.innerHTML=''}});
apply();window.addEventListener('resize',apply);
})();
</script>
</div>'''


PREVIEW = """<!doctype html><html lang="it"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Anteprima mappa ZTLive</title><style>body{margin:0}</style></head><body>{{MAP}}</body></html>"""


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    data = json.loads(Path(sys.argv[1]).read_text())
    fragment = build_fragment(data)
    OUTPUT.mkdir(exist_ok=True)
    (OUTPUT / "ztl-map.html").write_text(fragment)
    (OUTPUT / "preview.html").write_text(PREVIEW.replace("{{MAP}}", fragment))
    print(f"ztl-map.html: {len(fragment.encode()) // 1024} KB, viewBox {WIDTH}x{HEIGHT}")


if __name__ == "__main__":
    main()
