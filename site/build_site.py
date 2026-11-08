#!/usr/bin/env python3
"""Costruisce il sito ztlive.it su Cleitext tramite l'API REST.

Uso: python3 site/build_site.py percorso/del/token.txt

Rilanciabile: gli id creati sono in site/state.json e alla volta successiva le voci si aggiornano.
Le pagine usano i blocchi del tema Canvas; solo la mappa (site/ztl-map.html, da tools/build_site_map.py)
sta in un blocco HTML.
"""
import json
import mimetypes
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path

SITE = "https://ztlive.it"
API = SITE + "/api/v1"
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
STATE = HERE / "state.json"

GITHUB = "https://github.com/faghy/ZTLive"
# Matomo su server3, modalità anonima (senza cookie, nessun consenso): None finché il sito non esiste.
MATOMO_URL = "https://analytics.dueclic.eu"
MATOMO_SITE_ID = 57
LINKS = {
    "varchi": "https://dati.comune.milano.it/web/portale-del-dato/w/mappa-dei-varchi-di-area-c-e-area-b-a-milano",
    "ds82": "https://dati.comune.milano.it/dataset/ds82_infogeo_varchi_elettronici_localizzazione_",
    "ds959": "https://dati.comune.milano.it/dataset/ds959-varchi-areab",
    "ds51": "https://dati.comune.milano.it/dataset/ds51_trafficotrasporti_aree_pedonali_ztl",
    "areac": "https://www.comune.milano.it/aree-tematiche/mobilita/area-c",
    "areab": "https://www.comune.milano.it/aree-tematiche/mobilita/area-b",
    "ztl": "https://www.comune.milano.it/aree-tematiche/mobilita/zone-a-traffico-limitato",
    "carplay": "https://www.apple.com/it/ios/carplay/",
    "roma": "https://romamobilita.it/it/servizi/ztl",
    "osm": "https://www.openstreetmap.org/copyright",
    "faghy": "https://faghy.it",
}


