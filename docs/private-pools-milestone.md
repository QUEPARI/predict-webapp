# Privépoules — 16 oktober 2026

## Uitgangspunt en gerealiseerde mijlpaal

Gebouwd vanaf `3cd3e5f`. De bestaande JavaScript-frontend, Supabase Auth, serverberekening, individuele deadlines en centrale voorspellingen zijn behouden. Geen React-migratie of nieuwe puntentelling ingevoerd.

De live tabellen `pools`, `pool_members` en `invitations` hadden RLS maar geen policies. Het oude `schema.sql` is een afwijkend concept, geen live baseline. De nieuwe migratie sluit aan op de geïnspecteerde hosted structuur. Toepassing via de geautoriseerde `apply_migration`-tool slaagde. De eerdere gemelde toolblokkade kon niet worden gereproduceerd; de historische oorzaak is daarmee niet bewezen.

Ondersteund: aanmaken en automatisch deelnemen; eenmalige e-mailgebonden uitnodigingscodes; accepteren met bevestigd accountadres; verlaten/verwijderen; beheer overdragen; alle openstaande uitnodigingen intrekken; klassement per poule en ronde. De code wordt handmatig gedeeld. Nieuwe accounts aanmaken en e-mail verzenden vallen buiten deze mijlpaal.

## Beveiliging

- RLS blijft ingeschakeld. Alleen leden en bestaande systeembeheerders lezen poules/leden.
- Browserrollen krijgen alleen SELECT op poules/leden, geen mutatierechten en geen tabeltoegang tot uitnodigingen.
- Publieke RPC's zijn SECURITY INVOKER. SECURITY DEFINER-implementaties staan in `predict_private`, met lege search_path en expliciete auth.uid()-controles. Dit schema mag niet aan de Data API worden toegevoegd.
- Uitnodigingen bevatten 256 bits willekeur; alleen de SHA-256-hash wordt opgeslagen. Geldigheid zeven dagen, geverifieerd accountadres verplicht, eenmalig gebruik. Token noch ontvangeradres wordt voor deze stroom in localStorage opgeslagen.
- Alle lidmaatschapsmutaties vergrendelen eerst de poule; uitnodigingsacceptatie vergrendelt daarna de uitnodiging. Vervangen, overdragen en verwijderen trekken relevante openstaande codes in.
- Verlaten/verwijderen raakt de centrale toernooideelname en voorspellingen niet. Poule-eigenaars krijgen geen systeembeheerdersrechten.

## Testresultaten

`supabase/tests/private_pools.sql` slaagt op de hosted database met drie tijdelijke gewone gebruikers en een tijdelijke fixture in het bestaande fictieve QA-toernooi. Alles is teruggedraaid:

- Eigenaar wordt lid en toernooideelnemer; accepteren voegt ontvanger aan beide toe.
- Buitenstaander ziet geen poule/leden/klassement; gewone leden kunnen niemand uitnodigen of de eigenaar verwijderen.
- Direct lid toevoegen/eigenaar wijzigen en uitnodigingshashes lezen worden geweigerd; anonieme pouleaanmaak wordt geweigerd.
- Verkeerd e-mailadres, vervangen, hergebruikte, ingetrokken en verlopen codes worden geweigerd.
- Voorspellingen van poulegenoten zijn vóór de deadline afgeschermd en na geregistreerde start leesbaar.
- Geldige voorspelling vóór de deadline wordt opgeslagen; na werkelijk verstreken tijd weigert de RPC een wijziging. De oorspronkelijke voorspelling blijft bestaan.
- 6–4 voorspeld en 6–3 gespeeld levert 1 punt op, ook in het pouleklassement.
- Verwijdering ontneemt poule- en klassementtoegang zonder centrale voorspelling te wissen; opnieuw toetreden neemt historische punten mee.
- Eigendomsoverdracht en vertrek werken; de oude eigenaar verliest beheersrechten.

De bestaande leesfunctie gebruikt PostgreSQL `now()` (transactiestart); de schrijftest gebruikt de bestaande RPC met `clock_timestamp()`. Zichtbaarheid na start wordt daarom apart geverifieerd. Een test binnen één lange transactie is geen nieuwe HTTP-aanvraag.

`tests/pools-ui.cjs` slaagt in een mobiele Edge-browser met mockbackend: aanmaken, uitnodigen, accepteren, overdragen, poule-/rondefilter, foutafhandeling, HTML-escaping, geen horizontale pagina-overloop, geen lokaal opgeslagen uitnodigingscode en geen JavaScript-excepties. SQL- en browsertest vullen elkaar aan; een echte browserlogin met meerdere bestaande accounts is niet uitgevoerd. Gelijktijdigheid is via lockvolgorde beoordeeld, niet met parallelle databasesessies belast.

`node --check app.js` en `git diff --check` slagen. Na SQL-tests zijn nul tijdelijke QA-gebruikers, nul tijdelijke fixtures en nul poules/leden achtergebleven. Officiële fixtures en uitslagen zijn niet gewijzigd.

## Resterende aandachtspunten

- Supabase Security Advisor meldt bestaande publiek aanroepbare SECURITY DEFINER-RPC's; beoordeel hun autorisatie per functie. De nieuwe publieke poule-RPC's zijn SECURITY INVOKER. Geen bestaande rechten breed ingetrokken en RLS nergens uitgeschakeld.
- De advisor meldt bestaande tabellen zonder leespolicies, inclusief bewust afgeschermde uitnodigings- en audittabellen. Dit is geen reden om deze tabellen algemeen toegankelijk te maken. [Toelichting](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).
- Beveiliging tegen gelekte wachtwoorden staat uit; dit is ongewijzigd. [Supabase-documentatie](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
- Leg de volledige bestaande databasestructuur en oude migratiehistorie vast voordat een lege installatie/rebuild wordt ondersteund. De lokale migratienaam is gelijkgetrokken met de door Supabase uitgegeven versie.
- De oude roadmap noemt exact voorspelde uitslagen als extra tiebreaker, terwijl de huidige live klassementfunctie alleen punten en correcte winnaars rangschikt. Die bestaande functie is in deze mijlpaal behouden; harmoniseer deze documentatie en spelregel expliciet in een vervolg.
- Home/toernooikaarten en profiel bevatten nog demo-onderdelen. Accountuitnodigingen, automatische e-mailaflevering, accountverwijdering en uitgebreid auditbeheer vragen afzonderlijk vervolgwerk.

Actuele documentatie voor de aanpak: [Data API-beveiliging](https://supabase.com/docs/guides/api/securing-your-api), [Supabase-changelog](https://supabase.com/changelog).
