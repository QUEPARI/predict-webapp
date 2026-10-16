# Predict – algemene sportvoorspelwebapp

**Status 16 oktober 2026:** JavaScript/HTML/CSS op GitHub Pages met Supabase-authenticatie, beheerdersfuncties, beveiligde voorspellingen, toernooi- en pouleklassementen, echte privépoules en online profielbeheer. De gebruikersschermen gebruiken Supabase. **Geen volledig afgeronde productie-app.**

## Profiel en voorkeuren
De mijlpaal voor [gebruikersnaam en wachtwoord zonder e-mail](docs/manual-accounts-milestone.md) is gepubliceerd via PR #4 (`aa45d6f`) en door de gebruiker getest. Deelnemers activeren hun account met een eenmalige code van een beheerder. Wachtwoordherstel gebruikt ook een beheerderscode. SMTP en een eigen domein zijn niet nodig.

## Handmatige knock-outtoernooien
- De ontwikkelrichting is handmatig beheer, zonder sport-API's, betaalde databronnen of automatische bronimports.
- Nieuwe knock-outtoernooien ondersteunen 2–128 spelers of teams, lotingsvolgorde, vrijstellingen, rondeformaten en expliciete puntentelling. Datums/tijden worden als Nederlandse tijd ingevoerd; sluiting blijft op de server bewaakt.
- Winnaars stromen na handmatige uitslagregistratie door. Het volledige schema is zichtbaar bij een geselecteerd toernooi. Beheer toont ontbrekende gegevens en wedstrijden die een uitslag nodig hebben.
- Zie [knock-outmijlpaal](docs/manual-knockout-milestone.md) voor verificatie en ingebruikname. Na expliciete toestemming is migratie `20261016181258` toegepast en zijn de hosted rollbacktests geslaagd. De frontend is via PR #7 gepubliceerd.
- Oude bronrecords en importmigraties blijven als historie behouden. De nieuwe code verwijdert het importscherm en vervangt de twee sportimportfuncties door HTTP 410-antwoorden. Dit is via PR #7 uitgerold.

## Lege schema’s en sjablonen
- Kies per sport een vrij knock-outformat of een bewaard eigen sjabloon. Sjablonen bewaren deelnemersaantal, spelers/teams, rondeformaten en punten; geen namen of tijden.
- Darts heeft een ingebouwd **European Tour**-sjabloon: 48 spelers, 16 direct geplaatst in ronde 2 tegenover de 16 winnaars uit ronde 1. Legs: first-to 6 in de eerste vier rondes, 7 in de halve finales en 8 in de finale. Punten blijven expliciet in te vullen.
- Maak eerst een leeg conceptschema. Vul namen op de zichtbare lotingsplekken in, ook de geplaatste spelers in ronde 2. Tussentijds opslaan met lege plekken kan; dubbele ingevulde namen worden geweigerd.
- Alle deelnemers moeten ingevuld zijn vóór publiceren. Ook de bestaande publicatieroute en wedstrijdbeveiliging weigeren onvolledige deelnemers. Datums en tijden blijven apart in te vullen.
- Zie [mijlpaal lege schema’s en sjablonen](docs/knockout-templates-milestone.md). Migratie `20261016183915` is na toestemming toegepast; de hosted rollbacktests slagen. De frontend is opgenomen in PR #8.

## Uitgebreid toernooibeheer en winnaarsvoorspelling
- Beheer heeft eigen navigatie. Toernooien kunnen worden bewerkt, gepauzeerd, hervat, veilig terug naar concept of definitief verwijderd met naambevestiging en impactoverzicht. Bestaande audits blijven bewaard.
- Via **Beheer → Toernooien** stel je de winnaarsvraag in met expliciete bonuspunten. De vraag sluit uiterlijk bij de eerste wedstrijd. De winnaarbonus telt mee in de totale toernooi- en pouleklassementen; bestaande wedstrijdpunten blijven gelijk.
- Naam, schema en punten wijzigen blijft aan de bestaande voorspellingen/gestarte wedstrijden gebonden. Verlopen deadlines worden niet automatisch heropend. Toernooien met een startdatum in het verleden kunnen als concept worden ingevoerd.
- Zie [beheerverbeteringen, testresultaten en verdere bevindingen](docs/tournament-management-milestone.md).

