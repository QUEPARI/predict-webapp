# Predict – algemene sportvoorspelwebapp

**Status 16 oktober 2026:** JavaScript/HTML/CSS op GitHub Pages met Supabase-authenticatie, beheerdersfuncties, beveiligde voorspellingen, toernooi- en pouleklassementen, echte privépoules en online profielbeheer. De gebruikersschermen gebruiken Supabase. **Geen volledig afgeronde productie-app.**

## Introductie en automatisch opslaan — 19 oktober 2026
- Mijn spellen sorteert op begindatum van nieuw naar oud. Onbekende wedstrijdtijden heten overal NNB, ook in schema en beheer; voorspellingskaarten tonen geen wedstrijdstatuslabels.
- Niet-deelnemers zien een introductie met toernooiafbeelding, periode, aftelling tot de toernooistart, uitleg en Speel mee. De aftelling is geen nieuwe aanmelddeadline; de bestaande deelnamecontrole blijft gelden.
- Geldige scoreparen slaan automatisch op na een invoerpauze van 650 ms of bij verlaten van een invoerveld. Opslag per wedstrijd is geserialiseerd, recentere invoer wordt niet overschreven, fouten behouden de invoer en bieden Opnieuw proberen. De bestaande serverdeadline en scorevalidatie blijven gelden.
- Afgelopen toernooien openen op Uitslagen en tonen geen tab Voorspellingen. De zeven dagen op het hoofdscherm en het spelarchief blijven behouden.

## Mobiel, NNB en spelarchief — 19 oktober 2026
- Nieuw toernooi toont geen bestaande-toernooikeuze. De dubbele uitslagenkop en het label Gepubliceerd op beschikbare spelkaarten zijn verwijderd; de footer is gecentreerd.
- Uitslagen passen op mobiel zonder horizontaal scrollen. De vergelijkingskolommen blijven bovenaan hun scrollvlak staan.
- Afgeronde spellen met alle uitslagen tonen Toernooi afgelopen. Via Archiveren in beheer verdwijnen ze uit het actieve beheeroverzicht; spelers houden hun bestaande zeven dagen op het hoofdscherm en kunnen daarna via Spelarchief terugkijken. Alle gegevens blijven behouden; beheerarchivering is omkeerbaar.

## Automatisch beheer vergrendeld — 19 oktober 2026
- Mastercaller-toernooien tonen schema, deelnemers, planning en uitslagen alleen-lezen. Ook de oudere wedstrijdacties en API-routes worden op de server geblokkeerd. Naam, afbeelding en pauzeren/hervatten blijven beschikbaar; de bron van automatisch aangemaakte toernooien staat vast.
- Zodra de finale-eindstand bekend is, stopt zowel automatisch als handmatig ophalen, ook als er elders nog een uitslag ontbreekt.
- De eindgrens van een Mastercaller-toernooi staat op 00:00 Nederlandse tijd op de **volgende** dag. Voor European Championship 2026 is dat 26 oktober 00:00; de volledige speeldag 25 oktober valt binnen de periode.

