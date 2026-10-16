# Beheer, toernooilevenscyclus en winnaarsvoorspelling

## Opgeleverde verbeteringen

1. Beheer heeft eigen navigatie voor Toernooien, Schema’s, Wedstrijden, Accounts, Klassementen en Testomgeving. Eén onderdeel tegelijk zichtbaar; wisselen bewaart formulierinvoer. De technische QA-bediening staat apart.
2. De eerdere publicatietabel is vervangen door toernooibeheer met status in het Nederlands, aantallen, naam/start bewerken, rondepunten en directe koppeling naar het bijbehorende knock-outschema of bestaand wedstrijdbeheer.
3. Een gepubliceerde wedstrijdopzet kan worden gewijzigd zolang er geen voorspellingen of gestarte wedstrijden zijn. Een ingestelde winnaarsvraag vergrendelt de deelnemerslijst; zonder voorspellingen kan de beheerder die vraag eerst wissen. Namen wijzigen sluit de wedstrijden en opent niets impliciet opnieuw.
4. Gepubliceerde toernooien kunnen pauzeren, hervatten of terug naar concept. Pauzeren sluit alle wedstrijden. Hervatten reset geen wedstrijdstatus of verlopen deadline; toekomstige wedstrijden worden bewust vrijgegeven. Terug naar concept en rondepunten wijzigen zijn geblokkeerd zodra voorspellingen of gespeelde/gestarte wedstrijden bestaan. Een concept kan niet via pauzeren/hervatten de publicatiecontroles omzeilen.
5. Definitief verwijderen toont aantallen en vereist de exacte naam en een reden. De server controleert de aantallen opnieuw onder locks. Verwijderd worden uitsluitend het geselecteerde toernooi en zijn wedstrijden, deelnames, voorspellingen, poules/leden/uitnodigingen en bijbehorende importkoppelingen. Gedeelde competities en sjablonen blijven bestaan. Er worden tijdens uitrol geen bestaande toernooien verwijderd.
6. Alle bestaande auditregistraties blijven ongewijzigd en beschermd. Alleen de foreign keys van wedstrijd- en score-audits naar verwijderbare objecten vervallen; originele UUID’s en inhoud blijven behouden. Een nieuw privaat, onveranderbaar auditlog bewaart reden, actor, toernooinaam en verwijderaantallen. Het bestaande voorspellingenlog registreert verwijderde wedstrijdvoorspellingen.
7. Toernooiwinnaar voorspellen is instelbaar met expliciete bonuspunten, vaste deelnemers en deadline uiterlijk bij de toernooistart/eerste wedstrijd. Alleen deelnemers kunnen hun eigen keuze opslaan. De server controleert bij iedere opslag opnieuw de status, deadline en gestarte wedstrijden. Een vroegere start verkort de opgeslagen deadline; een latere correctie opent hem nooit opnieuw. Instellingen staan vast zodra iemand voorspelt.
8. Bij knock-outtoernooien volgt de werkelijke winnaar automatisch uit de finale. Een finale-correctie herberekent de bonus in toernooi- en pouleklassementen. Bij oude losse wedstrijdtoernooien kan de beheerder na de deadline een winnaar uit de vaste lijst vastleggen. Rondeklassementen behouden uitsluitend wedstrijdpunten; de totale klassementen tellen de winnaarbonus erbij. De bestaande wedstrijdpunten en tiebreaks zijn ongewijzigd.
9. Een toernooi kan nu ook met een startdatum in het verleden als concept worden aangemaakt. Dat opent geen verstreken wedstrijd- of winnaar-deadlines.
10. Formulierfouten bewaren invoer, beheerverversing overschrijft geen openstaande wijzigingen, gevaarlijke acties staan apart, en de onderste mobiele navigatie is horizontaal veegbaar zodat alle knoppen bereikbaar zijn. Mobiel licht en desktop donker visueel gecontroleerd.

## Beveiliging en grenzen

Nieuwe gegevens staan in private tabellen met RLS en zonder directe browserrechten. Publieke RPC’s zijn invoker-wrappers; private functies controleren auth.uid en de echte beheerdersrol. Beheeracties vergrendelen het toernooi en de wedstrijden; winnaarsopslag gebruikt dezelfde lockvolgorde. De bestaande puntenlocks zijn niet algemeen versoepeld: alleen een door de beheerfunctie aangelegde private toestemming binnen dezelfde transactie laat expliciete puntcorrectie/verwijdering toe. Browserrollen kunnen deze toestemming niet schrijven. Audittriggers blijven actief.

