# Gebruikersnaam en wachtwoord zonder e-mail — 16 oktober 2026

Deze mijlpaal vervangt de gebruikersstroom uit account-auth-milestone.md. SMTP, een eigen domein en e-mailbevestiging door de deelnemer zijn voorlopig niet nodig. Bestaande accounts, account-id's, rollen, voorspellingen en spelregels blijven behouden.

## Gebruik

1. Een systeembeheerder opent **Beheer → Accounts en herstelcodes** en vult een gebruikersnaam in. Nieuwe namen bevatten 3–32 letters (a–z), cijfers, streepjes of underscores. Namen zijn hoofdletterongevoelig en uniek.
2. **Account uitnodigen** maakt een eenmalige activatielink van zeven dagen. De beheerder deelt de link zelf met de juiste persoon. De ontvanger kiest en bevestigt een wachtwoord van minimaal twaalf tekens. Het wachtwoord is nooit zichtbaar voor de beheerder.
3. De deelnemer logt in met de gebruikersnaam en het wachtwoord. Bestaande e-mailadres/wachtwoordcombinaties blijven tijdelijk als compatibiliteit werken in hetzelfde invoerveld; er wordt geen e-mail verstuurd.
4. Bij een vergeten wachtwoord controleert de beheerder zelf met wie die contact heeft, zoekt het juiste bestaande account en kiest **Herstelcode maken**. De gedeelde link is één uur geldig en laat de ontvanger zelf een nieuw wachtwoord kiezen. Andere systeembeheerders kunnen niet via deze route worden overgenomen; daarvoor is afzonderlijk accountbeheer nodig.
5. **Openstaande codes intrekken** trekt ongebruikte codes voor die gebruikersnaam in. Een nieuwe uitgifte vervangt ongebruikte oude codes. Een code die al bij de server is ingeleverd is verbruikt en kan niet meer worden ingetrokken.

Een poulebeheerder kan nu een bestaande gebruiker op gebruikersnaam uitnodigen. De server vertaalt de naam naar hetzelfde account dat de bestaande poulecontrole gebruikt. De code blijft eenmalig, zeven dagen geldig en uitsluitend door het bedoelde account bruikbaar. Accountactivatie geeft geen automatische toernooi- of pouledeelname.

## Beveiliging en grenzen

- Supabase Auth blijft wachtwoorden hashen, wachtwoorden controleren en sessies uitgeven. Er is geen eigen wachtwoorddatabase. De browser krijgt geen service-role-sleutel of openbare naam/e-maildirectory.
- Nieuwe accounts krijgen intern een niet-bezorgbaar adres op `accounts.predict.invalid`, gebaseerd op een vooraf door de server gekozen UUID. Dit is uitsluitend een Auth-identificatie, geen claim dat de gebruiker een echt e-mailadres heeft geverifieerd. De deelnemer hoeft dit adres niet te kennen. Bestaande echte accountadressen worden niet gewijzigd.
- Een backend-aanroep verbruikt een 256-bit code atomair vóór de Auth-mutatie. Alleen SHA-256-hashes worden opgeslagen. Aanmaak van profiel, gebruikersnaam en gewone rol `user` gebeurt in dezelfde databasetransactie als Auth-aanmaak via een private trigger. User metadata geeft geen rechten.
- Uitgifte vereist actuele systeembeheerdersrechten en is begrensd op twintig accountcodes per beheerder per 24 uur. Openbare accountaanmaak blijft uitgeschakeld. Nieuwe publieke RPC's voor browsergebruik zijn SECURITY INVOKER-wrappers; backendfuncties zijn uitsluitend voor service_role uitvoerbaar.
- De gebruikersnaamroute heeft een atomair budget van twintig loginpogingen per naam per vijftien minuten en duizend voor de route als geheel. Codepogingen hebben afzonderlijke vergelijkbare budgetten. Supabase Auth behoudt zijn eigen limieten, ook voor de bestaande native inlogroute. Onbekende namen en onjuiste wachtwoorden geven dezelfde fouttekst; een minimumantwoordduur beperkt eenvoudige timingverschillen.
- Codes en wachtwoorden worden niet in lokale UI-opslag bewaard. De accountpagina wist het URL-fragment vóór het laden van de vastgepinde Auth-client en gebruikt geen persistente sessie. De hoofdapp behoudt haar normale Supabase-sessieopslag.
- Na een handmatige wachtwoordreset worden alle refresh-sessies van uitsluitend dat account verwijderd; refresh_tokens volgen via de bestaande cascade. Reeds uitgegeven access JWT's blijven tot hun normale vervaltijd geldig. Profiel, rol en voorspellingen veranderen niet.
- Auth en de codeclaim zijn aparte API-transacties. Bij een netwerk-/Auth-fout na claim is de code bewust verbruikt; de beheerder maakt een nieuwe. Nieuwe uitgifte wordt maximaal vijf minuten geblokkeerd zolang een eerdere claim wordt verwerkt. Er is geen gelijktijdige belastingstest uitgevoerd; lockvolgorde en hergebruik zijn wel gecontroleerd.
- E-mailactivatie is gepauzeerd: `activate-account-invitation` retourneert 410 en initialiseert geen mailclient. Het huidige accountscherm vraagt geen herstelmail aan. De oude e-mailmigraties blijven als reeds toegepaste historie aanwezig.

