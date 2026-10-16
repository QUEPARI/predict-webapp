# Handmatige knock-outtoernooien

## Gedrag

Alleen knock-out; geen groepsfase, competitieschema of sport-API. Beheer kan een toernooi met 2–128 spelers of teams aanmaken. De namenlijst bepaalt de lotingsvolgorde. Het schema wordt tot de eerstvolgende macht van twee aangevuld; de eerste namen krijgen eventuele vrijstellingen. Geen dubbele of lege namen. Er zijn altijd deelnemersaantal minus één echte wedstrijden; vrijstellingen hebben geen uitslag en leveren geen punten op.

Voor iedere ronde worden score-eenheid, first-to waar van toepassing en de winnaar-/exactscorepunten expliciet ingevuld. Er is geen nieuw standaardpuntenschema dat bestaande toernooiregels vervangt. Publicatie gebruikt de bestaande vergrendeling van puntentelling. Voor voetbal blijft de voorspelde score exclusief strafschoppen; bij een gelijke uitslag kiest beheer afzonderlijk wie doorgaat.

Het concept bevat alle rondes en toekomstige plekken. Namen kunnen in het concept worden gecorrigeerd zolang er geen voorspellingen bestaan. Na publicatie liggen de deelnemersidentiteiten vast. Tijden en spelvorm kunnen per wedstrijd worden beheerd. Bij bestaande voorspellingen wordt een wijziging van het formaat geweigerd. Een gewijzigde deadline vereist een reden en sluit voorspellingen; heropening is een expliciete actie met reden. Uitgestelde wedstrijden heropenen evenmin bij alleen een nieuwe tijd opslaan. Direct sluiten, werkelijk gestart registreren, uitstellen en annuleren zijn aparte beheeracties.

Publicatie opent complete toekomstige wedstrijden. Doorstroming vult de volgende plek en opent die wedstrijd wanneer beide deelnemers en een geldige toekomstige planning bekend zijn. Onbekende deelnemers en vrijstellingen kunnen ook via andere beheerprocedures niet worden geopend of van een uitslag voorzien. Een onbekende geplande start houdt voorspellingen gesloten. De bestaande submit_match_prediction en bestaande triggers bewaken de deadline op de server, ook zonder timer, cron of geopend scherm. Beheer toont 'Uitslag nodig' bij een verstreken start of geregistreerde werkelijke start, en claimt daarmee geen externe live-startinformatie. De statusfilter ververst ook op een open scherm.

De complete ronde-indeling is via een beveiligde RPC beschikbaar voor ingelogde gebruikers bij gepubliceerde/actieve/afgeronde/gearchiveerde toernooien. Concepten zijn alleen voor systeembeheerders zichtbaar. Er wordt geen voorspelling van iemand anders via de schemafunctie teruggegeven. Bestaande toernooien worden niet omgebouwd; hun wedstrijden, voorspellingen en puntentabellen blijven behouden. Zonder nieuw knock-outschema toont hun pagina een uitleg en de bestaande wedstrijden.

## Correcties en audit

Uitslagen gebruiken bij eerste registratie de bestaande admin_record_match_result-validatie. Een trigger plaatst winnaars door, ook wanneer bestaande beheerprocedures worden gebruikt. Scorecorrecties worden geaudit. Een winnaarcorrectie wordt geblokkeerd wanneer de volgende wedstrijd al voorspellingen, scores of een werkelijke start heeft. Die bescherming wist of herinterpreteert geen bestaande voorspellingen. Dezelfde winnaar met een gecorrigeerde score is wel mogelijk met reden. Vrijstellingen blijven los van uitslagen.

Nederlandse datum/tijd wordt expliciet omgerekend via Europe/Amsterdam en is onafhankelijk van de tijdzone van het apparaat. Niet-bestaande zomertijdmomenten en dubbele wintertijdmomenten worden geweigerd met een uitleg; er wordt geen stilzwijgende offset gekozen.

## Backend en sportimport verwijderen

Migratie: `supabase/migrations/20261016175608_manual_knockout.sql`, met de Supabase CLI gegenereerd. Twee nieuwe private tabellen met RLS, zonder directe browserrechten. Publieke functies gebruiken SECURITY INVOKER-wrappers; private implementaties hebben lege search_path en controleren auth.uid plus de actuele databasebeheerdersrol. Nieuwe triggers doen alleen werk voor wedstrijden in de nieuwe knock-outtabellen. Foreign-key- en doorstroomzoekvelden hebben indexes.

