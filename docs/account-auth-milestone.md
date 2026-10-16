# Accountuitnodigingen en wachtwoordherstel — 16 oktober 2026

**Historisch verslag:** de gebruikersstroom is vervangen door [gebruikersnaam en wachtwoord zonder e-mail](manual-accounts-milestone.md). De e-mailactivatiefunctie is gepauzeerd; SMTP en mailtemplates zijn voorlopig geen publicatievoorwaarde. De onderstaande migraties blijven toegepaste historie.

Gebouwd vanaf `04102a5`. GitHub en Supabase zijn vooraf gecontroleerd; project `sfcozzjcuppfypetbbzn` is ACTIVE_HEALTHY. De actuele repository staat lokaal in `predict-webapp/`; de gesynchroniseerde projectbronnen zijn niet gewijzigd.

## Uitnodigen en activeren

Systeembeheerders maken via Beheer een accountuitnodiging voor een e-mailadres. De link wordt één keer getoond en handmatig gedeeld. Een nieuwe uitnodiging vervangt de vorige voor hetzelfde adres. Intrekken werkt per adres. De server begrenst uitgifte op twintig per beheerder per 24 uur, ook bij gelijktijdige aanvragen. De code bevat 256 willekeurige bits en wordt uitsluitend als SHA-256-hash opgeslagen. De accountuitnodiging is zeven dagen geldig en staat los van poule-uitnodigingen.

De ontvanger opent `account.html#invite=...` en vult het uitgenodigde e-mailadres in. De openbare Edge Function controleert de code en het adres via een uitsluitend voor service_role toegankelijke RPC. Mailaanvragen zijn per uitnodiging begrensd op vijf, met minimaal zestig seconden tussen aanvragen. Ongeldige codes, onbekende adressen en Auth-afwijzingen krijgen dezelfde neutrale respons. Supabase Auth verstuurt de activatiemail; de beheerder krijgt geen Auth-token terug. Er wordt geen willekeurig redirectadres van de browser geaccepteerd.

De eerste e-mailbevestiging van een nog niet geprovisioneerd account controleert in dezelfde Auth-databasetransactie of er een geldige, niet ingetrokken accountuitnodiging met mailaanvraag bestaat. De trigger leest het bevestigde adres uit de nieuwe auth.users-rij en maakt profiel/rol aan voordat Auth de bevestiging kan afronden. Een verlopen of ingetrokken uitnodiging laat deze update mislukken. Zo kan een eerder verzonden native Auth-link niet alsnog de app openen. Bestaande volledig geprovisioneerde accounts behouden hun normale herstel-/bevestigingsgedrag. De complete_account_invitation-RPC biedt daarnaast een gecontroleerde, herhaalbare afrondingsroute voor reeds bevestigde sessies. Nieuwe accounts krijgen uitsluitend `user`, een unieke vaste gebruikersnaam (`speler-` plus account-id) en een bewerkbare weergavenaam. User metadata levert nooit rechten op. Bestaande profielen en rollen worden niet overschreven. Accountactivatie voegt niemand automatisch toe aan een toernooi of poule.

De zeven dagen gelden voor de accountuitnodiging. De afzonderlijke Supabase-e-mailcode heeft de kortere, door Auth ingestelde vervaltijd. Binnen de uitnodigingsperiode kan de ontvanger opnieuw een activatiemail aanvragen binnen het genoemde budget. Een mailverzendpoging telt ook bij een afleverfout mee. Nieuwe uitgifte door een beheerder vervangt de uitnodiging en geeft een nieuw budget.

## Wachtwoordherstel en sessies

De inlogpagina verwijst naar wachtwoordherstel. De melding onthult niet of een account bestaat. Supabase bewaakt serverlimieten en de geldigheid/eenmaligheid van herstelcodes. Het aparte accountscherm accepteert recovery- en invite-callbacks, inclusief native impliciete callbacks en token_hash-links. De browser vraagt expliciet om Doorgaan voordat hij een token_hash uitwisselt. Een verlopen/ongeldige link toont geen wachtwoordformulier.

Het accountscherm wist query en fragment vóór het dynamisch laden van de vastgepinde Supabase-client (`2.118.0`). Geen accountcodes, wachtwoorden of sessies worden door dit scherm in localStorage/sessionStorage opgeslagen. Sessies blijven uitsluitend in het geheugen en worden server-side gecontroleerd met getUser. Er is geen vrij instelbare vervolg-URL. De wachtwoordinvoer vereist minimaal twaalf en maximaal 128 tekens en twee gelijke invoeren; aanvullende serverregels blijven in Supabase Auth gelden. Na opslag wordt globale afmelding aangevraagd. Reeds uitgegeven access JWT's kunnen tot hun bestaande vervaltijd geldig blijven; dit wijzigt de bestaande JWT-beveiliging niet.

Profielprovisioning vindt vóór de wachtwoordupdate plaats. Als die update wordt afgewezen, kan dezelfde bevestigde sessie opnieuw opslaan; een aangemaakt account houdt de normale rol user. Een reeds geaccepteerd account wordt niet verwijderd bij het intrekken van latere uitnodigingen.

## Toegepast en gecontroleerd