## Compacte schermen en poulegenoten vergelijken
- Toernooien hebben aparte tabbladen voor Voorspellingen, Uitslagen (beide per ronde), Schema, Toernooiwinnaar en Klassement. Gesloten kaarten tonen de opgeslagen voorspelling, uitslag en punten compact naast elkaar.
- Beheer toont compacte inklapbare wedstrijden, expliciete Open/Gesloten-labels, gekleurde acties en opslag-/foutmeldingen bij de betreffende kaart. Winnaars zijn lichtgroen gemarkeerd in het schema.
- Klik in een poule op een lid om diens voorspellingen naast je eigen voorspellingen en de uitslagen te bekijken. De server onthult alleen wedstrijden waarvan de individuele deadline is verstreken of de werkelijke start is bereikt; handmatig sluiten onthult niets.
- Zie [testresultaten en details](docs/compact-predictions-milestone.md).

## Compactere rondes en mobiel schema
- Toernooikaarten tonen hoeveel wedstrijden openstaan en hoeveel je nog moet voorspellen. Spelregels en puntentelling staan in een eigen toernooitab.
- Het mobiele hoofdmenu staat bovenaan. Wedstrijdkaarten, de toernooikop en score-invoer zijn compacter.
- Het volledige knock-outschema loopt horizontaal door, met verbindingen en scrollknoppen. Rondes worden niet onder elkaar afgebroken.
- Schemabeheer groepeert wedstrijden per ronde en sorteert daarbinnen op datum/tijd. Begintijd en first-to staan naast elkaar; spelvorm komt uit het vastgelegde format en wijzigingen krijgen automatisch een auditreden.
- Beheer toont standaard nog af te handelen wedstrijden, inclusief verstreken wedstrijden zonder uitslag. Afgeronde wedstrijden blijven bereikbaar via alle wedstrijden.
- Zie [mijlpaal compacte rondes](docs/compact-rounds-milestone.md), inclusief de toegepaste tellingmigratie `20261016210334` en verificatie.

## Wedstrijden per lokale speeldag
- Voorspellingen toont alle wedstrijden van de gekozen lokale dag en ronde, inclusief gesloten wedstrijden en uitslagen. Alleen open wedstrijden zijn bewerkbaar. Overbodige labels en knoppen zijn verwijderd; paginering verschijnt alleen als nodig en behoudt invoer.
- Resterende voorspellingen vallen op met een oranje label; een volledig ingevulde open lijst krijgt een groene bevestiging. De tab Toernooiwinnaar verschijnt alleen bij een ingestelde vraag.
- Deelnemers zien tijden in hun eigen apparaattijdzone. Beheer blijft Nederlandse tijden invoeren. Compacte mobiele beheerkaarten en een lager horizontaal schema verbeteren de leesbaarheid.
- Een open toekomstige knock-outwedstrijd blijft na een zuivere tijdcorrectie open als de nieuwe tijd ook toekomstig is. Verlopen of handmatig gesloten wedstrijden vereisen bewuste heropening; gewijzigde spelvorm sluit voorspellingen.
- Zie [mijlpaal lokale speeldagen](docs/daily-matches-milestone.md). Migratie `20261016215435` is toegepast en transactioneel getest.

## Eenvoudiger voorspellingen opslaan
- De terugknop Toernooioverzicht en de datumfilter zijn verwijderd. Voorspellingen en uitslagen kunnen per ronde over alle datums bekeken worden.
- De knop toont **Opgeslagen** zodra een voorspelling is opgeslagen, ook na opnieuw openen. Bij een wijziging wordt het weer **Opslaan**. Overbodige bevestigingsteksten onder de velden zijn verwijderd; fouten blijven zichtbaar.
- Zie [opslagstatus en rondeoverzicht](docs/prediction-save-status-milestone.md).

## Account en voorkeuren (vervolg)

- **Account** vervangt het navigatielabel Profiel. Gebruikersnaam, licht/donker/systeeminstelling en Uitloggen staan op deze pagina; de header bevat alleen de huisstijl.
- Gewijzigde frontendbestanden hebben een versieparameter voor verversen van de browsercache. De bestaande mobiele menuplaatsing is behouden.
- Zie [accountnavigatie en verificatie](docs/account-navigation-milestone.md).


