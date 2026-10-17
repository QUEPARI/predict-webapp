# Vandaag, open wedstrijden en compacte menu's

17 oktober 2026.

- Voorspellingen selecteert wedstrijden uit de gekozen ronde die op de lokale datum van vandaag vallen, ongeacht hun status, plus alle wedstrijden die volgens de bestaande voorwaarden openstaan om te voorspellen. Geen datumdropdown. Vrijstellingen blijven uitgesloten.
- Oude gesloten/afgeronde wedstrijden en toekomstige gesloten wedstrijden worden niet in Voorspellingen getoond, maar hun ingevulde uitslagen blijven onder Uitslagen bereikbaar over alle datums.
- Paginering volgt de zichtbare selectie. De selectie wordt bij een deadline en lokale middernacht opnieuw bepaald. Invoer blijft in dezelfde kaarten bewaard bij tab- en paginawissels.
- De hoofdmenu-optie Klassementen is verwijderd. Klassement binnen het toernooi en het afzonderlijke beheerscherm voor klassementen blijven bestaan. Een oude lokaal opgeslagen hoofdmenu-route naar klassementen valt terug op Home.
- Hoofdmenu en beheermenu hebben dezelfde tekstgrootte, regelhoogte en padding. Mobiel worden knoppen indien nodig over meerdere regels verdeeld; geen afgesneden opties of verplicht horizontaal scrollen.
- Geen database- of beveiligingswijzigingen; bestaande gegevens worden niet aangepast. Frontendversies bijgewerkt voor de browsercache.

Controle: toernooibrowsertest met America/New_York, vandaag met meerdere statussen, toekomstige open/gesloten wedstrijden, oude uitslagen, lokale middernacht, deadlines, paginering en invoerbehoud. Beheertest controleert op 320/390/1280 pixels dat alle hoofdmenuknoppen binnen het scherm staan en dat beide menu's dezelfde lettergrootte/padding gebruiken. Account- en poule-browserregressies behouden. Mobiele schermafbeelding visueel gecontroleerd; live bestandscontrole na publicatie.
