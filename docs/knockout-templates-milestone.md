# Lege knock-outschema’s en toernooisjablonen

## Gedrag

Aanmaken vraagt geen deelnemersnamen meer. De beheerder kiest sport, vrij format of sjabloon, spelers/teams, deelnemersaantal, toernooistart en expliciete punten per ronde. Het resultaat is een leeg concept. Namen worden direct in het zichtbare schema op de officiële lotingsplek ingevuld; namen van geplaatste deelnemers staan bij hun instroomronde. Winnaarverwijzingen blijven automatisch beheerd. Datums/tijden worden met de bestaande wedstrijdformulieren ingevuld.

Het ingebouwde European Tour-sjabloon kiest 48 spelers en legs met first-to 6/6/6/6/7/8. De vrijstellingen worden bij nieuwe schema’s verdeeld: alle 16 wedstrijden van ronde 2 krijgen één geplaatste speler en één winnaar uit ronde 1. Er zijn 47 echte wedstrijden; de 16 technische vrijstellingen leveren geen uitslag of punten op. Het sjabloon bepaalt geen namen, seed-rangnummers of loting; de beheerder volgt de werkelijke loting bij het invullen.

Een eigen format kan bij de geselecteerde sport als herbruikbaar sjabloon worden bewaard. Dit bewaart aantal, spelers/teams, spelvorm, first-to en puntentelling. Sjablonen zijn voor beheerders gedeeld via de database; geen lokale opslag, namen of tijden. Geen import, API, groepsfase of automatisch ombouwen van bestaande schema’s.

## Beveiliging

Lege namen zijn alleen bedoeld voor concepten. Gedeeltelijke invoer kan worden opgeslagen; ingevulde namen zijn uniek, maximaal 80 tekens en bevatten geen controletekens. Namen worden in de interface ge-escaped. De bestaande draft-zonder-voorspellingen-beperking voor naamswijzigingen blijft gelden.

Publiceren wordt geblokkeerd zolang een deelnemersplek leeg is, ook via de bestaande publicatie-RPC. De wedstrijdtrigger controleert naast slotnummers de echte opgeslagen namen voordat voorspellingen of scores kunnen worden gezet. Bestaande serverdeadlines, autorisatie, auditregels, scorevalidatie, doorplaatsing en bescherming van downstream-voorspellingen blijven actief.

Sjablonen staan in een private tabel met RLS en zonder directe browserrechten. Publieke RPC is een invoker-wrapper; de private definer controleert de echte beheerdersrol en heeft een lege search_path. Bestaande functies behouden hun beperkte grants. Validatie van opgeslagen sjablonen hergebruikt de aanmaakvalidatie binnen een teruggedraaide subtransactie; er blijven geen tijdelijke toernooien, wedstrijden of audits achter.

## Verificatie

- `node tests/knockout-db.cjs`: oorspronkelijke knockout-tests plus `supabase/tests/knockout_templates.sql`, uitsluitend lokale PGlite. Controleert lege 48-plekconcepten, 47 echte wedstrijden, 16 R1-wedstrijden en 16 geplaatste R2-tegenstanders, 6/6/6/6/7/8, gedeeltelijke opslag, duplicaten, beide publicatieroutes, score/vrijgavebeveiliging, sjabloonopslag zonder tijdelijke toernooien, toegang en publiceren na volledige invoer. Alles wordt teruggedraaid.
- `node tests/knockout-ui.cjs`: mobiele Edge met fictieve mockbackend; sjabloonkeuze, vooraf ingevulde legs, eigen sjabloon opslaan/selecteren, sportfilter, aanmaken zonder namen, namen op ronde- en slotplekken, gedeeltelijke opslag, escaping, foutbehoud, statusfilter, breedte en Nederlandse zomertijd.
- Bestaande `tests/tournaments-ui.cjs` en `tests/account-admin-ui.cjs` slagen.
- Mobiele schermafbeelding visueel gecontroleerd; geen horizontale overflow.

## Publicatiestatus

Na expliciete toestemming van de gebruiker ("Zet live") is migratie `20261016183915_knockout_templates.sql` toegepast. De versie in het repository is gelijkgetrokken met de werkelijke Supabase-versie. De nieuwe SQL-suite en de bestaande knock-outregressie slagen op Supabase, beide met rollback. De frontend is opgenomen in PR #8. Geen bestaande sportgegevens gewijzigd. Oudere migraties worden niet opnieuw toegepast. Bestaande brackets blijven exact zoals aangemaakt; alleen nieuwe schema’s gebruiken de verdeelde vrijstellingen. Tijdens een uitrol werken oude aanmaakaanvragen met ingevulde namen nog steeds.

Hosted controle: vóór en na 18 wedstrijden, 2 voorspellingen, 26 wedstrijdauditregels en 3 toernooien. Matchfingerprint `d74c64635c41e7a9b4f52b101d841773` blijft gelijk. Nul testgebruikers, testtoernooien en testsjablonen achtergebleven.

Security advisors: één extra informatieve [RLS-zonder-policy-melding](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) voor de bewust private sjabloontabel zonder directe browserrechten (totaal 13). De 17 bestaande [publieke definer-meldingen](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) en één bestaande melding over [gelekte-wachtwoordbescherming](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) zijn ongewijzigd. De nieuwe publieke sjabloon-RPC is een invoker-wrapper.
