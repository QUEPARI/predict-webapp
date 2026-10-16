# Opslagstatus en rondeoverzicht

17 oktober 2026.

- De dubbele terugknop Toernooioverzicht is verwijderd; het hoofdmenu blijft de navigatieroute, inclusief de bestaande bescherming tegen verlies van onopgeslagen invoer.
- Datum-dropdown en datumfiltering zijn verwijderd. De bestaande rondekeuze filtert alle wedstrijden en alle ingevulde uitslagen van die ronde, ongeacht de datum. Paginering blijft gebaseerd op de daadwerkelijk getoonde wedstrijden/uitslagen.
- Na succesvolle opslag staat Opgeslagen op de knop. Bij opnieuw openen wordt de opgeslagen voorspelling herkend. Bij gewijzigde scores toont de knop Opslaan. Als de scores exact teruggezet worden naar de opgeslagen waarden, verschijnt Opgeslagen weer. De ongewijzigde opgeslagen knop is uitgeschakeld om dubbele opslag te voorkomen.
- Tijdens de aanvraag staat Opslaan… op de knop; Opgeslagen verschijnt pas bij succes. Foutmeldingen blijven naast de betreffende invoer zichtbaar en behouden de gewijzigde score. Opslagmeldingen en de tekst Nog geen voorspelling opgeslagen zijn verwijderd.
- Individuele deadlines, uitslagweergave, invoerbehoud bij tab/paginawissel en de tijdzoneweergave blijven behouden. Geen databasewijzigingen of wijzigingen van echte wedstrijden/voorspellingen uitgevoerd.
- Frontend-versies bijgewerkt zodat browsers de nieuwe bestanden ophalen.

Verificatie met fictieve gegevens: toernooibrowsertest met opslag/heropenen/wijzigen, fout en herstel, bewaarde andere invoer, rondekeuze, uitslagen over meerdere datums, paginering en deadlineverloop. Mobiele en desktopweergave gecontroleerd op 320/390/1280 pixels. Account- en beheerbrowserregressies slagen. Gepubliceerde bestanden worden na deployment met main vergeleken; de livecontrole wijzigt geen account of sportgegevens.