class Api:
    def __init__(self, token):
        self.token = token

    def call(self, method, path, body=None, raw=None, content_type="application/json"):
        headers = {"Authorization": f"Bearer {self.token}", "Origin": SITE, "User-Agent": "ztlive-site-builder/1.0"}
        data = raw
        if raw is None and (body is not None or method in ("POST", "PUT", "PATCH")):
            # Il server web rifiuta le POST senza corpo.
            data = json.dumps(body if body is not None else {}).encode()
        if data is not None:
            headers["Content-Type"] = content_type
        request = urllib.request.Request(API + path, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                text = response.read().decode()
        except urllib.error.HTTPError as error:
            sys.exit(f"{method} {path}: {error.code} {error.read().decode()[:500]}")
        return json.loads(text) if text else None

    def upload(self, path):
        boundary = uuid.uuid4().hex
        mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        body = (
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{path.name}\"\r\n"
            f"Content-Type: {mime}\r\n\r\n"
        ).encode() + path.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
        return self.call("POST", "/media", raw=body, content_type=f"multipart/form-data; boundary={boundary}")


# --- Blocchi CXD ---------------------------------------------------------------------------

class Doc:
    def __init__(self):
        self.n = 0

    def block(self, type_, attrs=None, content=None, children=None):
        self.n += 1
        block = {"id": f"b{self.n}", "type": type_, "v": 1, "attrs": attrs or {}}
        if content is not None:
            block["content"] = inline(content)
        if children is not None:
            block["children"] = children
        return block

    def p(self, content, cls=None):
        return self.block("core/paragraph", {"className": cls} if cls else {}, content)

    def h(self, level, content, cls=None, anchor=None):
        attrs = {"level": level}
        if cls:
            attrs["className"] = cls
        if anchor:
            attrs["anchor"] = anchor
        return self.block("core/heading", attrs, content)

    def group(self, children, cls="", section=False, anchor=None):
        attrs = {"className": cls} if cls else {}
        if section:
            attrs.update(align="full", tagName="section")
        if anchor:
            attrs["anchor"] = anchor
        return self.block("core/group", attrs, children=children)

    def section(self, cls, children, anchor=None):
        return self.group(children, "cv-section " + cls, section=True, anchor=anchor)

    def card(self, icon, title, text):
        return self.group([self.h(3, title), self.p(text)], f"cv-card cv-i-{icon}")

    def buttons(self, items, cls=None):
        children = []
        for label, url, outline in items:
            attrs = {"url": url}
            if url.startswith("http"):
                attrs.update(linkTarget="_blank", rel="noopener")
            if outline:
                attrs["className"] = "is-style-outline"
            children.append(self.block("core/button", attrs, label))
        return self.block("core/buttons", {"className": cls} if cls else {}, children=children)

    def ul(self, items, cls=None):
        return self.block("core/list", {"className": cls} if cls else {},
                          children=[self.block("core/list-item", {}, item, children=[]) for item in items])

    def image(self, media, alt, cls=None):
        attrs = {"id": media["id"], "url": media["url"], "alt": alt}
        if cls:
            attrs["className"] = cls
        return self.block("core/image", attrs)

    def columns(self, columns, cls=None):
        return self.block("core/columns", {"className": cls} if cls else {},
                          children=[self.block("core/column", {}, children=c) for c in columns])

    def html(self, content):
        return self.block("core/html", {"content": content})


def inline(content):
    """Testo semplice, oppure lista di stringhe, ("testo", "bold") e ("link", href, testo)."""
    if isinstance(content, str):
        return [{"text": content}]
    out = []
    for part in content:
        if isinstance(part, str):
            out.append({"text": part})
        elif part[0] == "link":
            item = {"type": "link", "href": part[1], "children": [{"text": part[2]}]}
            if part[1].startswith("http"):
                item["target"] = "_blank"
            out.append(item)
        else:
            out.append({"text": part[0], "marks": list(part[1:])})
    return out


def document(blocks):
    return {"schema": 1, "blocks": blocks}


# --- Pagine ------------------------------------------------------------------------------

def home(media):
    d = Doc()
    L = LINKS
    blocks = [
        d.section("cv-bg-soft cv-center cv-tight", [
            d.p("Milano · Area C · Area B · ZTL · aree pedonali", "cv-eyebrow"),
            d.h(1, ["L'avviso ZTL ", ("prima del varco", "bold")]),
            d.p("ZTLive ti avvisa a voce e su CarPlay quando stai per entrare in una zona a traffico limitato, "
                "mentre navighi con Google Maps. In auto e in moto.", "cv-lead"),
            d.buttons([("Esplora la mappa", "#mappa", False), ("Cosa fa", "#funzioni", True)]),
        ], anchor="inizio"),
        d.group([
            d.html(media["map_html"]),
        ], "ztl-mappa", section=True, anchor="mappa"),
        d.section("cv-tight cv-center", [
            d.p(["Tocca una zona o un varco per vedere nome e orari, oppure cerca una via. "
                 "Zone e varchi vengono dagli ", ("link", L["varchi"], "open data del Comune di Milano"),
                 " e si aggiornano ogni settimana. Fanno sempre fede i cartelli stradali."]),
        ]),
        d.section("cv-bg-gray cv-center", [
            d.p("Funzionalità", "cv-eyebrow"),
            d.h(2, ["Tutto quello che serve per ", ("non prendere multe", "bold")], anchor="funzioni"),
            d.group([
                d.card("zap", "Avviso prima del varco", "Circa 400 metri prima, solo se la direzione di marcia porta davvero dentro la zona. Sotto i 120 metri diventa imminente."),
                d.card("layers", "Tutte le zone di Milano", "Varchi di Area C e Area B, 20 ZTL locali e oltre 100 aree pedonali, da Brera ai Navigli."),
                d.card("refresh", "Orari e festività", "Area B e C contano solo nei feriali dalle 7:30 alle 19:30. Festivi e Sant'Ambrogio esclusi."),
                d.card("users", "Auto o moto", "In moto l'Area C non si paga. ZTLive riconosce da solo il veicolo da CarPlay o dall'interfono."),
                d.card("search", "Controllo del percorso", "Condividi un percorso da Google Maps a ZTLive: vedi le zone che attraversi e l'orario di passaggio."),
                d.card("globe", "Alternativa senza ZTL", "Ti propone una strada che evita le zone, oppure dove lasciare l'auto e proseguire a piedi, in bici o con i mezzi."),
                d.card("chat", "Avvisi vocali", "Una voce breve che abbassa per un attimo la navigazione o la musica, anche nel casco."),
                d.card("shield", "La posizione resta tua", "Il GPS lavora solo sul telefono. ZTLive scarica i dati delle zone, non invia dove sei."),
            ], "cv-cards cv-cols-4"),
        ]),
        d.section("", [
            d.columns([
                [d.image(media["carplay"], "Schermo CarPlay con l'avviso di ZTLive: varco di Area C Porta Venezia a 250 metri, sopra Google Maps", "cv-shadow")],
                [
                    d.p("In auto e in moto", "cv-eyebrow"),
                    d.h(2, ["Su ", ("CarPlay", "bold"), ", sopra Google Maps"]),
                    d.p(["L'avviso arriva come Live Activity: lo vedi su ",
                         ("link", L["carplay"], "Apple CarPlay"),
                         ", sulla schermata di blocco e nella Dynamic Island, senza lasciare il navigatore."]),
                    d.ul([
                        "Arancione in avvicinamento, rosso quando il varco è vicino",
                        "Funziona anche sul display della moto con CarPlay e interfono",
                        "A strada libera resta solo un piccolo scudo verde",
                    ], "cv-checks"),
                ],
            ], "cv-split"),
        ]),
        d.section("cv-bg-soft", [
            d.p("Come funziona", "cv-eyebrow"),
            d.h(2, ["Quattro passi, ", ("zero pensieri", "bold")]),
            d.group([
                d.group([d.h(3, "Avvia ZTLive"), d.p("Un tocco prima di partire. Scegli auto o moto la prima volta.")], "cv-step"),
                d.group([d.h(3, "Naviga come sempre"), d.p("Usa Google Maps o il navigatore che preferisci.")], "cv-step"),
                d.group([d.h(3, "Ricevi l'avviso"), d.p("A circa 400 metri dal varco lo senti e lo vedi su CarPlay.")], "cv-step"),
                d.group([d.h(3, "Evita la multa"), d.p("Cambia strada, oppure lascia l'auto e prosegui con un altro mezzo.")], "cv-step"),
            ], "cv-steps"),
        ]),
        d.section("cv-bg-gray", [
            d.p("Fonti", "cv-eyebrow"),
            d.h(2, ["Dati ", ("ufficiali", "bold"), ", aggiornati ogni settimana"], anchor="dati"),
            d.p("ZTLive usa solo dati pubblici. Ogni lunedì li riscarica dal portale del Comune e l'app li aggiorna da sola.", "cv-lead"),
            d.group([
                d.group([d.h(3, "Mappa dei varchi"), d.p(["La ", ("link", L["varchi"], "mappa ufficiale dei varchi di Area C e Area B"), " sul portale del dato del Comune di Milano."])], "cv-card cv-i-search"),
                d.group([d.h(3, "Open data"), d.p(["Varchi di ", ("link", L["ds82"], "Area C (ds82)"), " e di ", ("link", L["ds959"], "Area B (ds959)"), ", ", ("link", L["ds51"], "ZTL e aree pedonali (ds51)"), ". Licenza CC BY 4.0."])], "cv-card cv-i-download"),
                d.group([d.h(3, "Regole e orari"), d.p(["Le pagine del Comune su ", ("link", L["areac"], "Area C"), ", ", ("link", L["areab"], "Area B"), " e ", ("link", L["ztl"], "zone a traffico limitato"), ": deroghe, permessi e pagamenti."])], "cv-card cv-i-book"),
                d.group([d.h(3, "Mappa di base"), d.p(["Strade, parchi e Navigli da ", ("link", L["osm"], "OpenStreetMap"), ", disegnati da ZTLive senza servizi esterni né cookie."])], "cv-card cv-i-globe"),
            ], "cv-cards cv-cols-2"),
        ]),
        d.section("cv-center", [
            d.p("Prossimamente", "cv-eyebrow"),
            d.h(2, ["In arrivo ", ("altre città", "bold")], anchor="citta"),
            d.p("Milano è la prima. Le prossime città arriveranno con gli stessi avvisi e la stessa mappa.", "cv-lead"),
            d.group([
                d.group([d.h(3, "Roma"), d.p(["ZTL Centro Storico, Trastevere, San Lorenzo, Testaccio e Tridente, con i varchi di ", ("link", L["roma"], "Roma Mobilità"), ". In arrivo."])], "cv-card cv-i-rocket"),
                d.group([d.h(3, "Torino, Bologna, Firenze"), d.p("Città con ZTL controllate da varchi elettronici: in valutazione.")], "cv-card cv-i-layers"),
                d.group([d.h(3, "La tua città"), d.p(["Vuoi ZTLive dove vivi? Segnalalo su ", ("link", GITHUB + "/issues", "GitHub"), "."])], "cv-card cv-i-heart"),
            ], "cv-cards"),
        ]),
        d.section("cv-bg-soft", [
            d.h(2, ["Domande ", ("frequenti", "bold")], anchor="faq"),
            d.group([
                d.group([d.h(3, "Dove si scarica?"), d.p("ZTLive è in prova su iPhone e arriverà sull'App Store. Segui il progetto per sapere quando.")]),
                d.group([d.h(3, "Quanto costa?"), d.p("Durante la prova è gratuita.")]),
                d.group([d.h(3, "Funziona con il mio navigatore?"), d.p("Sì: lavora in background con Google Maps, Waze o Apple Mappe. Il controllo del percorso parte dalla condivisione di Google Maps.")]),
                d.group([d.h(3, "Dove finisce la mia posizione?"), d.p("Da nessuna parte: resta sul telefono. ZTLive scarica solo i dati delle zone.")]),
                d.group([d.h(3, "E in moto?"), d.p("In moto l'Area C non si paga e alcune ZTL ammettono le moto: ZTLive ne tiene conto.")]),
                d.group([d.h(3, "Posso fidarmi al cento per cento?"), d.p("ZTLive è un aiuto, non un documento ufficiale. Fanno fede i cartelli e le ordinanze del Comune.")]),
            ], "cv-faq"),
        ]),
        d.section("cv-bg-brand cv-center", [
            d.h(2, "Segui ZTLive"),
            d.p("Novità, nuove città e il codice del progetto sono su GitHub.", "cv-lead"),
            d.buttons([("Segui su GitHub", GITHUB, False)]),
        ]),
    ]
    return document(blocks)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    api = Api(Path(sys.argv[1]).read_text().strip())
    state = json.loads(STATE.read_text()) if STATE.exists() else {}

    # Plugin: SEO (incluso) e Privacy dal catalogo.
    plugins = {p["slug"]: p for p in api.call("GET", "/plugins")}
    if "privacy" not in plugins:
        api.call("POST", "/catalog/plugin/privacy/install")
        plugins = {p["slug"]: p for p in api.call("GET", "/plugins")}
    for slug in ("seo", "privacy"):
        if not plugins[slug]["active"]:
            api.call("POST", f"/plugins/{slug}/activate")
    if MATOMO_SITE_ID:
        if "analytics" not in plugins:
            api.call("POST", "/catalog/plugin/analytics/install")
            plugins = {p["slug"]: p for p in api.call("GET", "/plugins")}
        if not plugins["analytics"]["active"]:
            api.call("POST", "/plugins/analytics/activate")
        analytics = api.call("GET", "/ext/analytics/config")
        analytics["matomo"] = {"enabled": True, "url": MATOMO_URL, "siteId": str(MATOMO_SITE_ID), "mode": "anonymous"}
        api.call("PUT", "/ext/analytics/config", analytics)
    if plugins.get("hi-john", {}).get("active"):
        api.call("POST", "/plugins/hi-john/deactivate")

    # Immagini: si caricano una volta sola.
    media = state.setdefault("media", {})
    for key, path in (("logo", ROOT / "docs" / "logo.png"), ("favicon", ROOT / "App" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"),
                      ("carplay", HERE / "img" / "carplay.png"), ("mappa", HERE / "img" / "mappa.png")):
        if key not in media:
            uploaded = api.upload(path)
            media[key] = {"id": uploaded["id"], "url": uploaded["url"]}
            STATE.write_text(json.dumps(state, indent=2))

    api.call("PUT", "/themes/active/settings", {"values": {
        "logo": media["logo"]["id"], "favicon": media["favicon"]["id"], "accentColor": "#1a73e8",
        "showTagline": False, "showPoweredBy": False,
        "footerText": "© 2026 [Serafino Christian](https://faghy.it) · Dati: Comune di Milano (CC BY 4.0) e © OpenStreetMap · Fanno fede i cartelli stradali",
    }})

    # Home.
    pages = state.setdefault("pages", {})
    doc = home({**media, "map_html": (HERE / "ztl-map.html").read_text()})
    seo = {"seo": {
        "title": "ZTLive – Avvisi ZTL a Milano prima del varco, anche su CarPlay",
        "description": "Mappa delle ZTL di Milano con Area C, Area B e varchi. ZTLive ti avvisa a voce e su CarPlay prima del varco mentre navighi con Google Maps.",
        "keyphrase": "ZTL Milano",
    }}
    entry = {"title": "ZTLive", "slug": "home", "document": doc, "fields": seo}
    if "home" in pages:
        api.call("PATCH", f"/entries/{pages['home']}", entry)
    else:
        pages["home"] = api.call("POST", "/entries", {"type": "page", **entry})["id"]
        STATE.write_text(json.dumps(state, indent=2))
    api.call("POST", f"/entries/{pages['home']}/publish", {"visibility": "public"})

    # Privacy e cookie policy generate dal plugin.
    config = api.call("GET", "/ext/privacy/config")
    config["controller"] = {**(config.get("controller") or {}), "name": "Serafino Christian", "email": "fag@faghy.it"}
    # Niente marketing, moduli né contenuti esterni, e Matomo è anonimo: il banner non serve.
    config["banner"]["enabled"] = False
    config["processing"].update(contactForms=False, accounts=False, newsletter=False, embeds=False)
    api.call("PUT", "/ext/privacy/config", config)
    for kind, slug in (("privacy", "privacy"), ("cookies", "cookie")):
        policy = api.call("GET", f"/ext/privacy/policy/{kind}?locale=it&site=ZTLive&origin={SITE}")
        body = {"title": policy["title"], "slug": slug, "document": policy["document"]}
        if kind in pages:
            api.call("PATCH", f"/entries/{pages[kind]}", body)
        else:
            pages[kind] = api.call("POST", "/entries", {"type": "page", **body})["id"]
            STATE.write_text(json.dumps(state, indent=2))
        api.call("POST", f"/entries/{pages[kind]}/publish", {"visibility": "public"})
    config.setdefault("pages", {})["it"] = {"privacy": pages["privacy"], "cookies": pages["cookies"]}
    api.call("PUT", "/ext/privacy/config", config)

    api.call("PATCH", "/settings/core", {"title": "ZTLive", "tagline": "Avvisi ZTL prima del varco",
                                         "timezone": "Europe/Rome", "frontPage": pages["home"]})

    # Menu.
    menus = state.setdefault("menus", {})
    for location, name, items in (
        ("primary", "Principale", [
            {"kind": "url", "url": "/#mappa", "label": "Mappa"},
            {"kind": "url", "url": "/#funzioni", "label": "Funzioni"},
            {"kind": "url", "url": "/#dati", "label": "Dati ufficiali"},
            {"kind": "url", "url": "/#citta", "label": "Città"},
            {"kind": "url", "url": "/#faq", "label": "Domande"},
            {"kind": "url", "url": GITHUB, "label": "GitHub"},
        ]),
        ("footer", "Piè di pagina", [
            {"kind": "entry", "entryId": pages["privacy"], "label": "Privacy"},
            {"kind": "entry", "entryId": pages["cookies"], "label": "Cookie"},
            {"kind": "url", "url": GITHUB, "label": "Codice su GitHub"},
        ]),
    ):
        if location not in menus:
            menus[location] = api.call("POST", "/menus", {"name": name, "locale": "it", "location": location})["id"]
            STATE.write_text(json.dumps(state, indent=2))
        api.call("PUT", f"/menus/{menus[location]}/items", {"items": items})

    STATE.write_text(json.dumps(state, indent=2))
    print("Sito aggiornato:", SITE)


if __name__ == "__main__":
    main()
