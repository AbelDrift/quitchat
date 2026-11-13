# Fase 5 – De eigen app (QChat)

Element X werkt, maar toont kanalen en niet mensen. De eigen app laat zien
wat Element nooit gaat doen: één contact per persoon, per antwoord kiezen
via welk kanaal, en de burner en backups op je telefoon.

## Naam

- **QuitChat** blijft de naam van het project, de repo en de app in de
  winkel (F-Droid).
- **QChat** is de korte naam: onder het icoon op je telefoon, in het logo,
  en in de gewone omgangstaal.
- Let op: "QChat" en "Q-Chat" worden ook gebruikt door anderen (onder meer
  een oude push-to-talk-dienst van Qualcomm en een AI-chat van Quizlet).
  Daarom niet "QChat" als officiële appnaam, wel als korte naam.

## Basis: een fork van FluffyChat

Besloten (13 nov 2026). Vergeleken:

| | FluffyChat-fork | Element X-fork | Zelf bouwen |
| --- | --- | --- | --- |
| Taal | Flutter (Dart) | Kotlin + Swift | Flutter of Tauri + Matrix-SDK |
| Eén codebase telefoon en pc | Ja (Android, iOS, Linux, web) | Nee, twee apps | Ja |
| Licentie | AGPL-3.0, gelijk aan QuitChat | Apache/AGPL | Vrij |
| Zonder Google (UnifiedPush) | Ja, werkt met eigen ntfy | Beperkt | Zelf bouwen |
| Tijd tot werkende basis | Kort | Lang | Lang |

Waarom: één codebase voor de Fairphone (zonder Google), de andere telefoon,
de tablet en de pc; dezelfde licentie; UnifiedPush werkt al, dus meldingen
via de eigen ntfy-server zonder Google.

**Eigen gegevens zonder eigen server:** samengevoegde contacten, de keuze van
kanaal per contact en dergelijke bewaart de app als Matrix *account data*
(eigen event-type, bijv. `nl.quitchat.contacten`). Dat staat in je eigen
Synapse, gaat mee in de versleutelde backups en is automatisch op al je
apparaten gelijk.

## Apparaten

Eerst de **Fairphone** (Android zonder Google) en de **thuis-pc** (Linux).
Dat is dezelfde app: Flutter bouwt uit één codebase een Android- en een
Linux-versie. Andere telefoons en tablets volgen later; dan testen we ook
hoe de installatie daar gaat.

## Wensen van Abel (13 nov 2026)

### Contacten

- Samenvoegen mag het **adresboek van de telefoon** gebruiken (met
  toestemming), naast wat de bridges weten.
- **Contact worden zonder telefoonnummer of ander chat-account:** twee
  QChat-gebruikers koppelen elkaar door een **QR-code** te scannen, zoals bij
  Session. Een nummer is dus niet nodig om iemands contact te worden.
  - Binnen één QuitChat-server werkt dat direct (de QR-code bevat het
    Matrix-adres).
  - Tussen verschillende QuitChat-servers zou Matrix federatie nodig hebben,
    en dus een echte domeinnaam. De huidige server heet `localhost`, en die
    naam kan in Synapse niet achteraf veranderen.
  - **Gekozen richting (13 nov 2026): zoals Session.** Geen nummer, geen
    account, geen eigen server nodig; je wisselt een ID uit via een QR-code.
    Let op: Session is technisch geen directe telefoon-naar-telefoon-
    verbinding, maar een netwerk van onafhankelijke servers dat berichten
    versleuteld en via omwegen (onion routing) doorgeeft en tijdelijk bewaart,
    zodat ze ook aankomen als de ander offline is.
  - **Voorstel:** QChat spreekt het Session-netwerk zelf. Een QR-contact is
    dan een Session-contact, en je kunt ook chatten met mensen die alleen de
    Session-app hebben. Dat lost meteen het ontbreken van een Session-bridge
    op. **Uitzoeken:** kan de bibliotheek van Session (`libsession`) vanuit
    Flutter gebruikt worden, wat is de licentie, en hoe werkt het samen met
    de Matrix-kant in één contact?

### Uiterlijk

