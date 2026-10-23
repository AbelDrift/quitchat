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

- E-mailbrug (IMAP/SMTP), Telegram en andere bridges.
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
- **Kanaal kiezen per antwoord**, of een vaste regel per contact.
- **Privévoorkeur per contact:** stelt het meest privévriendelijke kanaal voor.
- **Burner-knop** en **opstart-goedkeuring** voor de kluis.
- **Backup-instellingen.**

## Bewust niet gedaan

- Nepverkeer om patronen te verbergen: kans op blokkade van het account.
- Extra versleuteling bovenop WhatsApp: onleesbaar voor ontvangers zonder
  QuitChat. Dan liever overstappen naar Signal of Matrix.
