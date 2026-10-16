# Online gebruikersvoorspellingen — 16 oktober 2026

Gebouwd vanaf `72fefc4`. Home, het toernooiaanbod en de wedstrijdschermen gebruiken nu Supabase. De oude lokale demo-ID's selecteren geen online wedstrijden. De gewone gebruiker kan deelnemen zonder poule en vervolgens voorspellingen invoeren of wijzigen via dezelfde beveiligde RPC als de bestaande QA-keten. Online voorspellingen worden niet in localStorage opgeslagen. Thema en navigatie blijven lokale voorkeuren.

## Database

Toegepast: `20261016140215_tournament_self_entry.sql` en `20261016140415_restrict_tournament_entry_grants.sql`.

`public.join_tournament` is een SECURITY INVOKER-wrapper rond een private implementatie met expliciete auth.uid()-controle. Alleen het eigen account kan worden ingeschreven, alleen bij published/active. De toernooirij wordt tijdens inschrijving met FOR SHARE vergrendeld en de bestaande unieke sleutel maakt herhalen idempotent. Dit maakt geen poule aan. Bestaande punten-, voorspellings- en deadlinefuncties zijn niet veranderd.

Op tournament_entries waren nog standaardrechten aanwezig voor anon/authenticated, waaronder INSERT, UPDATE, DELETE en TRUNCATE. De tweede migratie trekt die overbodige rechten in en behoudt alleen SELECT voor authenticated onder de bestaande eigen-deelname-RLS. Gecontroleerde backendfuncties blijven de schrijfroute. De databasetest bevestigt dat bestaande pouleaanmaak en uitnodigingsacceptatie blijven werken.

## Interface

- Catalogus en eigen deelnames uit Supabase, met lege toestanden en opnieuw proberen bij verbindingsproblemen.
- Wedstrijden met vaste sortering op geplande start en ID, 50 per pagina. Eigen voorspellingen worden uitsluitend voor het aangemelde account opgehaald.
- Per wedstrijd ronde, status, Nederlandse tijd, formaat, databasepuntenschema, eigen voorspelling en definitieve score. Punten komen uit get_my_match_points; er is geen nieuwe lokale puntenberekening.
- Clientcontrole op hele scores 0–99, vastgesteld dartsformaat of voetbalgelijkspel. Servervalidatie blijft beslissend.
- De deadline sluit een openstaand formulier automatisch. Tussentijdse starts, uitstel en andere beheerwijzigingen zijn zichtbaar na vernieuwen; bij opslag controleert de server altijd de actuele toestand.
- Opslaan wijzigt alleen de eigen wedstrijdkaart en laat andere conceptinvoer intact. Tijdens opslag zijn de ingediende velden tijdelijk vergrendeld. Bij fouten blijft de invoer behouden.
- Waarschuwing bij navigatie, paginawisseling, vernieuwen of browservertrek met niet-opgeslagen invoer. Navigeren/uitloggen voorkomt dat laat terugkerende aanvragen in een nieuw scherm/account verschijnen.

## Verificatie

Hosted SQL-test `supabase/tests/tournament_entry.sql` slaagt met tijdelijke gebruikers/toernooien en rollback: deelname zonder poule; herhaalde deelname zonder duplicaat; geen concept-/afgeronde/gearchiveerde/anonieme deelname; actieve deelname toegestaan; geen inschrijving van een ander via de tabel; geen voorspellen zonder deelname; ongeldige dartsstand geweigerd; eigen voorspelling wijzigen zonder duplicaat; andermans voorspellingen en deelnames blijven afgeschermd.

De bestaande `supabase/tests/private_pools.sql` slaagt opnieuw, inclusief individuele deadline en 6–4 versus 6–3 = 1 punt. Na beide suites zijn nul tijdelijke gebruikers, wedstrijden of toernooien achtergebleven. Officiële gegevens zijn niet aangepast.

Playwright/Edge met mockbackend controleert mobiel: lege Home, gepubliceerd aanbod, deelname, invoeren/herladen, ongeldige dartsstand, voetbalgelijkspel, behouden van andere conceptinvoer, serverfout zonder invoerverlies, automatisch sluiten op deadline, navigatiebevestiging, 51 wedstrijden verdeeld over twee pagina's, fout herstellen met opnieuw proberen, HTML-escaping en geen horizontale overloop of JavaScript-excepties. De privépoule-browsertest slaagt eveneens.

JavaScript-syntax en git diff-controle slagen. Supabase Security Advisor geeft dezelfde aantallen als bij de vorige mijlpaal: 7 afgeschermde tabellen zonder policies, 17 bestaande publieke SECURITY DEFINER-functies en uitgeschakelde gelekte-wachtwoordcontrole. De nieuwe publieke join-wrapper is SECURITY INVOKER.

## Grenzen en vervolg

Er is geen browsertest met echte gebruikerswachtwoorden uitgevoerd. De tests gebruiken echte databaserollen met rollback plus een browsermock; parallelle statuswijzigingen zijn via de lockvolgorde beoordeeld, niet onder belasting getest. Er is geen realtime abonnement of automatisch herladen dat conceptinvoer kan overschrijven.

Profielbeheer bevat nog demo-onderdelen. Accountuitnodigingen/wachtwoordherstel, een volledige databasebaseline, de eerder vastgelegde discrepantie in tiebreakdocumentatie en de bestaande beveiligingsmeldingen blijven vervolgwerk. De tiebreak- en scoringsregels zijn niet aangepast.
