# QuitChat installeren – fase 1: thuis-server

Deze stappen zetten de basis van QuitChat op een Ubuntu-pc (getest op
Ubuntu 22.04): Docker, een versleutelde kluis voor al je berichten, muxbee
(Matrix-server Synapse + bridges + Element Web) en toegang vanaf je telefoon
via Tailscale.

Alles van QuitChat (berichten, wachtwoorden, koppelingen met WhatsApp enz.)
komt in de kluis `/srv/brug`. Is de kluis dicht, dan is alles onleesbaar.

> **Plak nooit wachtwoorden of herstelcodes in een chat, issue of bestand.**
> Haal ze ook uit foutmeldingen voordat je die aan iemand stuurt.

## Voor je begint

```bash
git clone https://codeberg.org/AbelDrift/quitchat.git
cd quitchat/scripts
chmod +x *.sh
```

Alle commando's hieronder draai je vanuit de map `scripts`.

## Stap 1 – Voorbereiden (eenmalig)

```bash
sudo ./01-voorbereiden.sh
```

Installeert Docker, zet extra werkgeheugen aan (zram: in het geheugen, dus
er komt niets onversleuteld op de schijf) en zet de slaapstand uit.

**Log daarna één keer uit en weer in.** (Of typ `newgrp docker`; dan werkt
Docker alleen in dat ene terminalvenster.)

## Stap 2 – Kluis aanmaken (eenmalig)

```bash
sudo ./02-kluis-aanmaken.sh          # 100 GB
sudo ./02-kluis-aanmaken.sh 200G     # of groter
```

1. Kies een **wachtwoord** (twee keer typen).
2. Typ het nog één keer om de **herstelcode** toe te voegen.
3. **Schrijf de herstelcode op papier.**
4. Typ de herstelcode van je papier over ter controle. Kleine letters, spaties
   en plakken mogen. Je **wachtwoord** wordt hier níet geaccepteerd: het moet
   echt de herstelcode zijn. Typ `toon` om de code nog eens te zien.

Bewaar het papier niet bij de pc, en de code niet in een bestand op de pc.
Heb je hem toch tijdelijk in een bestand gezet? Verwijder het grondig:
`shred -u <bestand>`.

## Stap 3 – Muxbee installeren (eenmalig, zonder sudo)

```bash
./03-muxbee-installeren.sh
```

Dit maakt het commando **`brug`**. Gebruik altijd `brug`, nooit `muxbee`
zelf. `brug` zorgt ervoor dat:

- alles in de kluis wordt opgeslagen (en weigert als de kluis dicht is);
- Synapse en de bridges in Docker hun eigen mappen mogen gebruiken;
- de bridges op een **vaste, stabiele versie** blijven
  (zie `~/.config/brug/versies.conf`);
- Synapse het juiste adres voor je telefoon gebruikt (na stap 7).

Daarom vraagt `brug` soms om je sudo-wachtwoord. Dat is de bedoeling.

## Stap 4 – Brug instellen en starten

```bash
brug init
brug bridge enable signal
brug bridge enable whatsapp
brug up
brug open                 # opent Element Web op http://localhost:8080
```

De eerste `brug up` duurt een paar minuten (ongeveer 1 GB downloaden).
Aan het eind zie je de gebruikersnaam (`admin`) en het wachtwoord van je
Matrix-account. Kwijt? `brug config show --show-secrets | grep -A2 "^admin:"`

**Inloggen in Element:** gebruikersnaam `admin` en dat wachtwoord. De server
staat al goed; kies niet matrix.org.

**Versleuteling instellen:** klik in Element op het tandwiel → All settings
→ het sleutel-icoon (Encryption) → **Set up recovery**. Bewaar de
herstelsleutel van Element op papier of in een wachtwoordbeheerder
(bijvoorbeeld KeePassXC). Die heb je nodig om later je telefoon te
verifiëren.

**Je naam:** All settings → Account → Display Name. Het adres
`@admin:localhost` zelf kan niet veranderen, maar alleen jij ziet het.

## Stap 5 – Signal koppelen (met je gewone telefoon)

1. Open in Element de chat **Signal bridge bot** en typ `login`.
2. Er verschijnt een QR-code. Elke ±45 seconden komt er een nieuwe;
   **alleen de onderste werkt.**
3. Telefoon: Signal → Instellingen → **Gekoppelde apparaten** → **+** →
   scan direct de onderste code (vanuit Signal, niet met de camera-app).
4. Test: stuur een bericht naar "Notitie aan mezelf" in Signal. Het
   verschijnt in Element.