## Mastercaller (test) — 19 oktober 2026
- Bij **Nieuw toernooi → Uitslagen** kies je **Handmatige invoer** of **Scores ophalen via Mastercaller (test)**.
- In testmodus vul je de Mastercaller-uitslagenlink in. Het schema, spelers, rondeformats en beschikbare planning worden uit de uitslagen- en bracket-tab opgebouwd; er is geen handmatige goedkeuringswachtrij. Complete knock-outs met 2/4/8/16/32/64/128 spelers zijn ondersteund. Andere formats worden afgewezen zonder een gedeeltelijk toernooi te maken.
- Punten starten op 1 voor de winnaar en 3 voor de exacte eindstand; dit kun je vóór aanmaken aanpassen. Het aangemaakte toernooi wordt gepubliceerd. NNB-tijden blijven leeg. Met bekende spelers kun je alvast voorspellen tot de toernooistart; zodra een individuele tijd bekend is geldt die deadline. Verstreken bekende deadlines blijven gesloten.
- Achtergrondcontrole vóór de start elke 4 uur; bij begonnen/geplande wedstrijden zonder eindstand elke 15 minuten. Bij TBA geldt vanaf de eerste toernooidag de 15-minutenfallback. Na alle eindstanden stopt het ophalen.
- De specifieke European Championship 2026-pagina bevat 32 spelers en 31 schemaposities. **De serververbinding met Mastercaller wordt momenteel geweigerd (HTTP 418).** Aanmaken uit de bron mislukt daarom met een duidelijke melding; de live proef is nog niet geslaagd. Geen toegangsbescherming omzeild.
- Bronparsing, authenticatie, automatische schema-inrichting, scoreverwerking, doorplaatsing, puntentelling, intervallen en mobiele formulieren zijn lokaal getest. Historische handmatige toernooien behouden hun bestaande invoerwijze.
- Details: [Mastercaller-integratie](supabase/functions/sync-mastercaller/README.md).

## Kleur alleen op voorspelde scores
- Wedstrijdkaarten gebruiken de normale lichte/donkere paneelachtergrond. Alleen de voorspelde score is blauw (open), grijs (uitslag ontbreekt), donkergroen (exact), lichtgroen (winnaar goed) of rood (onjuist).
- Dezelfde scorekleurvlakken staan in de wedstrijdpop-up en in de kolom Jouw voorspelling bij Uitslagen. Niet ingevulde voorspellingen blijven neutraal.
- Afgerond en Gesloten verdwijnen uit de wedstrijdkaart. De scorevelden staan als groep exact in het kaartmidden; de opslagknop staat er rechts naast (op smalle schermen eronder). Punten staan gecentreerd in de linker twee derde van de kaart.

## Rustige wedstrijdkaarten
- Open kaarten zijn blauw. Spelers staan links/rechts met de uitslag centraal; jouw voorspelling en punten staan er compact onder. Gesloten kaarten behouden de uitkomstkleur.
- De teksten Exact goed en Vergelijk poule zijn uit de kaart verwijderd. De hele gesloten kaart opent de bestaande pop-up, ook via toetsenbord (Enter/spatie). Het uitkomstlabel staat in de pop-up.
- Uitslagen tonen achter de ronde de wedstrijddatum in de tijdzone van de speler.

## Gesloten wedstrijden en poulepop-up
- Gesloten wedstrijdkaarten openen een pop-up met voorspellingen en punten van de eigen poule. Een eigen beheerde poule staat bovenaan; anders wordt de eerste eigen deelname gekozen. Wisselen kan via de dropdown. Alleen eigen poules van hetzelfde toernooi zijn beschikbaar.
- De database controleert het actuele lidmaatschap van de kijker en de geselecteerde poule. Een handmatig gesloten toekomstige wedstrijd onthult niets; vergelijking opent pas na de deadline of werkelijke start. Leden staan met maximaal 10 per pagina in de pop-up.
- Gesloten kaarten zijn donkergroen bij exact goed, lichtgroen bij juiste winnaar, rood bij onjuist en grijs zonder uitslag. Niet ingevulde voorspellingen blijven neutraal. Tekstlabels ondersteunen de kleuren in lichte/donkere modus.
- Migratie `20261017131319_match_pool_popup.sql`; rollbacktest `supabase/tests/match_pool_popup.sql`. Geen bestaande voorspellingen of uitslagen worden gewijzigd.

