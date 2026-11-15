#!/usr/bin/env bash
# Haalt " (WA)", " (Signal)" en " (Discord)" weg achter bestaande namen van
# contacten en privéchats. Nieuwe namen krijgen die toevoeging al niet meer
# (07-bridges-afstellen.sh, NAAM_ZONDER_KANAAL); QuitChat toont het kanaal
# met een logo.
#
# Werkt via de officiële Matrix-weg, met de sleutel van elke bridge (as_token):
#  - profielnaam van elk bridge-contact: Synapse past daarna zelf de naam in
#    alle chats aan;
#  - naam van privéchats die de bridge naar het contact heeft genoemd.
# Veilig om opnieuw te draaien: wat al goed is, wordt overgeslagen.
#
# Gebruik: ./namen-opschonen.sh [--droog]
set -euo pipefail
DROOG=nee
[[ "${1:-}" == "--droog" ]] && DROOG=ja

sql() { docker exec muxbee-postgres-1 psql -U synapse -d synapse -AtF $'\t' -c "$1"; }
token() { docker exec "muxbee-mautrix-$1-1" sh -c 'sed -n "s/^as_token: //p" /data/registration.yaml'; }

werk="$(mktemp -d)"
trap 'rm -rf "$werk"' EXIT
chmod 700 "$werk"

# Profielen van bridge-contacten met een toevoeging.
sql "select full_user_id, displayname from profiles
     where displayname ~ ' \((WA|Signal|Discord)\)$'
       and full_user_id ~ '^@(whatsapp|signal|discord)_'" > "$werk/profielen.tsv"
# Kamernamen met een toevoeging (privéchats, genoemd naar het contact).
sql "select room_id, name from room_stats_state
     where name ~ ' \((WA|Signal|Discord)\)$'" > "$werk/kamers.tsv"
echo "Te doen: $(wc -l < "$werk/profielen.tsv") contactnamen, $(wc -l < "$werk/kamers.tsv") chatnamen."
[[ "$DROOG" == ja ]] && { head -n 3 "$werk/profielen.tsv"; echo "(droog: niets veranderd)"; exit 0; }

# Tokens alleen via een bestand met rechten 600 doorgeven, nooit op de
# opdrachtregel (die is voor iedereen zichtbaar in de proceslijst).
for b in whatsapp signal discord; do printf '%s\t%s\n' "$b" "$(token "$b")"; done > "$werk/tokens.tsv"
chmod 600 "$werk/tokens.tsv"

cat "$werk/tokens.tsv" <(echo '---') "$werk/profielen.tsv" <(echo '---') "$werk/kamers.tsv" \
  | docker exec -i muxbee-synapse-1 python -I -c '
import json, re, sys, time, urllib.parse, urllib.request
delen = sys.stdin.read().split("\n---\n")
tokens = dict(r.split("\t", 1) for r in delen[0].splitlines() if r)
profielen = [r.split("\t", 1) for r in delen[1].splitlines() if "\t" in r]
kamers = [r.split("\t", 1) for r in delen[2].splitlines() if "\t" in r]
achter = re.compile(r" \((WA|Signal|Discord)\)$")
bridge = {"WA": "whatsapp", "Signal": "signal", "Discord": "discord"}
q = urllib.parse.quote

def put(pad, token, als, inhoud):
    url = f"http://localhost:8008{pad}?user_id={q(als)}"
    req = urllib.request.Request(url, data=json.dumps(inhoud).encode(), method="PUT",
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    for poging in range(5):
        try:
            urllib.request.urlopen(req, timeout=60).read(); return True
        except urllib.error.HTTPError as e:
            if e.code == 429: time.sleep(2 + poging * 2); continue
            print(f"  fout {e.code} bij {als}: {e.read()[:120]!r}"); return False
    return False

goed = fout = 0
for i, (wie, naam) in enumerate(profielen, 1):
    m = achter.search(naam)
    b = wie[1:].split("_", 1)[0]
    if put(f"/_matrix/client/v3/profile/{q(wie)}/displayname", tokens[b], wie,
           {"displayname": naam[: m.start()]}): goed += 1
    else: fout += 1
    if i % 500 == 0: print(f"  contacten: {i}/{len(profielen)}", flush=True)
print(f"Contactnamen: {goed} aangepast, {fout} fout.")

goed = fout = 0
for kamer, naam in kamers:
    m = achter.search(naam)
    b = bridge[m.group(1)]
    if put(f"/_matrix/client/v3/rooms/{q(kamer)}/state/m.room.name/", tokens[b],
           f"@{b}bot:localhost", {"name": naam[: m.start()]}): goed += 1
    else: fout += 1
print(f"Chatnamen: {goed} aangepast, {fout} fout.")
'
