# Compacte rondes, mobiel schema en open voorspellingen

16 oktober 2026, vervolg op de compacte voorspellingenmijlpaal.

## Gedrag

- Home en toernooioverzicht tonen het aantal daadwerkelijk open wedstrijden. Bij deelname ook hoeveel daarvan nog geen eigen voorspelling hebben. De telling omvat het hele toernooi, onafhankelijk van paginering, en vernieuwt bij de eerstvolgende deadline. Bij een verbindingsfout verschijnt geen misleidende nul.
- Spelregels en rondepunten staan in **Spelregels & puntentelling**, naast Klassement. Kaarten tonen spelers links, deadline/status rechts en invoer met opslagknop naast elkaar.
- Het mobiele hoofdmenu staat onder de compacte kop, boven de inhoud. Het menu blijft horizontaal bereikbaar.
- Het schema houdt alle rondes in één horizontale rij. Wedstrijden staan in een trechter met verbindingen; scrollknoppen en vegen ondersteunen navigatie. Euro Tour-vrijstellingen zijn verborgen, de geplaatste spelers blijven op hun juiste instroomplek.
- Schemawedstrijden zijn gescheiden en gesorteerd per ronde, daarna datum/tijd en wedstrijdnummer. Ontbrekende datums staan achteraan binnen de ronde.
- De schema-invoer toont begintijd en first-to naast elkaar. De opgeslagen spelvorm wordt gebruikt zonder extra keuzelijst. Vrije redeninvoer is verwijderd uit schemabeheer; elke actie krijgt een automatische reden en blijft met beheerder/audit vastgelegd.
- Beheer toont standaard **Nog af te handelen**, inclusief wedstrijden waarvoor de voorspeldeadline verstreken is en de uitslag ontbreekt. Dit betekent geen bevestiging van een werkelijke start. Bij deelnemers blijven alleen daadwerkelijk open voorspellingen onder het open filter staan.
- Na uitslagopslag blijft de betreffende kaart met succesmelding zichtbaar via het filter Alle wedstrijden. Datum opslaan bewaart ingevoerde scores, zodat direct daarna de uitslag kan worden opgeslagen. Een nog niet opgeslagen datum/first-to krijgt een concrete foutmelding bij uitslaginvoer.

## Database en beveiliging

Migratie `20261016210334_tournament_counts.sql` is toegepast op project `sfcozzjcuppfypetbbzn`. De publieke RPC is SECURITY INVOKER; de implementatie staat buiten het blootgestelde schema, heeft een lege search_path en vereist een ingelogde gebruiker. De telling kijkt uitsluitend naar diens eigen voorspellingen. Concepten, verlopen/geblokkeerde/onvolledige wedstrijden en vrijstellingen tellen niet mee.

Spelregels, puntentelling, deadlines, toegangsrechten en bestaande mutatiecontroles blijven behouden. Een datumwijziging heropent voorspellingen niet automatisch. Bestaande beschermingen op afgeronde wedstrijden, voorspellingen en deelnemersnamen blijven gelden.

## Verificatie

- Lokale PostgreSQL/PGlite: alle knock-out-, sjabloon-, beheer-, vergelijkings- en tellingtests geslaagd.
- Negen browsertests met fictieve gegevens: knock-outbeheer, 48-spelersbracket, toernooien, toernooibeheer, poules, accountbeheer, profiel, gebruikersnaamlogin en activering/herstel.
- Bracketgeometrie op 1280, 390 en 320 pixels: zes rondes in één rij, 47 zichtbare wedstrijden, 46 verbindingen, 16 verborgen vrijstellingen, horizontaal schuiven en geen overloop van de pagina. Mobiele schermafbeeldingen visueel gecontroleerd.
- Hosted transactionele tellingtest met fictieve accounts en rollback: eigen/niet-eigen voorspellingen, concepten, handmatig sluiten, echte klokdeadline en anonieme toegang. Geen testaccounts achtergebleven.
- Voor/na: 1 toernooi, 63 wedstrijden, 2 voorspellingen, 1 poule, 115 wedstrijdaudits. Wedstrijdfingerprint gelijk: `d490088596b1da735551adb21a8447a6`. Geen officiële sportgegevens veranderd.
- Security advisors gelijk aan de bestaande baseline: 17 informatieve meldingen over bewust afgeschermde tabellen, 16 bestaande publieke SECURITY DEFINER-functies en 1 bestaande melding over gelekte-wachtwoordbescherming. Geen nieuwe bevindingen.

Browsergedrag is met een nagebootste backend gecontroleerd; de echte database is afzonderlijk transactioneel getest. Geen permanente ingelogde testaccounts aangemaakt voor de publicatiecontrole.