## Naamcorrecties, klassementpagina’s en compact beheer
- Deelnemersnamen kunnen ook na voorspellingen of gestarte wedstrijden worden gecorrigeerd. Schemaplekken, scores, deadlines en wedstrijdvoorspellingen blijven identiek; winnaarskeuzes volgen de naamcorrectie op dezelfde schemaplek. Namen blijven uniek en bestaande actieve deelnemers kunnen niet worden leeggemaakt.
- Toernooi- en pouleklassementen tonen maximaal 10 spelers per pagina, ook in beheer. Namen openen een vergelijking. Het nieuwe toernooi-RPC controleert deelname en toont uitsluitend wedstrijden waarvan de deadline verstreken is of die werkelijk gestart zijn; een handmatig gesloten toekomstige wedstrijd blijft verborgen.
- Uitslaginvoer is compact, zonder dubbele namen of grote witruimten. Afbeelding opslaan gebruikt de gewone primaire knop; verwijderen is rood.
- Het spelbeheermenu blijft onder het algemene beheermenu staan bij scrollen. Dubbele toernooinaam, status, Schema vernieuwen en de uitlegtekst verdwijnen uit het schemascherm. Punten worden uitsluitend onder Schema ingesteld (na publicatie vergrendeld).
- Migratie `20261017125312_roster_corrections_and_tournament_comparison.sql`; rollbacktest `supabase/tests/roster_and_tournament_comparison.sql`.

## Herstelacties en compacte beheerformulieren
- **Schema → Wedstrijden** biedt Uitstel ongedaan maken (ook na de deadline) en Uitslag ongedaan maken. Voorspellen blijft gesloten totdat de beheerder bewust heropent met een toekomstige begintijd.
- Uitslagherstel trekt de doorgeplaatste winnaar terug en herberekent punten, zonder voorspellingen te verwijderen. Bij voorspellingen of start in de vervolgwedstrijd wordt de hele herstelactie geblokkeerd. Auditlogging blijft behouden.
- Wijzigingsredenen worden automatisch op de server vastgelegd; beheerders hoeven nergens meer een reden in te vullen.
- Statusfilter start op Nog af te handelen; het nieuwe rondefilter op Alle rondes. Het schema biedt compacte neutrale tijd/statusacties zonder score- of first-to-invoer. Uitslagen kunnen per wedstrijd rechtstreeks bij Uitslagen nodig worden ingevuld.
- Spelnaam en tabs staan in alle beheerschermen boven de inhoudsbox. Uitklapbalken gebruiken de accentachtergrond en de drie headercirkels hebben dezelfde rand, achtergrond en afmetingen.
- Alleen eigen sjablonen zijn beschikbaar. De ingebouwde European Tour-optie is verwijderd; eigen sjablonen en bestaande spellen blijven behouden. Bewerken, Verwijderen en Kopie maken zijn even groot.
- Migratie `20261017121505_match_recovery_and_admin_forms.sql`; rollbacktests in `supabase/tests/match_recovery.sql`.

## Compact spelbeheer en archivering
- Beheer → **Spellen** sorteert op begindatum, net als Mijn spellen. Gearchiveerde spellen blijven in het uitklapbare beheerarchief beschikbaar.
- Spellen worden automatisch 7 dagen (168 uur) na hun eindtijd gearchiveerd. De database controleert dit iedere 5 minuten; ontbrekende einddatums en concepten worden overgeslagen. Uitslagen, voorspellingen en poules blijven bewaard.
- Elk spel heeft dezelfde tabs **Algemeen, Schema, Wedstrijden, Klassement**. Het algemene beheermenu bevat geen Klassementen meer.
- Benodigde uitslagen staan direct bij het openen van een spel. Instellingen en schemaonderdelen zijn duidelijk inklapbaar; het extra volledige beheerschema is verwijderd.
- Eigen sjablonen kunnen na bevestiging worden verwijderd zonder bestaande spellen te wijzigen.
- Migratie: `20261017113827_compact_game_management.sql`; verificatie: `supabase/tests/compact_game_management.sql` en lokale browsertests.

