# Startpagina, header en toernooipoules

17 oktober 2026.

## Navigatie

De algemene menubalk is verwijderd. Na inloggen en opnieuw laden begint de app op Mijn toernooien, met de bestaande eigen toernooikaarten. Daaronder staan Open toernooien: gepubliceerde/actieve toernooien waaraan het account nog niet deelneemt. Na deelname verhuist een kaart naar het eigen overzicht. Resterende voorspellingen behouden hun bestaande opvallende status.

Het Predict-logo is een thuisknop. Rechts op dezelfde hoogte staat een ronde accountknop met de eerste letter van de gebruikersnaam, ook als de weergavenaam anders is. Alleen beheerders zien links daarvan een tandwiel voor Beheer. Account en beheer hebben een tikvlak van minimaal 44 pixels en duidelijke toegankelijke namen. Toernooi- en beheeronderdelen behouden hun eigen tabs.

Navigeren via de header controleert niet-opgeslagen voorspellingen, profiel-, schema- en poule-invoer. Bestaande bewaakte deadlines, gebruikersscheiding en opslagfeedback blijven behouden.

## Poules per toernooi

De toernooitab Poules toont alleen de eigen poules voor het geopende toernooi. Bij aanmaken is het toernooi vooraf vastgelegd en niet opnieuw te selecteren. De bestaande create_pool-, uitnodigings-, ledenbeheer-, vergelijkings- en klassementfuncties blijven de servercontroles uitvoeren.

Als een gebruiker via een poule automatisch deelnemer wordt, wordt de deelname op de toernooipagina direct ververst. Een geaccepteerde uitnodiging voor een ander toernooi opent diens Poules-tab. Bij nog niet opgeslagen voorspellingen wordt eerst gevraagd of de gebruiker die wil laten vervallen; bij weigeren blijft de invoer behouden en wordt vermeld waar de nieuwe poule staat. Codes worden niet lokaal opgeslagen.

## Schema

Publieke schema-kaarten gebruiken hun natuurlijke inhoudshoogte. De layout meet de benodigde hoogtes, ook wanneer de schematab verborgen is, en berekent daarop de trechterposities en verbindingen. Zo verdwijnt overbodige ruimte onder de datum zonder lange namen af te snijden. De winnaarsmarkering staat direct na de naam; beide scores hebben dezelfde rechteruitlijning. De bewerkbare naamvelden in beheer behouden hun bestaande ruimte.

## Verificatie

Acht browserregressies met fictieve gegevens: toernooien, poules, account/profiel, toernooibeheer, 48-spelersbracket, schemabeheer, accountbeheer en gebruikersnaamlogin. Gecontroleerd: geen dubbele toernooikaarten, accountinitiaal en beperkte beheerknop, geen algemene menubalk, invoerbescherming, poules bij twee toernooien, automatische deelname via pouleaanmaak, uitnodiging voor een ander toernooi, leden-/uitnodigingsacties en vergelijking/klassement. Schema gecontroleerd op 320/390/1280 pixels, met 47 zichtbare wedstrijden en 46 verbindingen, score-uitlijning en minder dan 10 pixels tussen datumonderkant en kaartrand. Mobiele screenshots visueel gecontroleerd.

Geen databasemigratie, gewijzigde rechten of wijzigingen van officiële wedstrijden uitgevoerd. De bestaande Supabase-RPC's en RLS blijven beslissend. Frontendversies zijn vernieuwd voor de browsercache. Na publicatie worden de live bestanden met main vergeleken en de mobiele inlog/herstelroute gecontroleerd zonder echte accounts te wijzigen.