- Migratie `20261016152411_secure_account_invitations.sql` is toegepast. De bestandsversie is gelijkgetrokken met de door Supabase toegekende versie. Bestaande migraties zijn niet opnieuw uitgevoerd.
- Aanvullende migratie `20261016153120_guard_invited_email_confirmation.sql` is toegepast. De trigger staat in predict_private, gebruikt een lege search_path, en is niet direct aanroepbaar door browserrollen.
- Edge Function `activate-account-invitation` v1 is actief. Gateway-JWT-verificatie staat hier uit omdat de server de 256-bit uitnodigingscode als eigen authenticatie controleert. Ongeldige aanvragen versturen geen e-mail.
- `create-invitation` v3 gebruikt de gecontroleerde RPC's en kan het nieuwe uitgiftebudget niet omzeilen. Deze bestaande functie behoudt gateway-JWT-verificatie en valideert de gebruiker met getUser. De huidige poule-interface blijft de bestaande poule-RPC's gebruiken.
- Openbare Auth-instellingen gecontroleerd: `disable_signup=true`, `mailer_autoconfirm=false`, anonymous sign-ins uit.
- Hosted `supabase/tests/account_invitations.sql` slaagt met fictieve accounts en rollback: rechten, metadata, hashopslag, adresbinding, cooldown, vijf mailpogingen, twintig uitnodigingen, e-mailbevestiging, profiel/rol, acceptatie, hergebruik, vervangen, verlopen, intrekken en anonieme afwijzing. De e-mailbevestigingsupdate is ook rechtstreeks getest: geldige uitnodiging provisiont, verlopen/ingetrokken uitnodiging weigert de update. Deze updates lopen in de test als databasebeheerder; de connector mocht de aparte supabase_auth_admin-rol niet aannemen. Een echte Auth-verificatie via e-mail blijft daarom onderdeel van de acceptatietest.
- De bestaande drie SQL-suites slagen opnieuw: poules, toernooideelname en profielvoorkeuren. Officiële fixtures, uitslagen en spelregels zijn niet gewijzigd.
- Edge-handlerproeven slagen met gemockte Auth/database: CORS, methoden, aanvraagvalidatie, codecontrole vóór verzending, vaste redirect, neutrale antwoorden, fouten en legacy-routering.
- Mobiele Playwright/Edge-tests voor accountscherm en beheerscherm slagen met fictieve gegevens. Bestaande poule-, toernooi- en profielbrowsertests slagen opnieuw. JavaScript-syntax en diffcontrole slagen.
- De gedeployde activatiefunctie retourneert het neutrale antwoord op een ongeldige fictieve code en handelt de CORS-preflight af. Dit heeft geen e-mail verstuurd.
- Security Advisor blijft op 7 tabellen zonder policies, 17 bestaande publieke SECURITY DEFINER-functies en uitgeschakelde gelekte-wachtwoordcontrole. De nieuwe publieke RPC's zijn SECURITY INVOKER. De afgeschermde implementaties blijven in predict_private.

## Publicatie en e-mailacceptatie

De frontend is als concept-PR voorbereid; deze mijlpaal publiceert de frontend niet op main/GitHub Pages. Backend is hierboven al toegepast. Voor de gebruikersstroom moet de frontend inclusief account.html worden gepubliceerd.

Er is geen mail naar een echte inbox verstuurd en er zijn geen echte wachtwoorden gebruikt. SMTP-aflevering, de huidige Auth-mailtemplates en redirectallowlist zijn niet end-to-end geverifieerd. Controleer vóór productiegebruik de exacte redirect `https://quepari.github.io/predict-webapp/account.html` in Auth → URL Configuration en test met een eigen testinbox. De hoofdapp routeert native invite/recovery-callbacks ook door naar account.html als Supabase terugvalt op de Site URL.

Aanbevolen mailtemplates, met een vaste bestemming en token in het fragment:

```html
<!-- Invite user -->
<a href="https://quepari.github.io/predict-webapp/account.html#token_hash={{ .TokenHash }}&type=invite">Activeer je Predict-account</a>
<!-- Reset password -->
<a href="https://quepari.github.io/predict-webapp/account.html#token_hash={{ .TokenHash }}&type=recovery">Kies een nieuw wachtwoord</a>
```

Met deze templates verbruikt openen van de app-pagina de code pas na Doorgaan. Bij de standaard ConfirmationURL kan een mailbeveiligingsscanner de code al bij Supabase verbruiken voordat de app wordt geopend. Het accountscherm ondersteunt die standaardroute wel. Stel een eigen SMTP-provider in voor betrouwbare aflevering buiten toegestane teamadressen en controleer de limieten. Verander de globale OTP-vervaltijd niet naar zeven dagen.

Voor deze implementatie zijn de actuele [Supabase-changelog](https://supabase.com/changelog), [inviteUserByEmail](https://supabase.com/docs/reference/javascript/auth-admin-inviteuserbyemail), [wachtwoordherstel](https://supabase.com/docs/reference/javascript/auth-resetpasswordforemail) en [OTP-verificatiefouten](https://supabase.com/docs/guides/troubleshooting/otp-verification-failures-token-has-expired-or-otp_expired-errors-5ee4d0) geraadpleegd. De aangekondigde [TLS-wijziging](https://supabase.com/changelog/cbc-tls-ciphers-deprecated) vereist geen andere Auth-flow voor de hier gebruikte moderne clients.

De bestaande volledige-databasebaseline, tiebreakdocumentatie en overige eerder vastgelegde beveiligingsmeldingen blijven open.
