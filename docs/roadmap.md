# Volledige productbouw – voortgang en acceptatie

## Actuele scope vanaf 16 oktober 2026

Handmatige knock-outtoernooien krijgen voorrang. Geen sport-API's, groepsfase of competitieontwikkeling. De implementatie op de ontwikkelbranch bevat toernooiaanmaak, 2–128 spelers/teams, vrijstellingen, schema, handmatige tijden/uitslagen, automatische individuele deadlines en winnaar-doorstroming. De live migratie en publicatie wachten op expliciete goedkeuring na een automatische blokkade. Zie `manual-knockout-milestone.md` voor tests en ingebruikname.

Onderstaande oorspronkelijke algemene roadmap is historische context; de API- en andere toernooivormen zijn geen actieve ontwikkelopdracht meer.

De doelomvang is de volledige algemene voorspelapp; er is bewust geen aparte MVP-scope.

## 1. Basis en veiligheid [gestart]
- [x] Offline responsive UI en sportonafhankelijke tabellen als beginpunt
- [ ] React/TypeScript app initialiseren zodra npm/dependencies beschikbaar zijn
- [ ] Supabase-project, migrations, seeding en schema-consistentie
- [x] Invite-only Auth met gehashte eenmalige codes en handmatig wachtwoordherstel; e-mail voorlopig overgeslagen
- [ ] RLS-policies en beveiligde RPC's voor alle schrijfhandelingen
- [ ] Meerdere systeembeheerders, beheerdersaudit en rechtentests

## 2. Toernooi, poules en voorspellingen
- [ ] Adminbeheer voor sporten, competities, edities, fasen en deelnemers
- [ ] Deelname zonder poule; één voorspelling telt in iedere poule van dat toernooi
- [ ] Pouleaanmaak, uitnodigen, verwijderen, eigendomsoverdracht en accountverwijdering
- [ ] Wedstrijdvoorspelling als transactionele serverfunctie met UTC-deadlinebewaking
- [ ] Ongeldigverklaring voorspellingen bij deelnemersvervanging
- [ ] Extra antwoorden met uniciteit, max-aantal en gelijktijdige deadline
- [ ] Afgeschermde voorspellingen tot deadline, ook op databaseniveau

## 3. Scoring en uitslagen
- [ ] Regel-engine: darts sets/legs, voetbal eindscore exclusief strafschoppen
- [ ] WK Darts 2027-definitieve regels; geen punten voor walk-overs
- [ ] Configureerbare toernooipuntenschema's, vergrendeling en auditcorrecties
- [ ] Gedeelde officiële winnaars en punten per correct antwoord
- [ ] Reproduceerbare klassementen per toernooi, poule en ronde
- [ ] Tiebreakers: punten, correcte winnaars, exact, dan gedeeld

## 4. Gegevensbronnen
- [x] DartsAPI-fixtures ophalen met paginering en rate-budget; handmatige controle vóór vrijgave
- [x] DartsAPI-gisterenresultaten ophalen met controlewachtrij en expliciete beoordeling; geen automatische conflictcorrectie
- [ ] TheSportsDB voor voetbal testen (recorddekking en latency)
- [ ] Adaptieve sync en server-side cron; idempotente verwerking
- [ ] Handmatige voorlopige uitslag + latere API-verificatie, conflictreview
- [ ] Bij uitstel veilig heropenen alleen bij bevestigde niet-start

## 5. PWA, privacy en kwaliteit
- [ ] Werkende installable PWA met iconen en service worker
- [ ] Web Push: 2 uur voor sessie en maximaal één keer, ontbrekende voorspellingen
- [ ] Privacy, accountverwijdering, backups en wettelijke bewaarplichten
- [ ] Integratie-, deadline-, autorisatie- en regressietests
- [ ] CI voor GitHub Pages + staging/production deploy