Oude berichten komen niet mee; dat is een beperking van Signal.
Opnieuw beginnen met inloggen: typ `cancel` (zonder `!signal` ervoor).

## Stap 6 – WhatsApp koppelen (met een oude telefoon)

Oude telefoon klaarmaken:

1. Op **wifi** en aan de **lader**. Er hoeft geen simkaart in.
2. Installeer WhatsApp en registreer met je nummer. De sms-code komt op je
   gewone telefoon binnen; typ hem over op de oude.
3. Geef **geen toegang tot contacten**.
4. Zet **verificatie in twee stappen** aan (Instellingen → Account).
5. Zet **batterij-optimalisatie uit** voor WhatsApp
   (Instellingen → Apps → WhatsApp → Batterij → Niet beperkt).

Koppelen:

1. Open in Element de chat **WhatsApp bridge bot** en typ `login qr`.
2. Oude telefoon: WhatsApp → **⋮** → **Gekoppelde apparaten** →
   **Apparaat koppelen** → scan de onderste QR-code.
3. Je chats verschijnen. WhatsApp-groepen komen binnen als uitnodigingen;
   klik bij elk op **Accept** (niet "Decline and block").

Let op: staat WhatsApp op je gewone telefoon, dan verhuist het account naar
de oude. Verwijder het daarna van je gewone telefoon. Heeft de oude telefoon
±14 dagen geen verbinding, dan koppelt WhatsApp de brug los.

## Stap 6b – Telegram koppelen (optioneel)

1. Vraag een gratis API-sleutel aan op https://my.telegram.org (inloggen met
   je nummer; de code komt in de Telegram-app) → **API development tools** →
   App title `QuitChat`, Short name `quitchat`, Platform **Desktop** →
   **Create application**. Bewaar **api_id** en **api_hash** in je
   wachtwoordbeheerder; de hash is geheim.
2. Zet de bridge aan; muxbee vraagt om api_id en api_hash:

   ```bash
   brug bridge enable telegram
   ```

   Verkeerd ingevuld? `brug bridge disable telegram`, daarna opnieuw
   `brug bridge enable telegram` en bij "Update them?" **y** typen.
3. `brug up`, daarna in Element: chat met **@telegrambot:localhost** →
   `login` → je nummer met landcode (`+316…`) → de code uit de Telegram-app
   (en je wachtwoord als je verificatie in twee stappen hebt).

Muxbee maakt instellingen voor de **oude** Telegram-bridge. Daarom staat
Telegram vast op `v0.15.3` (zie `versies.conf`). Gewone Telegram-chats zijn
niet end-to-end versleuteld, en geheime chats worden niet doorgegeven.

## Stap 7 – Toegang vanaf je telefoon (Tailscale)

```bash
./04-tailscale-instellen.sh
```

Het script:

1. installeert Tailscale en laat je inloggen (gratis account);
2. vraagt je om in https://login.tailscale.com/admin/dns **MagicDNS** en
   **HTTPS Certificates** aan te zetten;
3. maakt je server bereikbaar op `https://<jouw-pc>.<tailnet>.ts.net`,
   **alleen voor je eigen Tailscale-apparaten**;
4. zet dat adres in `~/.config/brug/adres`, zodat `brug` Synapse er na
   elke start op zet.

Op je telefoon:

1. Installeer **Tailscale**, log in met hetzelfde account, zet het aan.
2. Test in de browser: `https://<jouw-pc>.<tailnet>.ts.net/_matrix/client/versions`
3. Installeer **Element X** (of FluffyChat) → Inloggen → **Account-provider
   wijzigen** → vul `<jouw-pc>.<tailnet>.ts.net` in → `admin` + wachtwoord.
4. Verifieer: kies in Element X "Gebruik een ander apparaat" en bevestig in
   Element Web op de pc, of voer de herstelsleutel van Element in.

Gebruikte je eerder Beeper of een andere cloud-bridge? Ontkoppel die daar,
en controleer bij **Gekoppelde apparaten** in WhatsApp en Signal dat alleen
je eigen brug er nog staat.

## Na een herstart

```bash
sudo ./kluis-open.sh      # wachtwoord of herstelcode typen
brug up
```

## Afsluiten en kluis op slot

```bash
sudo ./kluis-dicht.sh
```

## Bijwerken

```bash
brug update
```