- Zo veel mogelijk zoals de **donkere modus van WhatsApp**, om te wisselen
  met een **lichte, lichtgrijze** versie met dezelfde mogelijkheden.
- **Geen WhatsApp-achtergronden.** Standaard gewoon donker of licht.
- **Eigen achtergronden:** gebruikers en de community kunnen zelf
  achtergronden maken en met elkaar uitwisselen, volgens één vaste
  specificatie (formaat, beeldverhouding, resolutie, bestandsgrootte). Die
  specificatie komt in een apart document.
- **Alles aan te passen:** een **stijl-editor** (configurator) voor kleuren,
  lettertypes, bubbels en dergelijke, zodat iedereen het ontwerp naar wens
  kan maken. Stijlen zijn ook uit te wisselen.

### Status plaatsen (broadcast-knop)

- Eén **broadcast-knop** om een status te plaatsen: foto, filmpje of tekst.
- Met een **editor** om zelf iets samen te stellen: eigen achtergrond,
  tekst eroverheen (positioneren, verschillende tekststijlen), een geluidje
  erbij, enz. Ruimer dan WhatsApp, waar dat lelijk beperkt is.
- Het resultaat blijft **binnen de grenzen van WhatsApp**, zodat ook
  mensen die alleen WhatsApp hebben het goed zien (video tot ongeveer
  1 minuut; exacte grenzen voor duur, resolutie en bestandsgrootte nog
  vastleggen). De editor rendert alles tot één gewone afbeelding of video.

## Stappen

| Stap | Wat | Klaar als |
| --- | --- | --- |
| 5a | **Basis**: fork, naam en logo, bouwen op de thuis-pc, testen op de Fairphone, inloggen op de eigen server, meldingen via ntfy | De app vervangt Element X voor gewoon gebruik |
| 5b | **Eén persoon = één contact**: automatisch samenvoegen op telefoonnummer, handmatig samenvoegen en splitsen | Contactenlijst toont mensen, niet kanalen |
| 5c | **Eén tijdlijn per persoon**, met een klein kanaal-icoon per bericht | Alle chats met iemand in één scherm |
| 5d | **Kanaal kiezen per antwoord**, plus een vaste voorkeur per contact en een privacy-advies | Antwoorden gaat via het gekozen kanaal |
| 5e | **Status**: statussen bekijken en plaatsen (zie hieronder) | Eén knop "status plaatsen" |
| 5f | **Burner en backups**: kluis openen, burn, grace-tijd, scherp; backup-status en meldingen | Geen browser meer nodig voor de burner |
| 5g | **Privacy-kaart** per kanaal: wat ziet WhatsApp, Signal, Telegram, Discord | Uitleg en advies in de app |

## Statusupdates

Wat de bridges nu kunnen (13 nov 2026):

| Platform | Bekijken | Plaatsen | Hoe |
| --- | --- | --- | --- |
| WhatsApp | Ja | Ja | Instelling `enable_status_broadcast: true` maakt een kamer "WhatsApp Status" met de statussen van je contacten. Met `disable_status_broadcast_send: false` wordt wat je in die kamer stuurt jouw status. Staat nu nog uit. |
| Signal | Nog niet | Nog niet | De Signal-bridge heeft geen instelling voor stories. Uitzoeken: ondersteunt signalmeow stories, of kan het erbij? |
| Telegram | Onbekend | Onbekend | Uitzoeken of de Go-bridge stories doorgeeft. |
| Discord | n.v.t. | Alleen "custom status" | Uitzoeken of de bridge die kan zetten. |

In de app: een tabblad **Status** met de statussen van iedereen (per persoon
samengevoegd, net als de chats) en één knop **Status plaatsen**. Die zet de
status op elk platform dat het kan, en laat zien waar het niet lukte, met
een snelkoppeling om het daar zelf te doen. Per platform staat erbij wie de
status kan zien.

## Nodig om te beginnen

- Flutter en de Android SDK op de thuis-pc (een paar GB). Dezelfde
  installatie kan later ook voor de camera-fix van de FMD-app.
- De Fairphone via USB met *USB-foutopsporing* aan, voor het testen.
- Een eigen repo voor de app (fork van FluffyChat), naast de server-repo.