Verwijderen is definitief en verwijdert bewust ook de bijbehorende gebruikersvoorspellingen en poules. Daarom wordt de hele impact vóór bevestigen getoond en opnieuw gecontroleerd. Dit is een mogelijkheid voor de beheerder, geen bulkopschoning bij uitrol. Bestaande sportgegevens worden niet automatisch geconverteerd of verwijderd.

Geen groepsfase, automatische API/import, betaalde bron of impliciete walk-over. Bestaande toernooien zonder knock-outnodes krijgen geen verzonnen bracket. Hun bestaande wedstrijdbeheer blijft beschikbaar. Een gepubliceerde deelnemersidentiteit met voorspellingen kan niet worden vervangen; deadlines mogen niet met terugwerkende kracht worden heropend. Puntentelling wijzigen bij gespeelde gegevens vereist een afzonderlijk ontworpen correctieproces en is hier geblokkeerd.

## Verificatie

- `tests/knockout-db.cjs`: PGlite met de oorspronkelijke databasefuncties/guards, eerdere knockout/sjabloon-suites plus `supabase/tests/tournament_management.sql`. Controleert rollen, gepubliceerde naamsopslag, punten/concept, start in verleden, pause/resume, deadline zonder heropening, winnaarbonus in toernooi/poule, finale-correctie, getypte verwijderbevestiging, afhankelijke verwijdering en behouden audit/andere toernooien. Alles fictief met rollback.
- `tests/management-ui.cjs`: echte app-routes met mockdatabase op 390px mobiel, beheernavigatie, schema-link, metadata/foutbehoud, winnaarsvraag instellen, getypte verwijdering, winnaar opslaan, HTML-escaping en deadline-timer.
- Bestaande knockout-, accountbeheer-, toernooi-, poule-, profiel-, gebruikersnaam- en activatie/herstel-browsertests blijven onderdeel van de regressiecontrole.
- Geen garantie van een uitgebreide multi-session stresstest uit de lokale single-connection database-engine. De database gebruikt wel expliciete row locks en alle tijdscontroles vinden op de server plaats.

## Overige bevindingen voor een volgende versie

- Wedstrijdkaarten in beheer inklapbaar maken en op ronde filteren; bij 48 spelers zijn het veel kaarten.
- Meerdere wedstrijdtijden achter elkaar kunnen invullen vanuit een compact sessieoverzicht.
- Het schema op grote schermen verder als verbonden bracket tekenen, met zoomen/rondekeuze op mobiel.
- Een afzonderlijk correctieproces voor deelnemersvervanging of gewijzigde punten mét bestaande voorspellingen, inclusief vooraf zichtbare gevolgen.

## Publicatie

Gebruiker heeft ontwikkeling, controle en publicatie expliciet toegestaan. Migratie en frontend worden na geslaagde tests samen uitgerold. Er wordt geen bestaand toernooi geselecteerd voor verwijdering tijdens deze uitrol.

Migratie `20261016192203_tournament_management.sql` is na toestemming toegepast. De hosted beheer-, knockout- en sjabloon-SQL-suites slagen met rollback. Vóór en na: 4 toernooien, 81 wedstrijden, 2 voorspellingen, 2 deelnames, 0 poules, 27 wedstrijdaudits, 4 score-audits en 3 voorspelaudits. Matchfingerprint `06e8a758b67ee95c9b983b09aeb7ed40` blijft gelijk. Er blijven geen testgebruikers, beheeraudits, toestemmingrijen of winnaarsvoorspellingen uit tests achter. Anonieme beheer-RPC-toegang en directe browsertoegang tot winnaarsvoorspellingen zijn geweigerd.

Security advisors: vier extra informatieve [RLS-zonder-policy-meldingen](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) zijn voor de bewust private tabellen (totaal 17). De bestaande [publieke definer-meldingen](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) dalen van 17 naar 16 doordat de klassementfunctie nu een invoker-wrapper is. De bestaande melding over [gelekte-wachtwoordbescherming](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) is ongewijzigd.