## Toegepast en getest

Backend op `sfcozzjcuppfypetbbzn`:

- `20261016155043_manual_username_accounts.sql` en `20261016155426_authorize_username_pool_lookup.sql` toegepast. De tweede controleert poule-eigendom voordat een gebruikersnaam wordt opgezocht. De bestandsversies komen overeen met Supabase.
- `manual-account` v1 en `username-login` v1 actief; gateway-JWT-verificatie staat uit omdat de handlers zelf een eenmalige code respectievelijk een echt wachtwoord controleren. Geen code of service key kan wachtwoordcontrole vervangen.
- `activate-account-invitation` v2 gepauzeerd; `create-invitation` v4 gebruikt de gecontroleerde naam-/code-RPC's en behoudt gateway-JWT-verificatie plus getUser-controle.

De echte hosted ketentest met een tijdelijk fictief account slaagt: activatie, hoofdletterongevoelige gebruikersnaaminlog, geweigerd hergebruik, reset via beheerderscode, geweigerd oud wachtwoord, geweigerde oude refresh-token, werkend nieuw wachtwoord en uitgeschakelde mailroute. Testwachtwoorden zijn willekeurig gegenereerd en sessietokens bleven uitsluitend in het testproces. Het fictieve beheeraccount, deelnemersaccount en de bijbehorende codes zijn verwijderd; de controle toont nul achtergebleven live-testaccounts. Er is geen e-mail verstuurd. `tests/manual-live.cjs` is een optionele hosted test en vereist expliciet aangemaakte wegwerpfixtures en gerichte opruiming door de uitvoerder.

`supabase/tests/manual_accounts.sql` slaagt met rollback: alleen beheerder kan uitgeven, geen overname van andere beheerders, geen tabel-/directorytoegang voor browserrollen, hashopslag, naam-/doelbinding, vervangen, hergebruik, verlopen, intrekken, rol user, loginbudget, sessieverwijdering en poule-uitnodiging op gebruikersnaam. Een buitenstaander kan via poules geen bestaande of ontbrekende naam opzoeken. De eerdere SQL-suites voor poules, toernooien, profielbeheer en de historische e-mail-RPC's slagen opnieuw. Officiële sportgegevens zijn niet gewijzigd.

De browserproeven voor gebruikersnaaminlog, activatie/herstel en beheerdersuitgifte slagen met fictieve backendgegevens. De eerdere poule-, toernooi- en profielbrowsertests slagen opnieuw. Edge-handlerproeven controleren echte wachtwoordverificatie als verplichte stap, codecontrole, resetdoel, vaste oorsprong, limieten op invoer, gepauzeerde mail en legacy-routering. Syntax- en diffcontroles slagen.

Security Advisor: 17 bestaande publieke SECURITY DEFINER-meldingen en uitgeschakelde gelekte-wachtwoordcontrole blijven open. De informatieve RLS-zonder-policy-meldingen stijgen van 7 naar 9: de twee nieuwe tabellen staan bewust afgeschermd in predict_private, met RLS en ingetrokken browserrechten. Er zijn geen algemene leespolicies toegevoegd. Zie [RLS-melding](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [publieke definer-functies](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) en [gelekte-wachtwoordcontrole](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

De frontend staat in concept-PR #4 en is nog niet op main/GitHub Pages gepubliceerd. Na publicatie kan een bestaande systeembeheerder de beschreven knoppen gebruiken. Een mailprovider of domeinaankoop is hiervoor niet nodig. De huidige [Supabase-admin-API](https://supabase.com/docs/reference/javascript/auth-admin-createuser) en [wachtwoordupdate-API](https://supabase.com/docs/reference/javascript/auth-admin-updateuserbyid) zijn vóór implementatie gecontroleerd.
