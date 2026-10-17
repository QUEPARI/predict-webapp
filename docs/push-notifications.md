# Pushmeldingen

## Gedrag

- Iedere nieuwe overgang naar `announced` zet één spelaankondiging klaar voor alle op dat moment aangemelde apparaten, ook van gebruikers die nog niet deelnemen. Een herhaalde statuswijziging verstuurt dezelfde aankondiging niet opnieuw. Bestaande aankondigingen worden bij installatie niet achteraf verstuurd.
- Iedere klokslag (`0 * * * *`, UTC, dus ook ieder lokaal uur) komt maximaal één automatische herinnering per apparaat in de wachtrij, over alle deelnemende spellen samen. Alleen open, bevestigde, nog niet voorspelde wedstrijden tellen mee. Concepten, aangekondigde/gepauzeerde spellen, vrijstellingen, onbekende tegenstanders, verstreken deadlines, uitgestelde/gestarte wedstrijden en uitslagen tellen niet mee.
- De verzendfunctie controleert bij het ophalen opnieuw of er nog iets te voorspellen valt. Herinneringen vervallen na één uur; aankondigingen en eigen berichten na 24 uur. De pushprovider kan een eenmaal geaccepteerde melding alsnog vertraagd afleveren.
- Beheer → Meldingen biedt bereikvoorvertoning, handmatige herinneringen, spelaankondigingen en eigen berichten. Een eigen bericht gaat naar alle aangemelde apparaten, of alleen deelnemers van het gekozen spel. Aankondigingen gaan naar iedereen. Herinneringen alleen naar deelnemers met ontbrekende voorspellingen. De laatste tien handmatige verzendingen tonen bezorgstatussen.
- HTTP 404/410 verwijdert een verlopen apparaat; 408/429/5xx worden maximaal vijf keer geprobeerd met oplopende wachttijd. Een lease en unieke verzendkenmerken voorkomen normale dubbele verwerking. Zoals bij elke externe pushdienst kan een netwerkfout ná acceptatie incidenteel een dubbele aflevering opleveren.

## Telefoon

Account → Telefoonmeldingen → Meldingen aanzetten vraagt expliciete toestemming. iOS/iPadOS vereist een geschikte versie en opening vanaf het beginscherm; hiervoor staat instructie in de interface. Android gebruikt een ondersteunende browser of geïnstalleerde webapp. Een normale snelkoppeling is geen garantie op iOS-pushondersteuning.

Uitzetten en uitloggen verwijderen alleen het huidige apparaat. Bij wisselen van account wordt een bestaande browserkoppeling aan de ingelogde gebruiker gekoppeld en verdwijnen wachtende meldingen van de vorige gebruiker. Maximaal vijf apparaten per account. De gebruiker kan toestemming altijd via het besturingssysteem intrekken. Er is geen automatische toestemmingspopup bij openen van de site.

## Ingebruikname

De migratie start met `enabled=false`: de frontend toont dan dat de service nog wordt ingericht. Het alleen publiceren van HTML/JS activeert geen verzending. De VAPID-privésleutel en het cron-token staan versleuteld in Supabase Vault. Alleen de server-worker kan ze via een service-role RPC lezen. Alleen de VAPID-publieke sleutel wordt doorgegeven aan een ingelogde browser. De bestaande service-role sleutel wordt door Supabase automatisch aan de Edge Function geleverd.

