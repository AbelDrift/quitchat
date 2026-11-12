"""
QuitChat Burner – minimale web-app die via Tailscale bereikbaar is.
Gebruikt een PIN om vijf acties te beschermen:
  - kluis openen (met LUKS-wachtwoord)
  - burn
  - grace-tijd aanpassen
  - scherp aan/uit
Draait als user 'quitchat-burner', roept wrappers via sudo op.
"""
from __future__ import annotations

import os
import subprocess
import time
from pathlib import Path

from flask import Flask, flash, redirect, render_template, request, session, url_for
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

APP_DIR = Path("/opt/quitchat-burner")
STATE_DIR = Path("/var/lib/quitchat-burner")
PIN_FILE = STATE_DIR / "pin.hash"
SESSION_FILE = STATE_DIR / "session.key"
GRACE_FILE = STATE_DIR / "grace-minuten"
SCHERP_FILE = STATE_DIR / "scherp"
WRAPPERS = APP_DIR / "wrappers"

# Simpele brute-force-rem: na 5 mislukte pogingen 60 sec lock.
_mislukkingen = 0
_lock_tot = 0.0

ph = PasswordHasher()

app = Flask(__name__)
app.secret_key = SESSION_FILE.read_bytes()

# Deze app wordt via Tailscale aangeboden op pad /burner. Tailscale strijkt dat
# pad van de inkomende verzoeken, dus Flask ziet "/" en "/grace" enz. We zetten
# SCRIPT_NAME zodat url_for() in de templates "/burner/grace" teruggeeft en
# redirects naar "/burner/" wijzen in plaats van naar "/".
PATH_PREFIX = "/burner"

def _script_name_middleware(wsgi_app):
    def wrapped(environ, start_response):
        environ["SCRIPT_NAME"] = PATH_PREFIX
        return wsgi_app(environ, start_response)
    return wrapped

app.wsgi_app = _script_name_middleware(app.wsgi_app)


def _run_wrapper(naam: str, *, stdin: str | None = None, extra_args: list[str] | None = None):
    cmd = ["sudo", "-n", str(WRAPPERS / naam)]
    if extra_args:
        cmd.extend(extra_args)
    return subprocess.run(
        cmd,
        input=stdin.encode() if stdin is not None else None,
        capture_output=True,
        timeout=60,
    )


def kluis_open() -> bool:
    r = _run_wrapper("status.sh")
    return r.returncode == 0


def grace_minuten() -> int:
    try:
        return int(GRACE_FILE.read_text().strip())
    except (FileNotFoundError, ValueError):
        return 60


def scherp_aan() -> bool:
    return SCHERP_FILE.exists()


def verifieer_pin(gegeven: str) -> bool:
    global _mislukkingen, _lock_tot
    if time.time() < _lock_tot:
        return False
    try:
        hash_str = PIN_FILE.read_text().strip()
    except FileNotFoundError:
        return False
    try:
        ph.verify(hash_str, gegeven)
    except VerifyMismatchError:
        _mislukkingen += 1
        if _mislukkingen >= 5:
            _lock_tot = time.time() + 60
            _mislukkingen = 0
        return False
    _mislukkingen = 0
    return True


@app.route("/")
def index():
    return render_template(
        "index.html",
        open=kluis_open(),
        grace=grace_minuten(),
        scherp=scherp_aan(),
    )


@app.route("/open-kluis", methods=["POST"])
def open_kluis():
    pin = request.form.get("pin", "")
    wachtwoord = request.form.get("wachtwoord", "")  # geheimen-check: ok (formulierveld)
    if not verifieer_pin(pin):
        flash("Burner-PIN klopt niet.", "fout")
        return redirect(url_for("index"))
    if not wachtwoord:
        flash("Geen kluis-wachtwoord ingevuld.", "fout")
        return redirect(url_for("index"))
    r = _run_wrapper("open-kluis.sh", stdin=wachtwoord)
    if r.returncode == 0:
        flash("Kluis geopend.", "ok")
    else:
        fout = (r.stderr.decode(errors="replace") or r.stdout.decode(errors="replace"))[-300:]
        flash(f"Kluis openen mislukte: {fout}", "fout")
    return redirect(url_for("index"))


@app.route("/burn", methods=["POST"])
def burn():
    pin = request.form.get("pin", "")
    bevestiging = request.form.get("bevestiging", "")
    if not verifieer_pin(pin):
        flash("Burner-PIN klopt niet.", "fout")
        return redirect(url_for("index"))
    if bevestiging != "BURN":
        flash("Typ BURN in hoofdletters om door te gaan.", "fout")
        return redirect(url_for("index"))
    r = _run_wrapper("burn.sh", extra_args=["--yes"])
    if r.returncode == 0:
        flash("BURN uitgevoerd. De kluis is onherroepelijk weg.", "ok")
    else:
        fout = (r.stderr.decode(errors="replace") or r.stdout.decode(errors="replace"))[-300:]
        flash(f"Burn mislukt: {fout}", "fout")
    return redirect(url_for("index"))


@app.route("/grace", methods=["POST"])
def set_grace():
    pin = request.form.get("pin", "")
    if not verifieer_pin(pin):
        flash("Burner-PIN klopt niet.", "fout")
        return redirect(url_for("index"))
    minuten = request.form.get("minuten", "60").strip()
    if not minuten.isdigit() or int(minuten) > 1440:
        flash("Vul een getal in tussen 0 en 1440 (minuten).", "fout")
        return redirect(url_for("index"))
    GRACE_FILE.write_text(minuten)
    flash(f"Grace-tijd ingesteld op {minuten} minuten.", "ok")
    return redirect(url_for("index"))


@app.route("/scherp", methods=["POST"])
def toggle_scherp():
    pin = request.form.get("pin", "")
    if not verifieer_pin(pin):
        flash("Burner-PIN klopt niet.", "fout")
        return redirect(url_for("index"))
    actie = request.form.get("actie", "")
    if actie == "aan":
        SCHERP_FILE.touch()
        flash("SCHERP aan: volgende herstart = directe burn.", "ok")
    elif actie == "uit":
        SCHERP_FILE.unlink(missing_ok=True)
        flash("Scherp uit.", "ok")
    return redirect(url_for("index"))


if __name__ == "__main__":
    # Alleen localhost; Tailscale serve zet er HTTPS voor.
    app.run(host="127.0.0.1", port=9090)