De migratie trekt browser- en service-role-uitvoering van begin/finish/review/list-darts-importfuncties in, zonder historische tabellen te verwijderen. Twee Edge Function-bronbestanden (`sync-darts-data` en `sync-darts-fixtures`) bevatten alleen een 410-antwoord, zonder bronverzoeken of secretgebruik. Bij deployment blijft gateway-JWT aan. Het importscherm en de actieve bronadapter zijn uit de code verwijderd. Oude importmigraties/verslagen blijven historie; oude importtests die die functies actief veronderstellen zijn verwijderd. Het historische SQL-testbestand voor reviewed imports is niet meer van toepassing na deze migratie.

## Verificatie

- `tests/knockout-db.cjs`: geïsoleerde PostgreSQL-engine PGlite 0.5.10, geen netwerk of hosted verbinding. Laadt een beperkte representatie van de bestaande tabellen plus de werkelijke bestaande publicatie-, uitslag- en voorspelprocedures en de drie bestaande beveiligingstriggers, daarna de volledige nieuwe migratie. Fixtures staan onder tests/fixtures. Dit is geen volledige kopie van alle hosted RLS-policies/constraints; een hosted rollbacktest blijft nodig na goedkeuring.
- `supabase/tests/manual_knockout.sql`: volledige transactie met rollback. Tests voor gewone gebruikers/anoniemen, private tabeltoegang, conceptafscherming, 2/3/5/8/16/48/64/128 deelnemers, n−1 echte wedstrijden, vrijstellingen, onbekende plekken, publiceren, echte klokdeadline zonder statusflip, geldige/ongeldige uitslag, doorstroming, beschermen bestaande vervolgvoorspellingen, scorecorrectie, uitstel en bewuste heropening. Voetbaltest houdt strafschopwinnaar los van de voorspelde gelijke score.
- `tests/knockout-ui.cjs`: mobiele Edge met mockbackend. Toernooiaanmaak, rondepunten, deelnemersaantal, volledig schema, ontsmette namen, filter voor uitslag nodig, behoud van invoer bij fouten, geen horizontale overloop, Nederlandse zomer/wintertijd en DST-grensgevallen. Mobiele screenshot gecontroleerd.
- Bestaande browserregressies voor toernooien, accountbeheer, poules, profiel, gebruikersnaaminlog en activatie/herstel slagen.
- Geen officiële wedstrijd of score gewijzigd. Geen backend-deployment uitgevoerd.

Lokaal uitvoeren:

```
npm install --prefix .local-test --save-exact @electric-sql/pglite@0.5.10
node tests/knockout-db.cjs
node tests/knockout-ui.cjs
```

Voor de browsertest moet Playwright beschikbaar zijn en Edge geïnstalleerd zijn. De lokale PGlite-installatie is genegeerd in Git; er worden geen sleutels in gebruikt.

## Status en ingebruikname

Automatische goedkeuringscontrole weigerde het toepassen van de live migratie omdat die nieuwe triggers/functies toevoegt en bestaande importtoegang intrekt. Dat kan de bestaande gepubliceerde importinterface direct raken. De poging is niet uitgevoerd en niet via een andere route herhaald. De ontwikkelcode en lokale tests zijn daarna zonder live wijzigingen afgerond.

Voor ingebruikname is expliciete toestemming nodig voor deze concrete migratie en de gecoördineerde vervanging van backend en frontend. Volgorde na toestemming: migratie toepassen; hosted integratietest met rollback en vergelijking van bestaande gegevens; security advisors; beide sportimport-Edge Functions met verify_jwt=true naar 410 deployen; frontend publiceren; publicatie controleren. Geen bestaande wedstrijden converteren, oude migraties opnieuw toepassen of bronsecrets verwijderen.

Nog geen garantie over multi-session races uit de lokale single-connection testengine; de normale nieuwe beheerroute serialiseert per toernooi en bestaande wedstrijdlocks blijven actief. Een geannuleerde partij krijgt geen automatische winnaar. Walk-overafhandeling of vervanging van een deelnemer nadat er voorspeld is, is geen impliciete scorecorrectie: daarvoor blijft aanvullende expliciete spelregelafhandeling nodig. Er is geen automatische import van een bestaand los wedstrijdschema naar een nieuwe bracket.