1. Controleer `supabase --help` en de actuele CLI-opties. Pas `20261017170956_web_push_notifications.sql` en `20261017171105_push_vault_credentials.sql` toe via de normale migratiewerkwijze. De migratie installeert een uurtaak en een minuuttaak, die uitgeschakeld blijven totdat de configuratie is geactiveerd.
2. `node scripts/prepare-push.cjs sfcozzjcuppfypetbbzn` genereert sleutels onder de git-genegeerde map `.local-test/push-deployment/`. Het script drukt geen geheimen af en weigert bestaande sleutels te overschrijven.
3. De ingebouwde Edge Function-variabelen `SUPABASE_URL` en `SUPABASE_SERVICE_ROLE_KEY` zijn voldoende; een aparte CLI-login om secrets in te stellen is niet nodig.
4. Deploy `supabase/functions/send-push/index.ts` met `verify_jwt=false`. De functie controleert zelf op iedere aanroep de geheime `x-push-worker` header. Dit is géén vrij toegankelijke verzendroute. CLI: `supabase functions deploy send-push --project-ref sfcozzjcuppfypetbbzn --no-verify-jwt`.
5. Voer `.local-test/push-deployment/activate.sql` uit als databasebeheerder, bijvoorbeeld via `supabase db query --linked --file .local-test/push-deployment/activate.sql`. Dit zet het token en de VAPID-privésleutel in Vault, configureert de URL/publieke sleutel en activeert verzending. Print dit bestand niet, neem het niet op in Git en gebruik geen shellvariabelen voor geheime waarden.
6. Publiceer de frontend, `push-worker.js` en `icons/` samen. De service worker heeft uitsluitend pushhandlers, geen fetchcache; hij onderschept geen account- of API-verkeer. Manifestscope en serviceworkerscope blijven beperkt tot `/predict-webapp/`.
7. Meld één eigen testtelefoon aan, verstuur een handmatig testbericht en controleer ook ontvangst terwijl de app gesloten is. Controleer `cron.job_run_details`, HTTP-responses en alleen geaggregeerde aantallen in de beheerinterface. Verzend geen testbericht naar alle echte gebruikers.
8. Bewaar productie-VAPID-sleutels veilig buiten Git; verwijder de tijdelijke lokale bestanden wanneer de configuratie is afgerond en veilig geback-upt. Sleutelrotatie maakt bestaande subscriptions onbruikbaar en vereist opnieuw aanmelden van apparaten.

Terugdraaien zonder gegevensverlies: `update predict_push.config set enabled=false;` stopt ophalen en automatisch klaarzetten. Voor volledige uitschakeling kunnen daarnaast de twee cron-taken worden uitgeschakeld; de bestaande appfuncties blijven werken.

## Beveiliging en controles

Alle tabellen staan in een private schema, hebben RLS en geen rechtstreekse clientrechten. Alleen ingelogde gebruikers mogen hun eigen apparaat aanmelden/verwijderen. De beheercontrole leest `user_roles`, nooit wijzigbare user-metadata. Gewone gebruikers krijgen geen endpoints, abonnementenlijsten, geschiedenis of bereik van anderen te zien. De worker-RPC's zijn uitsluitend uitvoerbaar door `service_role`. SECURITY DEFINER-functies hebben een lege `search_path` en beperkte expliciete EXECUTE-rechten.

Pushendpoints zijn beperkt tot bekende HTTPS-pushproviders (FCM, Mozilla, Apple en Windows) om server-side verzoeken naar willekeurige adressen te blokkeren. Titel/bericht zijn platte tekst; de browserinterface escaped gegevens. De service worker negeert bestemmings-URL's in de payload en opent uitsluitend Predict. Verzendkenmerken zijn idempotent; beheerders kunnen maximaal één nieuwe verzending per 30 seconden klaarzetten. Geschiedenis en wachtrij worden na 30 dagen opgeruimd.

Lokale controles, zonder echte ontvangers:

```
node tests/push-db.cjs
node tests/push-functions.cjs
node tests/push-setup.cjs
node tests/push-ui.cjs
node tests/profile-ui.cjs
node tests/management-ui.cjs
node tests/tournaments-ui.cjs
```

De DB-test draait de migratie in PGlite en controleert scheduler-SQL met inerte cron/net/Vault-stubs. De echte hosted extensies worden daarnaast gevalideerd bij ingebruikname. De functietest mockt de pushprovider; de browsertest mockt telefoontoestemming. De Deno-test in `supabase/functions/send-push/` controleert echte VAPID-handtekeningen en een versleuteling/ontsleuteling zonder netwerk: `deno test --allow-env webpush.test.ts`. `deno check index.ts` controleert de verzendfunctie; `deno.lock` legt dependencies vast. Werkelijke aflevering door Apple/Google en OS-instellingen vereist altijd de test op een aangemelde telefoon uit stap 7.
