# Centrale accentkleur

17 oktober 2026.

Beheer heeft een onderdeel Instellingen met kleurkiezer, hexcode, licht/donker-voorbeelden, Kleur opslaan en Standaardkleur herstellen. De accentkleur geldt voor de huisstijl en gewone acties in de hele app, ook het inlogscherm en de afgeschermde activering-/herstelpagina. De persoonlijke licht/donker-keuze blijft behouden. Semantische kleuren zoals foutmeldingen en winnaarsmarkering blijven apart.

Het frontendalgoritme past de tint per thema aan zodat de accentkleur als tekst minimaal 4,5:1 contrast heeft tegen zowel paneel als achtergrond. Zwart of wit wordt gekozen voor tekst op de accentkleur. Ook een witte, zwarte of felgele invoer levert leesbare voorbeelden op. De gekozen basiskleur blijft opgeslagen; de weergave wordt per thema afgeleid.

De standaard blijft de bestaande licht/donker-groene combinatie totdat een beheerder een kleur opslaat. Er is geen kleur voor de gebruiker gekozen tijdens deze release. Opnieuw laden haalt de instelling opnieuw op. Bij een fout wordt de bestaande kleur behouden en blijft de gekozen invoer beschikbaar om opnieuw te proberen. Een verouderde uitleesaanvraag kan een succesvol opgeslagen kleur niet terugzetten. Niet-opgeslagen wijzigingen worden bewaakt bij navigatie.

## Opslag en beveiliging

Migratie `20261017081215_app_accent_settings.sql` voegt het geïsoleerde schema predict_branding toe, met een singleton-instelling en wijzigingsaudit. Beide tabellen hebben RLS en geen directe rechten voor anon/authenticated. Schema-USAGE voor deze rollen ontsluit alleen expliciet toegestane functies; er zijn geen rechten op het bestaande predict_private-schema aan anon toegevoegd.

Publieke RPC's zijn SECURITY INVOKER. De afgeschermde implementaties hebben een lege search_path. get_app_appearance is ook anoniem leesbaar maar retourneert uitsluitend de accentkleur. set_app_appearance is alleen voor ingelogde gebruikers uitvoerbaar en controleert via de bestaande ko_admin-functie op admin/super_admin. Alleen volledige #RRGGBB-kleuren of null voor standaard zijn toegestaan. Werkelijke wijzigingen worden met actor, tijdstip, oude en nieuwe kleur gelogd; ongewijzigde opslag maakt geen extra auditregel.

## Verificatie

- Lokale PostgreSQL/PGlite-suite met bestaande knock-out-/poule-/beheercontroles en nieuwe kleurtest geslaagd.
- Hosted transactionele kleurtest geslaagd, met rollback: publieke kleurrespons, anoniem/gewoon account niet kunnen wijzigen, beheerder wel, normalisatie, ongeldige/CSS-injectie-invoer, standaardherstel, directe tabelisolatie en audit. Geen testaccounts of kleurwijzigingen achtergebleven.
- De gedeelde kleurmodule wordt ook getest op de activering-/herstelpagina, zonder wijziging van de niet-persistente accountflow of het opschonen van codes.
- Nieuwe kleur-browsertest met fictieve persistente backend: opslaan/herladen, mislukte opslag, contrastvoorbeelden voor wit/zwart/geel, standaardherstel, donker thema, kleur op login en beperkte beheertoegang.
- Browserregressies voor toernooien, beheer, account/profiel, poules, accountbeheer en gebruikersnaamlogin geslaagd. Mobiele donkere kleurweergave visueel gecontroleerd.
- Voor/na: 63 wedstrijden, 32 voorspellingen, 151 wedstrijdaudits; fingerprint b726d0590518c126828790d3e8ec8e98 ongewijzigd. Geen officiële sportgegevens veranderd.
- Security advisors: de 16 bestaande definer-waarschuwingen en bestaande Auth-waarschuwing zijn gelijk gebleven. De twee nieuwe private tabellen geven verwachte informatieve RLS-zonder-policy-meldingen; directe toegang is juist ingetrokken en getest. Geen nieuwe publieke definer-functies.

Na publicatie vergelijkt de livecontrole de bestanden met main, opent mobiel login/herstel en leest de openbare kleur-RPC zonder ingelogd account. Er worden geen echte accounts of wedstrijden gewijzigd.
