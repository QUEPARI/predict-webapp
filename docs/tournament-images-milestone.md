# Toernooikaarten en afbeeldingen

De startpagina gebruikt compacte beeldkaarten zoals Mijn spellen in de referentie. Eigen en open toernooien blijven afzonderlijk; deelname, tellingen en spelregels blijven gelijk. Account/themakeuze en centrale accentkleur blijven beschikbaar. Donkere modus heeft een zwarte pagina en antraciete kaarten.

In Toernooibeheer kunnen beheerders JPG/PNG/WebP kiezen (maximaal 10 MB). De browser decodeert/verkleint tot maximaal 1000 px en encodeert als WebP. Storage accepteert alleen WebP tot 2 MB. Voortgang, fouten, succes, voorbeeld en verwijderen zijn zichtbaar. Zonder afbeelding verschijnt een trofee.

Migratie 20261017082846 maakt de openbare bucket tournament-images met strikte beheerpolicies. Bestandsnamen zijn beperkt tot een bestaand toernooi-ID/cover.webp. De rolcontrole leest de bestaande user_roles-tabel, niet gebruikersmetadata. Anonieme bezoekers en gewone gebruikers krijgen geen schrijfrechten. Geen wijzigingen aan wedstrijden, voorspellingen, scores of deadlines.

Verificatie: fictieve browsergegevens voor upload, vervanging, uploadfout met behouden selectie en verwijderen; bestaande tournament- en managementroutes; contrast/save/reset van centrale accentkleur. Kaartweergave gecontroleerd op 320/390/1280 px. Hosted SQL-rollbacktest voor admin insert/update, ongeldige paden en geweigerde gebruikersupload. Security advisors gecontroleerd.
