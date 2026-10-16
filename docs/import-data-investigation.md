# Onderzoek ontbrekende ronde en starttijd

## Damon Heta – Maikel Verberk, 16 oktober 2026

Alleen-lezencontrole van voorstel `fx_e97f561d096c95e8`, aangemaakt om 16:44:55 UTC:

- Toernooi: Dutch Darts Championship 2026.
- Opgeslagen bronronde: `last_48`.
- Opgeslagen start: `null`; bronvlag `date_confirmed=false`.
- Geen oorspronkelijke providerresponse in deze nieuwe importwachtrij. Het voorstel bevat alleen genormaliseerde velden. Daardoor bewijst een lege starttijd op zichzelf niet hoe het oorspronkelijke antwoord eruitzag.

De ronde was beschikbaar maar de beheerpagina selecteerde nooit een ronde. Dit is opgelost met eenduidige naamherkenning en een expliciete Dutch Darts Championship-koppeling: `last_48` naar Eerste ronde en `last_32` naar Tweede ronde. Die koppeling geldt alleen als de zes verwachte lokale ronden uniek aanwezig zijn. Andere competities, onbekende codes en dubbele/ontbrekende ronden krijgen geen gok. De keuze blijft wijzigbaar. Dit vult alleen het formulier; het verwerkt of opent geen wedstrijd.

Een aanwezige bronstart wordt nu als Nederlandse tijd getoond (Europe/Amsterdam, inclusief zomer-/wintertijd). Een ontbrekende tijd blijft expliciet ontbrekend; er wordt geen 22:00 ingevuld op basis van een externe verwachting. `date_confirmed` wordt aangeduid als bevestiging van de speeldatum, niet als bevestiging van de precieze starttijd.

De adapter leest het gedocumenteerde veld `starts_at`. Een fictieve response met 20:00 UTC wordt behouden en verschijnt in oktober als 22:00 Nederlandse tijd. Tests controleren ook de ronde, datumvlag, ontbrekende tijd, ontbrekende tijdzone en afwijkende UTC-datum. Dit bevestigt de verwerking van het gedocumenteerde formaat, maar vervangt geen controle van de daadwerkelijke providerresponse.

## Nog open

Het oorspronkelijke antwoord voor deze wedstrijd moet nog via een ingelogde beheerder of een veilige serverdiagnose worden bekeken. De API-sleutel is alleen in de backend beschikbaar; lokale CLI-authenticatie ontbreekt. Geen geheime waarden opgehaald, geen extra providercalls uitgevoerd en geen beveiliging afgezwakt om dit te omzeilen.

De PDPA-planning bevestigt ronde één en de avondsessie, maar geeft geen individuele tijd van 22:00. Een sessievolgorde of verwachte begintijd is geen garantie dat een wedstrijd niet eerder begint. Volledige automatische vrijgave vereist daarom nog een expliciete, geteste deadline-aanpak en betrouwbare informatie over spelvorm en first-to. Deze correctie levert geen cron of automatische wedstrijd-/uitslagverwerking.

Bronnen:

- https://dartsapi.com/documentation/endpoints/fixtures
- https://pdpa.co.uk/news/dutch-darts-championship-et-15/

Validatie: `tests/import-rounds.cjs`, `tests/darts-source.cjs`, `tests/imports-ui.cjs` en `tests/account-admin-ui.cjs`. Geen database- of Edge Function-wijzigingen voor deze correctie.
