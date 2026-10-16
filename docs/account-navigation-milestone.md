# Accountnavigatie en rustige header

16 oktober 2026, vervolg op compacte rondes.

- Het gebruikerslabel Profiel heet nu Account; de bestaande interne tab-id blijft compatibel met opgeslagen navigatie.
- Header bevat alleen Predict-huisstijl. ONLINE, de account-/roltekst, themawissel en Uitloggen zijn daar verwijderd.
- Account toont de gebruikersnaam en weergavenaam, Licht/Donker/Systeeminstelling met opslagbevestiging, eigen voorspellingen en Uitloggen.
- Uitloggen gebruikt de bestaande Supabase-signOut-aanroep. Een netwerk- of servicefout verschijnt bij de knop; opnieuw proberen blijft mogelijk. De accountweergave verdwijnt na succesvol uitloggen.
- Mobiele menupositie en CSS zijn ongewijzigd: de gebruiker bevestigde dat deze na verversen al juist waren. Versieparameters op de hoofdbestanden en accountmodule laten browsers de bijgewerkte bestanden ophalen.
- Geen migraties, gewijzigde beveiligingsregels of mutaties van officiële wedstrijden. Accountvoorkeuren gebruiken de bestaande opslagroute.

## Controle

Browsertests met fictieve gegevens voor Account, gebruikersnaamlogin, toernooien, toernooibeheer, accountbeheer en poules. Accounttest omvat licht/donker/systeem, opslaan en opnieuw laden, bewaarde invoer bij fouten, niet-opgeslagen wijzigingen, eigen voorspellingen en accountwissel na uitloggen. Ook een mislukte uitlogpoging en herstel zijn gecontroleerd. Mobiele screenshot visueel gecontroleerd: geen accountknoppen of ONLINE in de header.

De testservers accepteren versieparameters zodat dezelfde bestandsverwijzingen als op GitHub Pages worden gebruikt. Een live controle vergelijkt de gepubliceerde bestanden met de samengevoegde versie en controleert het mobiele inlogscherm zonder echte accounts of gegevens te wijzigen.
