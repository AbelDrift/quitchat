# Gedeelde controles voor het openen en sluiten van de kluis.
# Wordt ingelezen (source) door scripts/kluis-open.sh, scripts/kluis-dicht.sh
# en wrappers/open-kluis.sh. Verwacht NAAM en KLUIS.
#
# Twee dingen die eerder misgingen:
#  - Een alleen-lezen kluis (de udisksd-race, zie kluis-open.sh): de mapper
#    blijft dan ro bestaan, en opnieuw koppelen geeft weer een ro kluis.
#  - Een "zombie": de kluis is hier losgekoppeld, maar een proces in een
#    andere mount-namespace (een container, of een dienst met PrivateTmp)
#    heeft nog een eigen kopie van de koppeling. Dan kan cryptsetup hem niet
#    sluiten, en is hij dus nog niet echt dicht.

# De burner-webapp draait in een systemd-sandbox (ProtectSystem=strict): daar
# zijn /run en /srv alleen-lezen (cryptsetup-lock faalt) en zou een mount
# alleen binnen de sandbox bestaan. Draai het script dan opnieuw buiten de
# sandbox, als tijdelijke systemd-unit; stdin (het wachtwoord) gaat mee.
buiten_sandbox() {
  [[ "$(readlink /proc/self/ns/mnt)" == "$(readlink /proc/1/ns/mnt)" ]] && return 0
  [[ -n "${KLUIS_BUITEN_SANDBOX:-}" ]] && { echo "Nog steeds in een sandbox." >&2; exit 1; }
  exec systemd-run --quiet --pipe --wait --collect -E KLUIS_BUITEN_SANDBOX=1 \
    "$(readlink -f -- "$0")" "$@"
}

kluis_dm() { basename "$(readlink -f "/dev/mapper/$NAAM")"; }

# Is de geopende kluis (de mapper) alleen-lezen?
mapper_ro() { [[ "$(cat "/sys/block/$(kluis_dm)/ro" 2>/dev/null)" == 1 ]]; }

# Processen die de kluis nog vasthouden vanuit een andere mount-namespace
# (de onze telt niet mee). Geeft per programma het aantal; leeg = niemand.
kluis_vasthouders() {
  local mm eigen p ns
  mm="$(cat "/sys/block/$(kluis_dm)/dev" 2>/dev/null)" || return 0
  eigen="$(readlink /proc/self/ns/mnt)"
  for p in $(grep -l " $mm " /proc/[0-9]*/mountinfo 2>/dev/null | cut -d/ -f3); do
    ns="$(readlink "/proc/$p/ns/mnt" 2>/dev/null)" || continue   # al gestopt
    [[ "$ns" == "$eigen" ]] && continue
    cat "/proc/$p/comm" 2>/dev/null
  done | sort | uniq -c | sort -rn | head -5
}

# Mapper sluiten en de loop-devices van de kluis opruimen.
mapper_sluiten() {
  cryptsetup close "$NAAM" || return 1
  local loop
  for loop in $(losetup -j "$KLUIS" -O NAME --noheadings 2>/dev/null); do
    losetup -d "$loop" 2>/dev/null || true
  done
}

# Voor het openen: ruim een oude alleen-lezen mapper op. Lukt dat niet omdat
# iemand hem vasthoudt, dan is een herstart nodig (exit 3).
mapper_opruimen_voor_openen() {
  [[ -e "/dev/mapper/$NAAM" ]] || return 0
  mapper_ro || return 0
  local wie
  wie="$(kluis_vasthouders)"
  if [[ -n "$wie" ]]; then
    echo "De kluis hangt nog alleen-lezen open, en wordt vastgehouden door:" >&2
    echo "$wie" >&2
    echo "Herstart de pc en open de kluis daarna opnieuw (herstart nodig)." >&2
    exit 3
  fi
  echo "Er hing nog een alleen-lezen kluis; die sluit ik eerst."
  if ! mapper_sluiten; then
    echo "Sluiten lukte niet. Herstart de pc en probeer opnieuw (herstart nodig)." >&2
    exit 3
  fi
}