## Vooraankondigingen en sjabloonbeheer
- Concepten kunnen met een van- en tot-datum als **Vooraankondiging** op Beschikbare spellen verschijnen. Deelname, poules en voorspellingen openen pas na publicatie. Spelers zien het datumbereik zonder tijden; wedstrijden behouden hun tijden.
- **Beheer → Sjablonen** toont eigen formats. Eigen sjablonen kunnen worden aangemaakt en gewijzigd. Bestaande toernooien wijzigen niet mee.
- Spelvorm staat één keer per toernooi/sjabloon. First-to en punten staan per ronde in een compacte tabel. Eventuele bestaande gemengde toernooiformats worden behouden zolang je geen nieuwe centrale spelvorm kiest.
- Schema en Wedstrijden zijn alleen bereikbaar via het geselecteerde toernooi in Beheer → Toernooien. De wedstrijdacties zijn inklapbaar.
- Het logo is een Home-knop, Mijn spellen/Beschikbare spellen hebben dezelfde kopgrootte en spelersnamen staan gecentreerd boven scorevelden.
- Zie [verificatie en migratie](docs/previews-and-templates-milestone.md).

## Concept alvast aanmaken
- **Beheer → Toernooien → Nieuw toernooi** opent direct het aanmaakformulier.
- Startdatum, first-to en punten mogen leeg blijven bij het aanmaken van een knock-outconcept. Lege punten blijven onbekend en worden niet als nul opgeslagen.
- In **Schema’s → Ronde-instellingen en punten** kun je instellingen tussentijds opslaan en later aanvullen. Een overzicht toont wat nog nodig is voor publicatie.
- Publiceren vereist complete deelnemersnamen, startdatum en ronde-instellingen. De server bewaakt dit bij alle publicatieroutes; bestaande gepubliceerde spellen houden hun vergrendelingen.
- Zie [verificatie en migratie](docs/incomplete-drafts-milestone.md).

## Compacte header en schermindeling
- Het woordlogo staat gecentreerd, zonder los P-icoon. Links staat Home; rechts staan de kleinere account- en beheericonen. De visuele cirkels zijn 33 px, met behoud van 44 px klikruimte.
- Mijn spellen toont naam, afbeelding en voorspelstatus; deelname-/publicatietekst en startdatum zijn daar verwijderd. Binnen het toernooi blijven de punten zichtbaar en zijn de dubbele deelnamelabels weg.
- De toernooinaam staat iets lager. De voettekst staat onderaan korte schermen en volgt de inhoud op langere pagina’s.
- Zie [verificatie](docs/compact-header-milestone.md).

## Spellen, uitsnijden en pouleklassementen
- **PREDICT.** als logo; de startpagina toont **Mijn spellen** en **Beschikbare spellen**, met extra ruimte boven de eerste sectie.
- Afbeeldingen zijn vierkant uit te snijden: verschuiven, zoomen en een direct voorbeeld. Opslag als JPEG werkt ook zonder WebP-codering in Safari. Bestaande afbeeldingen blijven zichtbaar.
- Beheer → Toernooien toont spelkaarten met openstaande beheeracties. Open een kaart voor de bestaande beheerfuncties.
- Klassement binnen een toernooi bevat het algemene klassement en uitklapbare klassementen van je eigen poules. Namen in een poule zijn aanklikbaar voor de bestaande beveiligde vergelijking.
- Zie [verificatie en migratie](docs/game-management-crop-milestone.md).

## Toernooikaarten en afbeeldingen
- Compacte kaarten met toernooiafbeelding, naam en voorspelstatus op de startpagina. Donkere modus gebruikt een neutrale zwarte/anthraciete basis.
- Beheer → Toernooien: kies een toernooi en upload/verwijder de openbare afbeelding. JPG, PNG en WebP worden verkleind naar WebP; alleen beheerders mogen bestanden wijzigen.
- Zie [verificatie](docs/tournament-images-milestone.md).

