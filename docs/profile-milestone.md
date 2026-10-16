# Online profiel — 16 oktober 2026

Gebouwd vanaf `9db098c`. Het profielscherm toont geen lokale demovoorspellingen of demo-resetknop meer. Het leest de eigen accountvoorkeuren en voorspellingen uit Supabase. De weergavenaam en het thema worden bij het account opgeslagen; de aanmeldnaam, authenticatie en gebruikersrol blijven ongewijzigd.

## Database en rechten

Migratie `20261016145640_own_profile_preferences.sql` is toegepast. `public.update_my_profile` is een SECURITY INVOKER-wrapper rond de private implementatie. Er is geen user-id-parameter: de functie werkt uitsluitend met auth.uid(). Alleen display_name en theme kunnen worden aangepast. De naam wordt getrimd, moet 1–40 tekens bevatten en mag geen controletekens/regelafbrekingen bevatten. Thema is system/light/dark. Ontbrekende parameters laten de betreffende voorkeur ongewijzigd.

Op profiles waren nog standaardrechten aanwezig voor anon/authenticated, waaronder directe mutaties en TRUNCATE. Deze zijn ingetrokken. Authenticated behoudt SELECT onder de bestaande eigen-profiel-RLS. De gecontroleerde functie is de schrijfroute; profielaanmaak tijdens toekomstige accountprovisioning moet eveneens via een gecontroleerde backendroute verlopen.

## Interface en opslag

- Profiel laden bij aanmelden en bij openen van de profielpagina. Geen gedeeld lokaal profiel tussen accounts.
- De profielkeuze en de headerknop schrijven dezelfde databasevoorkeur. De headerknop wijzigt geen andere conceptinvoer. Opslagaanvragen lopen opeenvolgend om antwoorden niet in willekeurige volgorde toe te passen.
- Systeeminstelling gebruikt prefers-color-scheme en reageert op apparaatwijzigingen zonder invoer te wissen. Expliciet licht/donker volgt de opgeslagen accountkeuze.
- Foutmeldingen behouden invoer en laten opnieuw proberen toe. Profielwijzigingen worden pas als opgeslagen gemarkeerd na een succesvol serverantwoord. Niet-opgeslagen wijzigingen krijgen een waarschuwing bij tabnavigatie/browservertrek.
- Oude predict-demo-v1-opslag wordt verwijderd. predict-ui-v2 bevat alleen tab en theme. De Supabase-authenticatiesessie wordt niet gewist. Problemen met deze optionele UI-cache blokkeren geen accountwijzigingen.
- Eigen voorspellingen worden gefilterd op de ingelogde user-id en het gekozen toernooi. De gekoppelde matches blijven onder RLS. Vaste sortering op gewijzigde tijd en ID; 25 records per pagina. Punten komen uit de bestaande get_my_match_points-functie, zonder nieuwe scoringsformule.
- Laat terugkerende antwoorden worden genegeerd na navigatie of accountwisseling. Een laat profielantwoord overschrijft geen intussen succesvol opgeslagen voorkeuren.

## Verificatie

`supabase/tests/profile_preferences.sql` slaagt op de hosted database met twee fictieve gebruikers en rollback. Getest: alleen eigen profiel lezen/bewerken; direct wijzigen/verwijderen geweigerd; trimmen/valideren; gedeeltelijke wijzigingen; behouden gebruikersnaam en rol; nieuwe weergavenaam zichtbaar in het bestaande klassement; ander profiel ongewijzigd; anoniem lezen/schrijven en een helperaanroep zonder identiteit geweigerd.

`tests/profile-ui.cjs` slaagt in mobiele Edge met een mockbackend die voorkeuren over herladen bewaart. Getest: opslag/herladen; systeemthema en headerknop; foutafhandeling zonder invoerverlies; headerwijziging behoudt conceptnaam; navigatiebevestiging; 26 eigen voorspellingen over twee pagina's; toernooifilter en lege toestand; uitslag/1 punt uit serverantwoord; HTML-escaping; oude-cacheverwijdering met behoud authenticatiesleutel; geen namen/voorspellingen in UI-cache; geen late schermoverschrijving en scheiding van twee accounts. Mobiele screenshot visueel gecontroleerd.

De bestaande toernooi- en poule-browsertests slagen opnieuw. De hosted poule-SQL-suite slaagt opnieuw, inclusief voorspellingprivacy, individuele deadline en 6–4 tegen 6–3 = 1 punt. JavaScript-syntax en diffchecks slagen. Alle fictieve databasegegevens zijn teruggedraaid; officiële wedstrijden en bestaande accountvoorkeuren zijn niet gewijzigd door tests.

Supabase Security Advisor toont dezelfde bestaande meldingen: 7 afgeschermde tabellen zonder policies, 17 bestaande publieke SECURITY DEFINER-RPC's en uitgeschakelde gelekte-wachtwoordcontrole. De nieuwe publieke functie is SECURITY INVOKER. Deze bestaande meldingen zijn niet als opgelost aangemerkt.

## Grenzen en volgende stap

De browser gebruikt mockaccounts; er is geen test met echte gebruikerswachtwoorden uitgevoerd. Databaseautorisatie is apart met echte rollen getest. Een tweede fysiek apparaat is niet getest; de voorkeuren staan server-side en worden bij opnieuw laden opgehaald. Er is geen realtime synchronisatie van wijzigingen tussen reeds geopende apparaten.

Volgende functionele stap: veilige accountuitnodigingen en wachtwoordherstel voor nieuwe deelnemers. De volledige databasebaseline, de bestaande tiebreakdiscrepantie en de overige eerder vastgelegde aandachtspunten blijven open. Scorings- en toernooiregels zijn niet gewijzigd.