Werkt Synapse en Element bij naar de nieuwste versie, en de bridges naar de
vaste versie uit `~/.config/brug/versies.conf`. Nieuwe stabiele bridge-
versies verschijnen rond de 16e van elke maand (zie https://mau.fi/blog/).
Pas dan het nummer in `versies.conf` aan (bijv. `v26.11`) en draai
`brug update`. Een nieuwe bridge erbij? Voeg een regel toe, bijv.
`telegram v26.10`.

## Wachtwoorden en herstelcodes beheren

| Wat | Commando of plek |
| --- | --- |
| Kluiswachtwoord veranderen | `sudo cryptsetup luksChangeKey --key-slot 0 /srv/brug.kluis` |
| Kluis-herstelcode testen | `sudo cryptsetup open --test-passphrase --key-slot 1 /srv/brug.kluis` |
| Nieuwe kluis-herstelcode (oude vervalt) | `sudo ./herstelcode-vervangen.sh` |
| Matrix-wachtwoord veranderen | Element → All settings → Account, en daarna ook in `/srv/brug/config/muxbee/settings.yaml` bij `admin:` → `password:` |

In de kluis: vak 0 = je wachtwoord, vak 1 = je herstelcode.

## Handige commando's

| Commando | Wat het doet |
| --- | --- |
| `brug` | Overzichtsscherm (TUI) |
| `brug status` | Welke onderdelen draaien |
| `brug health` | Controle of alles gezond is |
| `brug logs synapse -n 40` | Laatste regels van de Matrix-server |
| `brug logs mautrix-signal -n 40` | Laatste regels van de Signal-bridge |
| `brug logs mautrix-whatsapp -n 40` | Laatste regels van de WhatsApp-bridge |
| `tailscale serve status` | Op welk adres de server bereikbaar is |

**Niet gebruiken tenzij je het echt wilt:** `brug nuke` (wist alles).
Backups met `brug backup` zijn nog **niet versleuteld**; bewaar ze alleen
in de kluis. Versleutelde backups komen in fase 4.

## Problemen oplossen

| Wat je ziet | Oorzaak en oplossing |
| --- | --- |
| Script stopt zonder melding bij "Herstelcode maken" | Oude versie van het script; gebruik de versie uit deze repository |
| "Docker werkt nog niet voor jouw account" | Uit- en weer inloggen, of `newgrp docker` |
| `Permission denied` in de logs van Synapse of een bridge | Rechten verkeerd; `brug up` zet ze opnieuw goed |
| Signal geeft "netwerkfout" bij het scannen | Oude QR-code gescand (scan de onderste, binnen 30 sec.), of een testversie van de bridge; `brug update` zet hem op de vaste versie |
| Bot zegt "You already have an ongoing login" | Typ `cancel`, daarna opnieuw `login` |
| Element X: "Kon deze homeserver niet bereiken" | Tailscale op de telefoon aan? Test het adres in de browser; draai stap 7 |
| Element X blijft op "Offline" na inloggen | Synapse gaf `localhost` als adres. Controleer `~/.config/brug/adres`, draai `brug up`, log in Element X uit en opnieuw in |
| Element Web: "This device doesn't support encryption" bij je telefoon | Die telefoon synchroniseert niet; zie hierboven |
| Telegram-bridge "stopped", logs: "Legacy bridge config detected" | Verkeerde (nieuwe) versie; zet in `~/.config/brug/versies.conf`: `telegram v0.15.3` en draai `brug up` |
| `brug` zegt "De kluis is dicht" | `sudo ./kluis-open.sh` |

## Wat staat waar

| Wat | Waar | Versleuteld? |
| --- | --- | --- |
| Berichten, media, database, wachtwoorden, koppelingen | `/srv/brug` (kluis) | Ja |
| Het kluisbestand zelf | `/srv/brug.kluis` | Ja |
| Vaste versies, serveradres, visitekaartje | `~/.config/brug/` | Nee (geen geheimen, wel je Tailscale-adres) |
| Docker-programma's (images) | `/var/lib/docker` | Nee (geen persoonlijke gegevens) |
| Logboeken van Docker | `/var/lib/docker` | Nee, daarom klein gehouden (max. 10 MB per onderdeel) |

## Bekende beperkingen van fase 1

- **Kluis openen gaat nog met de hand.** Openen via je telefoon en de
  burner komen in fase 3.
- **Muxbee wordt niet meer onderhouden** (gearchiveerd in juni 2026).
- **Docker-groep:** wie in de groep `docker` zit, heeft feitelijk
  beheerdersrechten. Laat andere mensen niet op jouw account werken.
- **Muxbee logt bij elke `brug up` in** om de bot-chats klaar te zetten.
  Daardoor staan er in Element → Devices veel sessies met willekeurige
  namen (vanaf 172.18.0.1). Die zijn onschuldig en mogen weg.
- **Touchscreen of gedeelde pc:** laat Element niet open staan als anderen
  langslopen; zet een schermvergrendeling aan.