- Het profiel toont je eigen gebruikersnaam, bewerkbare weergavenaam en thema: systeeminstelling, licht of donker.
- Weergavenaam (1–40 tekens) en thema worden via `update_my_profile` bij je account opgeslagen. Gebruikersnaam en rol kunnen hiermee niet worden gewijzigd.
- De themaknop bovenaan gebruikt dezelfde accountvoorkeur, zonder andere invoer te wissen. Systeeminstelling volgt wijzigingen in de apparaatvoorkeur.
- Mijn voorspellingen toont je eigen opgeslagen voorspellingen, uitslagen en serverberekende punten per toernooi, met 25 voorspellingen per pagina.
- De oude lokale demo-opslag wordt verwijderd. Alleen thema en navigatietab staan nog in een lokale UI-cache; accountnamen en echte voorspellingen niet. Supabase-sessies worden daarbij niet verwijderd.
- Migratie `20261016145640_own_profile_preferences.sql` is toegepast. Tests en grenzen staan in [de profielmijlpaal](docs/profile-milestone.md).

## Online toernooien en voorspellingen
- **Home** toont je werkelijke toernooideelnames; **Toernooien** toont het gepubliceerde aanbod uit Supabase.
- Je kunt deelnemen zonder poule. Deelname voegt alleen je eigen account toe en is herhaalbaar zonder dubbele records. Concepten en gesloten toernooien accepteren geen nieuwe deelname.
- Open een toernooi voor de werkelijke wedstrijden, je eigen voorspellingen en serverberekende punten. Alleen goedgekeurde, vrijgegeven wedstrijden met een bevestigde toekomstige individuele starttijd zijn bewerkbaar.
- Voorspellen en wijzigen verlopen via de bestaande `submit_match_prediction`-RPC. Darts gebruikt het vastgestelde sets-/legsformaat; voetbal staat gelijkspel toe en telt geen strafschoppen mee.
- Geen online voorspellingen in lokale opslag. Niet-opgeslagen invoer op andere wedstrijdkaarten blijft behouden na opslaan. Navigeren met niet-opgeslagen wijzigingen vraagt om bevestiging.
- Maximaal 50 wedstrijden per pagina. Ververs bewust voor tussentijdse beheerwijzigingen; de server bewaakt de deadline en rechten bij iedere opslag. Een open formulier wordt ook op de individuele deadline lokaal geblokkeerd.
- Migraties `20261016140215_tournament_self_entry.sql` en `20261016140415_restrict_tournament_entry_grants.sql` zijn toegepast. De tweede verwijdert overbodige directe browserrechten op deelnames; bestaande RLS en beheerdersfuncties blijven actief.
- Tests: `supabase/tests/tournament_entry.sql` (rollback) en `tests/tournaments-ui.cjs` (mockbackend). Zie [de testnotities](docs/online-predictions-milestone.md).

## Online privépoules
- Open **Mijn poules**, kies een gepubliceerd/actief toernooi en maak een poule aan. Je wordt automatisch toernooideelnemer en poulebeheerder.
- De beheerder maakt een uitnodigingscode voor een bestaande gebruikersnaam en deelt die zelf. Er wordt geen e-mail verzonden. De ontvanger moet met het bedoelde Predict-account ingelogd zijn. Bestaande e-mailgebonden uitnodigingscodes blijven werken.
- Codes zijn eenmalig, zeven dagen geldig en uitsluitend als SHA-256-hash opgeslagen. Een nieuwe code voor hetzelfde adres vervangt de oude. Alle openstaande codes kunnen worden ingetrokken.
- Leden kunnen vertrekken. De beheerder kan leden verwijderen of het beheer overdragen aan een bestaand lid. De eigenaar moet eerst overdragen voordat die vertrekt.
- Eén centrale voorspelling per wedstrijd telt in alle poules van dat toernooi, inclusief eerdere punten bij later toetreden. Verlaten/verwijderen wist de voorspellingen niet.
- Klassementen komen uit de bestaande beveiligde serverfunctie, met filters op poule en ronde. Systeembeheerders behouden hun bestaande leestoegang.

## Database en verificatie
De incrementele migratie `supabase/migrations/20261016133928_secure_private_pools.sql` is toegepast op project `sfcozzjcuppfypetbbzn`. RLS blijft actief; tabelmutaties en het lezen van uitnodigingsgegevens zijn geblokkeerd voor browserrollen. Publieke RPC's gebruiken invoker-rechten en roepen afgeschermde functies met expliciete identiteits- en eigendomscontroles aan.

