# QuitChat – plan

## Doel

Eén app voor al je chats en e-mail, zoals Beeper, maar zonder bedrijfscloud
ertussen. De brug draait op een eigen thuis-server (een pc, of een
Raspberry Pi 4/5). Mainstream messengers worden "ingepakt", zodat de
gebruiker er juist op vooruitgaat: meer privacy, meer keuze, en geen
abonnement.

Uitgangspunten:

- **Geen cloud van derden:** berichten gaan alleen via apparaten van de eigenaar.
- **Open source en vrij** (AGPL-3.0); bestaande, bewezen onderdelen hergebruiken.
- **Eerlijk over privacy:** wat niet op te lossen is, legt de app uit, met een
  advies. De gebruiker maakt zelf de afweging.
- **De eigenaar houdt de controle:** eigen backups, eigen sleutels, wissen op afstand.

## Fases

### Fase 1 – Thuis-server ✅

Versleutelde kluis (LUKS2) met herstelcode, Synapse + mautrix-bridges via
muxbee, vaste bridge-versies, toegang vanaf de telefoon via Tailscale met
HTTPS. Een oude telefoon zonder simkaart houdt WhatsApp gekoppeld.

### Fase 2 – Meer koppelingen en privacy per kanaal

- Telegram ✅ en andere chat-bridges (bijvoorbeeld Discord).
- **E-mail blijft voorlopig buiten QuitChat.** E-mail werkt anders dan chatten
  (lange berichten, bijlagen, mappen, filters) en daar is al een goede, vrije
  oplossing voor: [Thunderbird](https://www.thunderbird.net). Later misschien
  wel: een melding in QuitChat bij belangrijke mail.
- Automatisch: WhatsApp zonder toegang tot contacten, geen Google Drive-backup.
- Voorstellen: VPN voor de koppeltelefoon, privacy-instellingen per app.
- **Privacy-kaart per kanaal:** wat Signal, WhatsApp, Messenger, Telegram en
  e-mail over je kunnen zien, met een advies.

### Fase 3 – Burner

Burnen = de sleutel vernietigen, niet bestanden overschrijven (werkt binnen
een seconde, ook op SD-kaarten en SSD's).

- **Kluis openen via de telefoon:** de server kent zijn eigen sleutel niet en
  vraagt bij elke start toestemming aan de telefoon van de eigenaar.
- **Burn op afstand:** knop in de app (pincode/vingerafdruk) vernietigt de
  sleutels, wist de bridge-koppelingen en schakelt de server uit.
- **Burn bij loskoppeling:** geen toestemming binnen de ingestelde tijd, of
  burn-modus aan? Dan krijgt de server geen sleutel en vernietigt hij zijn
  sleutelopslag. Werkt ook als de server van internet wordt gehouden.
- Alleen het deel van QuitChat wordt gewist; andere toepassingen op dezelfde
  machine blijven staan.

### Fase 4 – Versleutelde backups

- Instelbaar: elke X MB nieuwe data of elke X berichten.
- Versleutelde zip (met of zonder extra wachtwoord) naar de eigen cloud
  (Nextcloud, WebDAV, rclone) of handmatig downloaden.
- **Herstel na een burn** met de herstelcode op papier (of verborgen op een
  muziek-cd, of in stukken verdeeld met Shamir's Secret Sharing).
- **Backup-burner:** wist backups in de eigen cloud en vernietigt de
  backup-sleutel.

### Fase 5 – Eigen app

Waarschijnlijk gebaseerd op een bestaande open-source Matrix-app
(bijvoorbeeld FluffyChat), uitgebreid met:

- **Eén persoon = één contact:** alle kanalen van iemand in één tijdlijn.
  Automatisch samenvoegen op telefoonnummer (vaak gelijk bij WhatsApp,
  Signal en Telegram); handmatig samenvoegen of splitsen als de app het mis
  heeft. Een klein icoon per bericht laat zien via welk kanaal het kwam.
- **Groepen bundelen:** groepen blijven per platform (de leden verschillen
  bijna altijd), maar je kunt ze zelf bundelen en labelen, bijvoorbeeld
  "Familie" met de WhatsApp- én de Signal-groep erin.
- **Eén status voor alle platforms:** één knop "status plaatsen" die de
  status zet op elk platform waar de bridge dat ondersteunt. Voor de rest
  laat de app zien waar het niet lukte, met een snelkoppeling om het daar
  zelf te doen, en per platform wie de status kan zien. Nog uit te zoeken:
  welke bridges statusupdates en stories kunnen versturen (WhatsApp lijkt
  ze wel te kunnen ontvangen; Signal- en Telegram-stories waarschijnlijk
  niet), en of de info- of bio-tekst per platform aan te passen is.
- **Kanaal kiezen per antwoord**, of een vaste regel per contact.
- **Privévoorkeur per contact:** stelt het meest privévriendelijke kanaal voor.
- **Burner-knop** en **opstart-goedkeuring** voor de kluis.
- **Backup-instellingen.**

## Bewust niet gedaan

- Nepverkeer om patronen te verbergen: kans op blokkade van het account.
- Extra versleuteling bovenop WhatsApp: onleesbaar voor ontvangers zonder
  QuitChat. Dan liever overstappen naar Signal of Matrix.

## Te onderzoeken – hulp welkom

Ideeën waar we (nog) geen tijd voor hadden, of waarvan nog niet duidelijk
is of en hoe ze kunnen. Wil je helpen? Kies er een, open een issue en
vertel wat je gaat uitzoeken.

| Onderwerp | Wat is er bekend | Wat moet uitgezocht worden |
| --- | --- | --- |
| **Microsoft Teams (persoonlijk)** | Er is een experimentele community-bridge in Go (mautrix bridgev2) voor persoonlijke Teams (teams.live.com). Bewerken, verwijderen en threads werken nog niet. | Hoe stabiel is hij? Kan hij in muxbee/`brug` worden opgenomen? Werken meerdere accounts tegelijk? |
| **Microsoft Teams (school/werk)** | De officiële Element-bridge is niet meer te koop en vroeg beheerdersrechten. mx-puppet-teams lijkt niet meer onderhouden. | Is er een werkende, eerlijke oplossing? Altijd alleen met toestemming van de organisatie. |
| **Nieuwe Telegram-bridge** | Muxbee maakt instellingen voor de oude Python-bridge (v0.15.3, geen updates meer). De nieuwe Go-versie (v0.2604.0 en later) weigert die. | Instellingen voor de nieuwe bridge laten genereren (fork van muxbee) en overstappen zonder je koppeling kwijt te raken. |
| **Serveradres in muxbee** | `brug` zet `public_baseurl` nu achteraf goed, omdat muxbee het steeds op `localhost` zet. | Een nette optie in muxbee zelf (fork), zodat het trucje niet meer nodig is. |
| **Status op alle platforms** | WhatsApp-statusupdates lijken binnen te komen; Signal- en Telegram-stories waarschijnlijk niet. | Welke bridges kunnen een status of story versturen? Kan de info- of bio-tekst per platform worden aangepast? |
| **Headscale i.p.v. Tailscale** | Tailscale werkt goed, maar ziet welke apparaten je hebt. Headscale is een zelf te hosten vervanger. | Handleiding of script om QuitChat met Headscale te gebruiken, ook voor HTTPS. |
| **Raspberry Pi 4/5** | Het plan is ooit naar een zuinige Pi te verhuizen. | Alle scripts testen op Raspberry Pi OS (64-bit), en een verhuisstappenplan van pc naar Pi. |
| **Muxbee-sessies** | Muxbee logt bij elke `brug up` in, waardoor er steeds nieuwe sessies bijkomen. | Hergebruik van één sessie, of automatisch opruimen. |
| **E-mailmelding** | E-mail blijft bewust bij Thunderbird. | Eventueel een melding in QuitChat bij belangrijke mail, zonder de mail zelf te bridgen. |
