#!/usr/bin/env python3
"""QuitChat – telefoonnummers van je chatcontacten voor de app (fase 5b).

De app voegt de kanalen van één persoon samen tot één contact, op
telefoonnummer. Maar Matrix kent die nummers meestal niet: WhatsApp gebruikt
sinds 2025 privé-ID's ("LID", bijv. @whatsapp_lid-123:localhost) en Signal
UUID's. De bridges weten de nummers wel (WhatsApp: whatsmeow_lid_map, Signal:
signalmeow_recipients). Dit script leest die (alleen-lezen) en zet ze voor je
privéchats als account data `nl.quitchat.nummers` in je eigen Synapse:

    {"nummers": {"@whatsapp_lid-123:localhost": "+3161234", ...}}

Dat blijft op je eigen server, gaat mee in de versleutelde backups en is op al
je apparaten gelijk. Er wordt alleen geschreven als er iets veranderde.

Gebruik: contacten-nummers.py            (draait elk uur via een systemd-timer)
         contacten-nummers.py --test      (zelftest, raakt niets aan)
"""
import json
import sqlite3
import sys
import urllib.error
import urllib.request
from pathlib import Path

MAP = Path("/srv/brug")
BRIDGES = MAP / "data/muxbee/bridges"
SETTINGS = MAP / "config/muxbee/settings.yaml"
TOKEN = MAP / "config/brug/contacten-token"   # in de kluis, niet op de gewone schijf
SYNAPSE = "http://localhost:8008"
SOORT = "nl.quitchat.nummers"


def lees_db(pad, sql):
    if not pad.exists():
        return []
    db = sqlite3.connect(f"file:{pad}?mode=ro", uri=True)
    try:
        return db.execute(sql).fetchall()
    except sqlite3.Error:
        return []   # tabel bestaat (nog) niet: deze bridge levert niets
    finally:
        db.close()


def e164(cijfers):
    cijfers = "".join(c for c in str(cijfers) if c.isdigit())
    return "+" + cijfers if cijfers else ""


def nummer_voor(mxid, lid_map, signal):
    """Telefoonnummer bij een bridge-gebruiker, of "" als onbekend."""
    lokaal = mxid[1:].split(":", 1)[0]
    if lokaal.startswith("whatsapp_lid-"):
        return e164(lid_map.get(lokaal[len("whatsapp_lid-"):], ""))
    if lokaal.startswith("whatsapp_") and lokaal[len("whatsapp_"):].isdigit():
        return e164(lokaal[len("whatsapp_"):])
    if lokaal.startswith("signal_"):
        return e164(signal.get(lokaal[len("signal_"):], ""))
    return ""


def bereken(direct, lid_map, signal):
    """Alleen contacten uit je privéchats (m.direct), niet alle groepsleden."""
    uit = {}
    for mxid in direct:
        n = nummer_voor(mxid, lid_map, signal)
        if n:
            uit[mxid] = n
    return dict(sorted(uit.items()))


def matrix(methode, pad, token=None, data=None):
    req = urllib.request.Request(SYNAPSE + pad, method=methode,
                                 data=None if data is None else json.dumps(data).encode())
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read() or b"{}")


def token_halen():
    """Vast apparaat-ID, zodat er niet bij elke keer een nieuwe sessie bijkomt."""
    if TOKEN.exists():
        return TOKEN.read_text().strip(), None
    import yaml
    admin = yaml.safe_load(SETTINGS.read_text())["admin"]
    antw = matrix("POST", "/_matrix/client/v3/login", data={
        "type": "m.login.password",
        "identifier": {"type": "m.id.user", "user": admin["username"]},
        "password": admin["password"],
        "device_id": "QUITCHAT_CONTACTEN",
        "initial_device_display_name": "QuitChat contacten (server)",
    })
    TOKEN.parent.mkdir(parents=True, exist_ok=True)
    TOKEN.write_text(antw["access_token"])
    TOKEN.chmod(0o600)
    return antw["access_token"], antw["user_id"]


def main():
    if not (MAP / "data").is_dir():
        print("De kluis is dicht; niets gedaan.")
        return 0
    lid_map = dict(lees_db(BRIDGES / "whatsapp/mautrix-whatsapp.db",
                           "select lid, pn from whatsmeow_lid_map"))
    signal = dict(lees_db(BRIDGES / "signal/mautrix-signal.db",
                          "select aci_uuid, e164_number from signalmeow_recipients"
                          " where e164_number != ''"))
    token, wie = token_halen()
    try:
        wie = wie or matrix("GET", "/_matrix/client/v3/account/whoami", token)["user_id"]
    except urllib.error.HTTPError as e:
        if e.code != 401:
            raise
        TOKEN.unlink()                      # verlopen of uitgelogd: opnieuw
        token, wie = token_halen()
    basis = f"/_matrix/client/v3/user/{urllib.request.quote(wie)}/account_data/"
    try:
        direct = matrix("GET", basis + "m.direct", token)
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise
        direct = {}
    nieuw = {"nummers": bereken(direct, lid_map, signal)}
    try:
        oud = matrix("GET", basis + SOORT, token)
    except urllib.error.HTTPError:
        oud = {}
    if oud == nieuw:
        print(f"Niets veranderd ({len(nieuw['nummers'])} contacten met nummer).")
        return 0
    matrix("PUT", basis + SOORT, token, nieuw)
    print(f"Bijgewerkt: {len(nieuw['nummers'])} contacten met nummer.")
    return 0


def test():
    lid_map = {"123": "3161234"}
    signal = {"aaaa-bbbb": "+3168765"}
    assert nummer_voor("@whatsapp_lid-123:localhost", lid_map, signal) == "+3161234"
    assert nummer_voor("@whatsapp_lid-999:localhost", lid_map, signal) == ""
    assert nummer_voor("@whatsapp_3161111:localhost", lid_map, signal) == "+3161111"
    assert nummer_voor("@signal_aaaa-bbbb:localhost", lid_map, signal) == "+3168765"
    assert nummer_voor("@telegram_42:localhost", lid_map, signal) == ""
    assert nummer_voor("@admin:localhost", lid_map, signal) == ""
    direct = {"@whatsapp_lid-123:localhost": ["!a:localhost"], "@discord_1:localhost": ["!b:localhost"]}
    assert bereken(direct, lid_map, signal) == {"@whatsapp_lid-123:localhost": "+3161234"}
    print("Zelftest geslaagd.")
    return 0


if __name__ == "__main__":
    sys.exit(test() if "--test" in sys.argv else main())
