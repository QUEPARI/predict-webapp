# Spelkaarten, vierkante uitsnede en pouleklassementen

## Gedrag
De naam in het logo is PREDICT., inclusief punt. Mijn spellen en Beschikbare spellen vervangen de eerdere startpaginatitels. De eerste sectie heeft 14 px extra ruimte bovenaan.

Beheer → Toernooien toont dezelfde vierkante beeldkaarten met spelnaam, publicatiestatus en openstaande acties (namen, wedstrijdgegevens, uitslagen). Een kaart opent de bestaande beheerfuncties; teruggaan met niet-opgeslagen wijzigingen vraagt bevestiging.

De afbeeldingkiezer toont een vierkant canvas. Verschuiven met vinger/muis, zoomen en horizontale/verticale schuifjes bepalen de uitsnede. De afbeelding wordt via een HTML-afbeelding gedecodeerd en naar JPEG geschreven, maximaal 1000 × 1000 px / 2 MB. Safari hoeft geen WebP te kunnen coderen en createImageBitmap is niet nodig. Uploadfouten behouden de selectie en uitsnede. Bestandtypes JPG/PNG/WebP tot 10 MB blijven de invoergrens. Corrupte bestanden geven een foutmelding; opslaan blijft dan geblokkeerd.

Nieuwe opslag: tournament-images/<toernooi-id>/cover.jpg; oude cover.webp-bestanden blijven een terugval. Verwijderen verwijdert beide. Alleen beheerders en bestaande toernooi-ID's zijn toegestaan. Migratie **20261017090302_jpeg_tournament_images.sql** is toegepast en voegt uitsluitend JPEG aan de bucket toe en het exacte JPEG-pad aan de bestaande rolcontrole. Geen wijzigingen aan spelregels, wedstrijden of voorspellingen.

Klassement toont het algemene toernooiklassement plus de eigen poules van dat toernooi. Pouleklassementen laden pas bij uitklappen, met lege toestand en lokale foutmelding/herhalen. De bestaande membership-RLS en get_tournament_leaderboard-RPC bewaken de toegang. De bestaande vergelijking via get_pool_prediction_comparison blijft alleen gesloten deadlines/werkelijk gestarte wedstrijden onthullen.

## Verificatie
- Lokale PGlite-test: JPEG/WebP-bucket, admin insert/read/update/delete; weigering van vreemde paden, onbekend toernooi, gewone gebruiker en anonieme upload.
- Hosted rollbacktest: bucketconfiguratie, admin JPEG insert/update, geen metadata/uploadautoriteit voor gewone gebruikers en geen anonieme helpertoegang. Geen fysieke testupload naar echte toernooien.
- Browsercontrole met kunstmatige rood/groen/blauw-afbeelding: vierkante JPEG-uitvoer, gekozen blauwe pixels, schuifjes, zoom, slepen en corrupte invoer. Expliciet getest zonder createImageBitmap en zonder WebP-encoder. Browserautomatisering gebruikt Edge; geen fysieke iPhone-test geclaimd.
- Beheerflow: opslaan, uploadfout met behouden selectie, verwijderen, kaarten/teruggaan en bestaande schema/metadata/winnaarsvraag/verwijdering.
- Pouleflow: alleen eigen poules van geselecteerd toernooi, meerdere poules, lazy load, fout/herhalen, namen ontsnappen en vergelijking. Bestaande lidmaatschap-/uitnodigingsfuncties getest.
- Mobiele en desktopbreedtes 320/390/1280 px, logo en nieuwe sectietitels; bestaande account-, profiel-, themakleur- en inlogtests.
- Hosted controle vóór/na: 63 wedstrijden en 32 voorspellingen, ongewijzigde fingerprints 70ca58d09ae7d3133adffc57d1a78898 / 8f4234654deb29b4b8e0afe3d2a64863. Geen testobjecten achtergebleven.
- Security-advisors ongewijzigd: 19 informatieve afgesloten privétabellen, 16 bestaande definerwaarschuwingen, 1 bestaande wachtwoordbeschermingswaarschuwing.
