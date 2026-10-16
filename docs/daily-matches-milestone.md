# Compacte speeldagen en veilige tijdcorrecties

16 oktober 2026.

## Gedrag

- Voorspellingen toont de wedstrijden van één gekozen speeldag, gegroepeerd op de lokale datum van het apparaat, met daarnaast een rondekeuze. Vandaag wordt gekozen als er wedstrijden zijn, anders de eerstvolgende of laatst beschikbare dag. Wedstrijden zonder begintijd hebben een aparte keuze. Vrijstellingen worden uitgesloten.
- Open, gesloten, uitgestelde en afgeronde wedstrijden blijven op hun speeldag zichtbaar. Alleen open wedstrijden kunnen worden opgeslagen. Gesloten kaarten tonen spelers, eigen voorspelling, uitslag en punten.
- Namen staan eenmaal boven de scorevelden. Knoppen heten Opslaan, de openstatus heet Open; Gepland, de algemene deadline-uitleg, Vernieuwen en Toon alle wedstrijden zijn verwijderd uit Voorspellingen.
- Wedstrijden, dagkeuze en ronde-dropdown staan naast elkaar. Gegevens worden volledig opgehaald met serverpaginering; de gekozen dag/ronde wordt daarna gepagineerd. Er zijn geen lege vervolgpagina's door een open-filter. Vorige/Volgende en paginanummer zijn verborgen als alles past. Invoer blijft behouden bij pagina- en tabwissels.
- Toernooiwinnaar wordt na succesvol ophalen verborgen als geen vraag is ingesteld. Een ingestelde maar gesloten vraag blijft zichtbaar met de eigen voorspelling of Niet voorspeld. Een verbindingsfout wordt niet stilzwijgend als ontbrekende vraag behandeld.
- Home toont een opvallend oranje aantal nog te voorspellen wedstrijden, een groene bevestiging als alle open wedstrijden ingevuld zijn, en een neutrale melding als er geen open wedstrijden zijn.
- Publieke toernooikaarten, schema's en de winnaarsvraag gebruiken de tijdzone van het apparaat. De tijdstippen/deadlines blijven dezelfde UTC-momenten. Beheer, inclusief oudere datum-/startdialogen, blijft in Nederlandse tijd invoeren en behandelt zomer-/wintertijd met de bestaande gecontroleerde omzetting.
- Schema-kaarten zijn verlaagd van 144 naar 112 pixels; rijafstand van 160 naar 128 pixels. Wedstrijdnummers boven de kaarten zijn weg, noodzakelijke verwijzingen naar winnaars van onbekende wedstrijden blijven behouden. Trechterverbindingen volgen de nieuwe geometrie.
- Op mobiel wordt Beheer > Wedstrijden als compacte kaarten getoond, met spelers naast elkaar, ronde, tijd, status, uitslag en bestaande acties. Desktop houdt de tabel.

## Tijdcorrecties en beveiliging

Migratie `20261016215435_compact_daily_matches.sql` vervangt uitsluitend de bestaande private ko_edit-functie. Bij schedule wordt eerst gecontroleerd gesloten zoals voorheen. Daarna blijft uitsluitend een eerder open, bevestigde, toekomstige scheduled-wedstrijd zonder controlewaarschuwing open, mits ook de nieuwe tijd toekomstig is, het format onveranderd is en het toernooi gepubliceerd/actief is. Bestaande triggers en auditregistratie blijven actief. Handmatig gesloten, uitgestelde en verlopen wedstrijden worden nooit vanzelf heropend. Een formatwijziging met bestaande voorspellingen blijft verboden.

De apart door de gebruiker gevraagde heropening van 16 ET15-wedstrijden is eerder als gegevensactie uitgevoerd; deze release verandert geen bestaande wedstrijdrecords.

## Verificatie

- Lokale PostgreSQL/PGlite-regressies voor knock-outs, sjablonen, beheer, vergelijkingen, tellingen en tijdcorrecties: geslaagd.
- Nieuwe transactionele SQL-test zowel lokaal als hosted: toekomstige open tijdcorrectie, handmatig sluiten, verplaatsen naar verleden, natuurlijk verstreken deadline, formatwijziging met/zonder voorspellingen en onbevoegde deelnemer. Rollback; geen testgebruikers achtergebleven.
- Acht browsertests: toernooien, 48-spelersschema, schemabeheer, toernooibeheer, profiel/account, poules, accountbeheer en gebruikersnaamlogin. Alle geslaagd met fictieve gegevens.
- Toernooitest gebruikt America/New_York: dezelfde UTC-tijd verschijnt lokaal, een wedstrijd na UTC-middernacht hoort nog bij de juiste lokale vorige dag. Dagfilter, gesloten/afgeronde kaarten, afwezige winnaarsvraag, echte paginering en invoerbehoud zijn gecontroleerd.
- Beheerkaarten op mobiel en schema op 320/390/1280 pixels: geen pagina-overloop; screenshots visueel gecontroleerd. De bestaande ingeschakelde winnaarsvraag en automatische sluiting blijven getest.
- Hosted voor/na: 63 wedstrijden, 2 voorspellingen, 143 wedstrijdaudits; volledige wedstrijdfingerprint gelijk: a9a7d9c44dbb3b5b994c75ab374ddf3c. Geen officiële wedstrijdgegevens gewijzigd.
- Security advisors onveranderd: 17 bestaande informatieve RLS-meldingen, 16 bestaande publieke definer-meldingen, 1 bestaande Auth-wachtwoordmelding. Geen nieuw publiek endpoint of nieuwe rechten.

Bestandsversies zijn bijgewerkt voor de browsercache. De livecontrole vergelijkt gepubliceerde bestanden met main en opent de mobiele inlog/herstelpagina zonder echte accounts te wijzigen.
