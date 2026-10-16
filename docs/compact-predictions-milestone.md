# Compacte voorspellingen en vergelijken

## Opgeleverd
- Inklapbare wedstrijdkaarten met compacte samenvatting, uitslag indien bekend en altijd een expliciet label Voorspellen open/gesloten met reden. Onmogelijke acties zijn uitgeschakeld; de database blijft de definitieve controle uitvoeren.
- Meldingen staan bij de kaart of het formulier. Een ontbrekende/niet opgeslagen datum wordt rood gemarkeerd. Fouten behouden invoer; na datumopslag blijft de kaart open en kunnen scores direct worden opgeslagen. Ook vooraf ingevulde, nog niet opgeslagen scores blijven na datum-/startopslag behouden. Opgeslagen status, toernooifilter en uitgeklapte kaart worden na de backendverversing opnieuw gebruikt.
- Compacte schemaplekken: alleen nummer en naam, winnaar lichtgroen met vinkje; uitslagen in het volledige schema. Kleuren hebben aparte waarden voor donker thema.
- Beheer → Wedstrijden toont standaard alleen werkelijk open wedstrijden; Toon alle wedstrijden toont ook gesloten wedstrijden en opgeslagen uitslagen. De bestaande beheer-RPC bevatte geen scorekolommen: een aparte afgeschermde admin-RPC levert de opgeslagen uitslagen.
- Bewerk-/publiceer-/pauzeknoppen hebben blauw/groen/oranje; verwijderen rood.
- Bij verwijderen zonder wedstrijd-/winnaarsvoorspellingen en zonder poules volstaan impactoverzicht, reden en gewone bevestiging. Bij gekoppelde voorspellingen of poules blijft de getypte naam verplicht. De server controleert dit zelf op basis van actuele aantallen, niet op een clientbeslissing.
- Toernooi krijgt aparte tabbladen Voorspellingen, Uitslagen, Schema, Toernooiwinnaar en Klassement. Voorspellingen en Uitslagen hebben een rondekeuze en paginering. Standaard alleen open wedstrijden, met optie alle wedstrijden. Tabwisselen bewaart invoer; ronde/pagina/verversen vraagt bevestiging bij conceptinvoer. Herproberen na een verbindingsfout behoudt tab en filter.
- Gesloten wedstrijdkaarten tonen voorspelling/uitslag/punten naast elkaar in plaats van een uitgeschakeld formulier. Ook na het verlopen van een deadline verschijnt de opgeslagen voorspelling in de samenvatting. Spelregels en punten zijn inklapbaar.
- Pouledetails vervangen het overzicht met een terugknop. Namen zijn aanklikbaar; vergelijking toont per ronde jouw voorspelling, die van je poulegenoot, officiële uitslag en beide punten. Snelle wisselingen kunnen een nieuwere selectie niet overschrijven. Laden/fouten hebben zichtbare terugkoppeling.

## Beveiliging

De nieuwe vergelijkings-RPC controleert dat de ingelogde gebruiker én de gekozen medespeler lid zijn van dezelfde opgegeven poule. Een andere ronde/toernooi-combinatie wordt geweigerd. Alleen wedstrijden met een verstreken individuele deadline of werkelijk verstreken startmoment worden teruggegeven. Handmatig sluiten vóór de deadline onthult niets. Ook een per ongeluk in de toekomst ingevoerde actual_start onthult niets: de bestaande RLS-helper is aangescherpt met een expliciete klokcontrole. Verwijderde pouleleden verliezen toegang. Er zijn geen brede leesrechten op voorspellingen toegevoegd.

De publieke nieuwe RPC’s zijn invoker-wrappers met alleen authenticated execute; de private functies controleren echte beheerdersrechten of poollidmaatschap en gebruiken search_path=''. Bestaande wedstrijd-/toernooiwinnaarpunten, deadlines, audits en downstream-bescherming blijven ongewijzigd. Een ontbrekende geplande datum wordt niet automatisch als gespeelde wedstrijd behandeld: de bestaande expliciete registratie van werkelijke start blijft beschikbaar. Een uitslag voor een toekomstige, niet werkelijk gestarte wedstrijd blijft geblokkeerd.

## Verificatie

Lokale PGlite: eerdere knockout/sjabloon/beheer-suites plus compact_predictions.sql. Controleert privacy bij vroegtijdig sluiten en toekomstige actual_start, wederzijds lidmaatschap, verlies van toegang na verwijdering, beide voorspellingen/punten en eenvoudiger verwijderen van een leeg toernooi. Alle tests gebruiken fictieve gegevens en rollback.

Browsertests: knockout-ui controleert ontbrekende datum, veldmarkering, behoud van score, datum opslaan en onmiddellijk resultaat opslaan met een nieuwe backend-snapshot, lokale succesmelding en groene winnaar. tournaments-ui controleert de tabs, conceptbehoud, deadlines, paginering en retry. pools-ui controleert afzonderlijke detailnavigatie en naast-elkaar vergelijking. Ook management-, accounts-, profiel-, login- en activatie/herstelregressies slagen. Mobiele screenshots visueel gecontroleerd.

Geen officiële gegevens zijn voor tests gebruikt of aangepast. De uitrol voert geen verwijderactie uit. Geen extra API-automatisering toegevoegd.

## Hosted verificatie en uitrol

Migratie `20261016202950_compact_predictions.sql` is toegepast na de expliciete opdracht om te publiceren. Een eerste verlopen toolverzoek had niets uitgevoerd; dat is gecontroleerd vóór één geslaagde herpoging. De nieuwe privacy/vergelijkingssuite en eerdere beheer/winnaars-suite slagen op Supabase met rollback. Voor en na blijven 1 toernooi, 63 wedstrijden, 1 poule, 0 wedstrijdvoorspellingen, 101 wedstrijdaudits en 4 beheeraudits bestaan. Matchfingerprint `596b650777b70eca06f518092f966ff7` is ongewijzigd; nul testgebruikers achtergebleven. Anonieme toegang tot vergelijken is geweigerd.

Security advisors zijn ongewijzigd: 17 informatieve [private-RLS-meldingen](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), 16 bestaande [publieke definer-meldingen](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) en één bestaande melding over [gelekte-wachtwoordbescherming](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). De nieuwe publieke RPC’s zijn invoker-wrappers.