## Nieuwe startpagina en navigatie
- Na inloggen verschijnt Mijn toernooien, met daaronder Open toernooien waaraan je nog kunt deelnemen. Toernooien worden niet dubbel getoond; na deelname staan ze onder Mijn toernooien.
- Het Predict-logo brengt je naar deze startpagina. Rechts staan een ronde Account-knop met je gebruikersinitiaal en, alleen voor beheerders, een tandwiel voor Beheer. Het gewone hoofdmenu is verwijderd.
- Privépoules staan in de tab Poules van het betreffende toernooi. Aanmaken, uitnodigingen, ledenbeheer, vergelijken en klassementen blijven via de bestaande beveiligde functies werken.
- Schema-kaarten volgen hun inhoud, met het winnaarsvinkje bij de naam en scores rechts onder elkaar.
- Zie [startpagina, header en toernooipoules](docs/tournament-hub-milestone.md).

## Accentkleur voor de hele app
- Via **Beheer → Instellingen** kunnen beheerders de accentkleur kiezen met een kleurkiezer of kleurcode. Voorbeelden tonen de lichte en donkere weergave. De standaardkleur is met één knop te herstellen.
- De keuze wordt centraal opgeslagen en bij het openen van de app opgehaald, ook op het inlogscherm. Kleurtinten en tekstcontrast worden automatisch aangepast voor leesbaarheid. Statuskleuren voor bijvoorbeeld winnaars/fouten behouden hun betekenis.
- Alleen beheerders kunnen wijzigen; kleurwijzigingen worden gelogd. De openbare uitleesfunctie toont uitsluitend de kleur.
- Zie [accentkleur en beveiligingscontrole](docs/app-accent-milestone.md). Migratie `20261017081215` is toegepast.

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

## Vandaag en open wedstrijden
- Voorspellingen toont alle wedstrijden van vandaag in de lokale tijdzone, plus toekomstige wedstrijden die openstaan om te voorspellen. Oudere gesloten wedstrijden blijven onder Uitslagen. De rondekeuze blijft beschikbaar; er is geen datumfilter.
- Bij lokale middernacht en bij een verlopen deadline wordt de selectie opnieuw bepaald, met bijpassende paginering.
- Klassement is uit het hoofdmenu verwijderd en blijft binnen het toernooi bereikbaar. Hoofdmenu en beheermenu gebruiken even grote compacte knoppen; op smalle schermen lopen de knoppen door op een volgende regel.
- Zie [vandaagselectie en menucontrole](docs/today-and-navigation-milestone.md).

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

## Mastercaller via GitHub Actions — 19 oktober 2026
- De bron blokkeert ophalen vanuit Supabase soms met HTTP 418. Een echte GitHub-run heeft beide pagina's met HTTP 200 opgehaald en 32 spelers/31 wedstrijden gevalideerd. Ophalen gebeurt daarom via `.github/workflows/mastercaller-sync.yml`.
- De worker draait iedere vijf minuten en vraagt alleen taken op die volgens de bestaande regels aan de beurt zijn: vóór de start iedere vier uur, bij begonnen wedstrijden iedere vijftien minuten, geen taken na een finale-eindstand. Handmatig ophalen zet een verzoek in dezelfde wachtrij. GitHub-planning kan vertraging oplopen.
- Bij een nieuw toernooi wordt een recent gecontroleerd schema direct gebruikt. Anders staat de aanvraag in een bewaakte wachtrij en volgt de pagina de voortgang. De aanvraag blijft op de achtergrond bestaan als je de pagina sluit. Dubbele nog lopende aanvragen met dezelfde invoer worden samengevoegd.
- Een kortlevend, ondertekend GitHub OIDC-token wordt gecontroleerd op issuer/audience, repository- en eigenaar-ID, main-ref, exact workflowpad, event en runner. Er staan geen Supabase-beheersleutels of workergeheimen in GitHub. Wachtrijen en cache staan in het private schema; alleen beheerders mogen aanvragen indienen en alleen de oorspronkelijke aanvrager mag de voortgang lezen.
- De oude Supabase-ophaalcron is uitgeschakeld. De parser, bronvalidatie, puntentelling, deadlines, readonlybescherming en stoppen na de finale blijven behouden.
