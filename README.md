# QuitChat

**Stop met betaalde, gesloten chatdiensten. Houd je contacten.**

Iedereen zit op WhatsApp, dus je kunt er bijna niet omheen. QuitChat pakt
mainstream messengers in en zet ze terug in jouw handen: al je chats
(WhatsApp, Signal en meer) op één plek, via een server **bij jou thuis**.
Zonder cloud van een bedrijf ertussen, zonder abonnement, en met de keuzes
bij jou.

> **Status: vroeg en experimenteel.** Fase 1 (de thuis-server) werkt.
> De eigen app, de burner en versleutelde backups worden nog gebouwd.
> Gebruik het nog niet voor dingen waar je leven van afhangt.

## Wat het doet

- **Eén plek voor al je chats:** WhatsApp, Signal, Telegram en meer in één
  app, via [Matrix](https://matrix.org). (E-mail laten we aan
  [Thunderbird](https://www.thunderbird.net) over.)
- **Jouw server, jouw data:** alles draait op een eigen pc of Raspberry Pi.
  Berichten worden pas daar ontsleuteld, nooit bij een tussenpartij.
- **Versleutelde kluis:** alle gegevens staan in een LUKS-kluis, met een
  herstelcode op papier.
- **Bereikbaar vanaf je telefoon** via [Tailscale](https://tailscale.com),
  met HTTPS, alleen voor je eigen apparaten.
- **Geen telefoon met al die apps nodig:** een oude telefoon thuis (zonder
  simkaart) houdt WhatsApp gekoppeld.

## Wat er nog komt

| Fase | Wat | Status |
| --- | --- | --- |
| 1 | Thuis-server: kluis, Matrix, bridges, toegang via Tailscale | ✅ Werkt |
| 2 | Meer koppelingen (Telegram ✅) en privacy-instellingen per kanaal | Bezig |
| 3 | Burner: kluis openen via je telefoon, wissen op afstand en bij diefstal | Gepland |
| 4 | Versleutelde backups (per X MB of X berichten) naar je eigen cloud | Gepland |
| 5 | Eigen app: één contact per persoon, kanaal kiezen per antwoord, privacy-kaart | Gepland |

Meer uitleg: [docs/plan.md](docs/plan.md).

## Installeren

Zie **[docs/installatie.md](docs/installatie.md)**. In het kort, op Ubuntu:

```bash
git clone https://codeberg.org/AbelDrift/quitchat.git
cd quitchat/scripts
sudo ./01-voorbereiden.sh          # Docker, zram, slaapstand uit
sudo ./02-kluis-aanmaken.sh        # versleutelde kluis + herstelcode
./03-muxbee-installeren.sh         # muxbee + het commando 'brug'
brug init && brug bridge enable signal && brug up
./04-tailscale-instellen.sh        # toegang vanaf je telefoon
```

**Nodig:** een pc of Raspberry Pi 4/5 met 64-bit Linux, minimaal 4 GB
werkgeheugen en 20 GB vrije ruimte, die altijd aan staat.

## Privacy, eerlijk verteld

- **Inhoud van je berichten:** blijft versleuteld tot op je eigen server.
- **Metadata:** WhatsApp (Meta) ziet nog steeds met wie je praat en wanneer.
  Dat kan QuitChat niet verbergen. Het advies: gebruik waar mogelijk Signal
  of Matrix. De app gaat daar later zelf bij helpen.
- **Gebruiksvoorwaarden:** WhatsApp en Meta staan bridges officieel niet
  toe. Er is een kleine kans op een blokkade van je account.
- **Tailscale** ziet welke apparaten je hebt en wanneer ze online zijn,
  niet wat je verstuurt. Wil je ook dat niet: zie
  [Headscale](https://github.com/juanfont/headscale) (zelf te hosten).

## Bijdragen

Ideeën, fouten en verbeteringen zijn welkom via de issues. Zoek je iets om
mee te beginnen? Kijk bij [Te onderzoeken](docs/plan.md#te-onderzoeken--hulp-welkom). Draai vóór je
eerste commit eenmalig:

```bash
git config core.hooksPath .githooks
```

Dan controleert `tools/geheimen-check.sh` bij elke commit of er geen
wachtwoorden, sleutels, herstelcodes, adressen of telefoonnummers meegaan.

## Gebouwd op

QuitChat staat op de schouders van:
[muxbee](https://github.com/tobocop2/muxbee) (MIT),
de [mautrix-bridges](https://github.com/mautrix) (AGPL-3.0),
[Synapse](https://github.com/element-hq/synapse) (AGPL-3.0) en
[Element](https://element.io). Zie [NOTICE.md](NOTICE.md).

## Licentie

[GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0).
Je mag QuitChat vrij gebruiken, aanpassen en delen. Bied je een aangepaste
versie aan anderen aan, ook als online dienst, dan deel je jouw aanpassingen
onder dezelfde licentie. Zo blijft QuitChat voor iedereen vrij.