**Let op:** `supabase/schema.sql` is het oorspronkelijke concept en wijkt af van de bestaande hosted database. Voer het niet uit op productie. De nieuwe migratie vereist die bestaande structuur; dit is nog geen volledige migratiegeschiedenis voor een lege installatie.

- `supabase/tests/private_pools.sql`: integratietest als databasebeheerder; fictieve gebruikers en wedstrijden uitsluitend binnen een transactie met rollback. Controleert RLS, uitnodigingen, ledenbeheer, historische punten, individuele deadline en 6–4 versus 6–3 = 1 punt.
- `tests/pools-ui.cjs`: Playwright-browsertest met mockbackend. Voer uit met `node tests/pools-ui.cjs` als Playwright en een browser beschikbaar zijn; stel eventueel `PLAYWRIGHT_CHANNEL=msedge` in.
- Volledige testresultaten, beperkingen en vervolgstappen: [privépoule-mijlpaal](docs/private-pools-milestone.md).

Onderstaande beschrijving documenteert de **oorspronkelijke lokale demo**. De online functies hierboven vervangen de betreffende demostromen.

## Oorspronkelijke demo: beschikbare functies
- Responsieve interface, licht/donker thema, platform- en toernooioverzicht.
- Dart- en voetbalwedstrijdkaarten met scorevalidatie.
- Voorspellingen lokaal opslaan met `localStorage` (alleen op dit apparaat).
- Definitieve WK Darts 2027-puntentabel zichtbaar (1/3, 2/5, 3/7, 4/10, 6/15, 10/25, 15/40).
- Demo-extra-voorspellingen voor voetbal.
- Demo-privépoules en eigen overzicht.
- Conceptueel Supabase PostgreSQL-schema met standaard afgeschermde tabellen.

## Oorspronkelijke demo: beperkingen bij oplevering
- Geen echte accounts, uitnodigingen of meerdere gebruikers. De gegevens staan uitsluitend lokaal op het apparaat.
- Geen echte darts- of voetbalwedstrijden; alle voorbeeldwedstrijden zijn fictief.
- Geen DartsAPI/TheSportsDB-synchronisatie, echte scoring/klassementen, realtime startdetectie, auditverwerking of pushnotificaties.
- Geen productierijpe RLS-regels, database-RPC's en Edge Functions: het SQL-schema is een **basis**, en mag niet als volledige backend worden beschouwd.
- Aan de demo toegevoegde poules hebben nog geen lidmaatschapsbeheer of uitnodigingen.

## Lokaal bekijken
Open `index.html` in een browser. Als browserbeperkingen module-import vanuit `file://` verhinderen, start een statische server:

```sh
python3 -m http.server 8080
```

Open daarna `http://localhost:8080`. Er is geen npm-installatie vereist.

## GitHub Pages
Upload de bestanden naar een GitHub-repository en stel **Settings → Pages → Deploy from a branch → main / (root)** in. De statische demonstratie werkt onder een projectsubpad. Zet dit pas openbaar als je akkoord bent met een **demo zonder echte accounts**.

## Technische koers voor de volledige app
- Platform: React + TypeScript (in de productiefase), GitHub Pages, Supabase Auth + PostgreSQL + Edge Functions.
- Authenticatie alleen via uitnodigingen van zeven dagen.
- Sportonafhankelijke toernooien; privépoules zijn altijd gekoppeld aan één toernooi.
- Scoreverwerking via versiegebonden regels; API-uitkomsten eerst matchen, valideren en bij conflicten blokkeren.
- Darts: fixtures via DartsAPI, resultaten via `results/yesterday` en noodcorrecties.
- Voetbal: TheSportsDB nader valideren, daarna adapter integreren.
- Server-side bewaakte deadlines; geheimen uitsluitend als backend secrets.
- WK Darts 2027 blijft volgens de vastgelegde puntentabel en walk-over-/tiebreakregels werken.

## Bestanden
- `index.html`, `styles.css`, `app.js`: zelfstandig werkende browserdemo.
- `manifest.webmanifest`: basis-PWA-metadata, nog geen pushimplementatie.
- `supabase/schema.sql`: databasebasis. Niet productierijp zonder aanvullende RLS, procedures en tests.
- `docs/roadmap.md`: volledige vervolgbouw en afvinkcriteria.

**Geen API-sleutels, service_role keys of wachtwoorden in GitHub plaatsen.**
