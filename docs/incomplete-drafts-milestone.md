# Onvolledige knock-outconcepten

## Gebruikersflow
Beheer → Toernooien heeft een duidelijke knop Nieuw toernooi. Deze opent het bestaande aanmaakformulier in Schema’s, ook wanneer het scherm nog geladen wordt. De naam krijgt focus. Na aanmaken klapt het aanmaakformulier dicht en verschijnt het nieuwe concept.

Naam, sport, soort deelnemers, aantal en een geldige standaardpuntenmethode blijven nodig om het schema te bepalen. Startdatum, first-to en beide puntvelden per ronde mogen leeg blijven. Deelnemersnamen blijven later in het schema in te vullen. Het concept heeft gesloten wedstrijden en is onzichtbaar voor gewone gebruikers.

Ronde-instellingen en punten is een onderdeel van het conceptschema: startdatum, puntenmethode, spelvorm/first-to per ronde en punten zijn tussentijds op te slaan. Gedeeltelijke waarden blijven behouden, inclusief het verschil tussen nul en onbekend. Fouten behouden invoer; succes toont een lokale melding. Publicatie toont een lijst met ontbrekende instellingen. Individuele speeltijden blijven later in te vullen; publicatie opent uitsluitend al complete toekomstige wedstrijden.

## Database en beveiliging
Migratie 20261017095736_knockout_incomplete_drafts.sql is toegepast. Round_scoring kan onbekende punten bewaren, maar de aanvullende trigger staat dit alleen bij een bestaand knock-outconcept toe en vergrendelt de toernooirij tegen gelijktijdig publiceren. Andere toernooien en gepubliceerde spellen behouden volledige punten. Het bestaande beheer- en lockmechanisme blijft werkzaam.

Create accepteert ontbrekende start/first-to/punten. Edit krijgt de actie rounds, uitsluitend voor concepten zonder wedstrijdvoorspellingen, winnaarsvoorspellingen, gestarte wedstrijden of uitslagen. Geldige sporten, deelnemersaantallen, unieke namen, puntenbereik, first-to en rondetoewijzing blijven gevalideerd. De bestaande tijdelijke, transactiebonden beheerpermit maakt gecontroleerde conceptwijzigingen mogelijk en wordt weer verwijderd. Auditregistratie blijft bestaan.

Een interne helper verzamelt ontbrekende velden. De bestaande status-trigger weigert publicatie/activatie bij ontbrekende namen, toernooistart, puntenmethode, punten of first-to. Daardoor zijn ook de oude publicatiefunctie en hervatten beschermd. Een sjabloon bewaren vereist nog steeds een volledig format.

## Verificatie
- Volledige lokale PGlite-regressiesuite plus nieuwe tests voor onvolledige creatie, gedeeltelijk opslaan, nul versus onbekend, spelplannen zonder first-to in concept, fout bij vreemde ronde, rolbeveiliging, verborgen concept, beide publicatieroutes, aanvullen/publiceren en blijvende vergrendeling.
- Dezelfde nieuwe SQL-test op het gekoppelde project met fictieve accounts en transactie-rollback. Geen testaccounts achtergebleven.
- Browser: directe knop Nieuw toernooi, focus/open formulier, lege conceptvelden, correcte null-payload, gedeeltelijk opslaan en herladen, fout met behoud van invoer, aanvullen en de bestaande schema-/uitslag-/sjabloonflows. Beheer, toernooien en poules blijven getest met fictieve gegevens.
- Voor/na controle: 63 wedstrijden en 32 voorspellingen; identieke wedstrijd-, voorspellings- en toernooifingerprints. Bestaande sportgegevens niet gewijzigd.
- Security-advisors ongewijzigd: 19 informatieve privétabellen zonder directe policies, 16 bestaande definerwaarschuwingen en 1 bestaande wachtwoordbeschermingswaarschuwing. Nieuwe interne helpers zijn niet direct uitvoerbaar door anon/authenticated.
