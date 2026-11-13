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
