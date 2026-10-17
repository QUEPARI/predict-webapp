# Vooraankondiging, sjablonen en toernooibeheer

## Gedrag
Een nieuw knock-outspel kan als Concept of Vooraankondiging worden aangemaakt. Een vooraankondiging vereist een geldig van/tot-bereik en verschijnt onder Beschikbare spellen. De informatiepagina toont uitsluitend naam, datums en de aankondiging. Deelname, poules en voorspellen blijven gesloten. Namen, first-to en punten kunnen nog ontbreken. Na aanvullen kan het aangekondigde spel via de bestaande gecontroleerde route worden gepubliceerd.

Beheer bewaart start en einde als UTC-timestamps vanuit Nederlandse invoer. Beide datums verschijnen zonder tijden op eigen en beschikbare spelkaarten, geformatteerd in de apparaattijdzone. Wedstrijddeadlines en tijden zijn ongewijzigd. Bestaande toernooien krijgen geen verzonnen einddatum.

Beheer → Sjablonen toont de bestaande eigen sjablonen en de European Tour-standaard. Eigen sjablonen aanmaken/bewerken gebruikt volledige formatvalidatie. De standaard biedt Kopie maken. Toernooien zijn onafhankelijke kopieën van de sjablooninstellingen; het wijzigen van een sjabloon raakt geen bestaande wedstrijden of puntentellingen.

Spelvorm staat eenmaal boven de tabel. De rondekolommen zijn Ronde, First-to, Punten winnaar en Punten exact. Darts biedt legs/sets; voetbal doelpunten zonder first-to. Historische gemengde toernooiformats worden expliciet als bestaand gemengd format behouden zolang geen centrale vervangende spelvorm is gekozen.

Schema’s en Wedstrijden zijn verwijderd uit het algemene beheermenu. Open een toernooikaart en kies Schema of Wedstrijden; de interne navigatie behoudt toernooicontext en filtert wedstrijdbeheer op dat toernooi. Het algemene aanmaakformulier blijft via Nieuw toernooi bereikbaar. Wedstrijdacties staan onder Acties. Niet-opgeslagen invoer wordt behouden of vraagt expliciete bevestiging bij vervanging.

PREDICT. is aanklikbaar naar Home, de beide hoofdpaginakoppen zijn even groot en voorspellingsnamen staan gecentreerd boven hun scorevelden.

## Database
Migratie **20261017104818_game_previews_and_templates.sql** is toegepast. Status announced is toegevoegd. Bestaande wedstrijd-/ronde-/puntenpolicies beperken leesrechten tot gepubliceerde, actieve, afgeronde of gearchiveerde spellen; alleen de toernooimetadata is bij een aankondiging zichtbaar. Ook schema- en winnaarsvraag-RPC’s verbergen vooraankondigingen voor gewone gebruikers. Bestaande join/create-pool- en voorspellingsstatuscontroles blijven actief.

Status- en datumbereikvalidatie gebeurt ook op de server. Annonceert alleen vanuit concept; bestaande deelnemers/voorspellingen/gestarte wedstrijden blokkeren de aankondiging. Publicatie blijft complete instellingen eisen. Create_knockout_game bewaart naam, bereik, rondekopie en status atomair. Manage_knockout_template valideert een onafhankelijk format voordat een eigen sjabloon wordt bijgewerkt. Alle nieuwe publieke wrappers zijn security invoker; de afgeschermde helpers controleren de bestaande beheerrol en hebben een lege search_path. Geen nieuwe tabel of publieke schrijfrechten.

## Verificatie
- Volledige lokale PGlite-regressiesuite plus aangekondigde creatie met lege instellingen, ongeldige bereiken, RLS voor metadata versus verborgen wedstrijden/rondes/punten, geweigerde deelname/poule/schema/winnaarsvraag, aanvullen en publiceren.
- Gewone gebruikers kunnen geen aankondiging of sjabloon wijzigen. Een sjabloon wordt aangepast en het reeds aangemaakte spel wordt inhoudelijk identiek bevonden.
- Dezelfde nieuwe SQL-test op het gekoppelde project met fictieve accounts en rollback. Geen testaccounts achtergebleven.
- Browsercontroles: sjabloon maken/bewerken en direct kiezen bij nieuw toernooi, één spelvorm en compacte rondetabel, contextueel schema/wedstrijden, inklapbare acties, datumkaart zonder tijd, geen deelname op aankondiging en logo naar Home. Mobiele controle op 320/390 px en desktop op 1280 px.
- Bestaande schema-, beheer-, toernooi-, poule-, account-, profiel-, thema- en inlogflows slagen met fictieve gegevens.
- De 63 wedstrijden, 32 voorspellingen en bestaande toernooi-/puntentellinggegevens hebben dezelfde fingerprints vóór en na de wijziging. De beveiligingsadviseurs zijn ongewijzigd (19 INFO, 16 bestaande definerwaarschuwingen en 1 bestaande wachtwoordbeschermingswaarschuwing).
