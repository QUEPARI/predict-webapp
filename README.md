# Predict – algemene sportvoorspelwebapp

**Status 16 oktober 2026:** JavaScript/HTML/CSS op GitHub Pages met Supabase-authenticatie, beheerdersfuncties, beveiligde voorspellingen, toernooi- en pouleklassementen en echte privépoules. Andere delen van de interface bevatten nog lokale demonstraties. **Geen volledig afgeronde productie-app.**

## Online privépoules
- Open **Mijn poules**, kies een gepubliceerd/actief toernooi en maak een poule aan. Je wordt automatisch toernooideelnemer en poulebeheerder.
- De beheerder maakt een uitnodigingscode voor een e-mailadres en deelt die zelf. Er wordt geen e-mail verzonden. De ontvanger heeft een bestaand Predict-account met dat bevestigde e-mailadres nodig.
- Codes zijn eenmalig, zeven dagen geldig en uitsluitend als SHA-256-hash opgeslagen. Een nieuwe code voor hetzelfde adres vervangt de oude. Alle openstaande codes kunnen worden ingetrokken.
- Leden kunnen vertrekken. De beheerder kan leden verwijderen of het beheer overdragen aan een bestaand lid. De eigenaar moet eerst overdragen voordat die vertrekt.
- Eén centrale voorspelling per wedstrijd telt in alle poules van dat toernooi, inclusief eerdere punten bij later toetreden. Verlaten/verwijderen wist de voorspellingen niet.
- Klassementen komen uit de bestaande beveiligde serverfunctie, met filters op poule en ronde. Systeembeheerders behouden hun bestaande leestoegang.

## Database en verificatie
De incrementele migratie `supabase/migrations/20261016133928_secure_private_pools.sql` is toegepast op project `sfcozzjcuppfypetbbzn`. RLS blijft actief; tabelmutaties en het lezen van uitnodigingsgegevens zijn geblokkeerd voor browserrollen. Publieke RPC's gebruiken invoker-rechten en roepen afgeschermde functies met expliciete identiteits- en eigendomscontroles aan.

**Let op:** `supabase/schema.sql` is het oorspronkelijke concept en wijkt af van de bestaande hosted database. Voer het niet uit op productie. De nieuwe migratie vereist die bestaande structuur; dit is nog geen volledige migratiegeschiedenis voor een lege installatie.

- `supabase/tests/private_pools.sql`: integratietest als databasebeheerder; fictieve gebruikers en wedstrijden uitsluitend binnen een transactie met rollback. Controleert RLS, uitnodigingen, ledenbeheer, historische punten, individuele deadline en 6–4 versus 6–3 = 1 punt.
- `tests/pools-ui.cjs`: Playwright-browsertest met mockbackend. Voer uit met `node tests/pools-ui.cjs` als Playwright en een browser beschikbaar zijn; stel eventueel `PLAYWRIGHT_CHANNEL=msedge` in.
- Volledige testresultaten, beperkingen en vervolgstappen: [privépoule-mijlpaal](docs/private-pools-milestone.md).

Onderstaande beschrijving documenteert de **oorspronkelijke lokale demo**. De online functies hierboven vervangen de betreffende demostromen.

## Oorspronkelijke demo: beschikbare functies
- Responsieve interface, licht/donker thema, platform- en toernooioverzicht.
- Dart- en voetbalwedstrijdkaarten met scorevalidatie.
- Voorspellingen lokaal opslaan met `localStorage` (alleen op dit apparaat).
- Definitieve WK Darts 2027-puntentabel zichtbaar (1/3, 2/5, 3/7, 4/10, 6/15, 10/25, 15/40).
- Demo-extra-voorspellingen voor voetbal.
- Demo-privépoules en eigen overzicht.
- Conceptueel Supabase PostgreSQL-schema met standaard afgeschermde tabellen.

## Oorspronkelijke demo: beperkingen bij oplevering
- Geen echte accounts, uitnodigingen of meerdere gebruikers. De gegevens staan uitsluitend lokaal op het apparaat.
- Geen echte darts- of voetbalwedstrijden; alle voorbeeldwedstrijden zijn fictief.
- Geen DartsAPI/TheSportsDB-synchronisatie, echte scoring/klassementen, realtime startdetectie, auditverwerking of pushnotificaties.
- Geen productierijpe RLS-regels, database-RPC's en Edge Functions: het SQL-schema is een **basis**, en mag niet als volledige backend worden beschouwd.
- Aan de demo toegevoegde poules hebben nog geen lidmaatschapsbeheer of uitnodigingen.

## Lokaal bekijken
Open `index.html` in een browser. Als browserbeperkingen module-import vanuit `file://` verhinderen, start een statische server:

```sh
python3 -m http.server 8080
```

Open daarna `http://localhost:8080`. Er is geen npm-installatie vereist.

## GitHub Pages
Upload de bestanden naar een GitHub-repository en stel **Settings → Pages → Deploy from a branch → main / (root)** in. De statische demonstratie werkt onder een projectsubpad. Zet dit pas openbaar als je akkoord bent met een **demo zonder echte accounts**.

## Technische koers voor de volledige app
- Platform: React + TypeScript (in de productiefase), GitHub Pages, Supabase Auth + PostgreSQL + Edge Functions.
- Authenticatie alleen via uitnodigingen van zeven dagen.
- Sportonafhankelijke toernooien; privépoules zijn altijd gekoppeld aan één toernooi.
- Scoreverwerking via versiegebonden regels; API-uitkomsten eerst matchen, valideren en bij conflicten blokkeren.
- Darts: fixtures via DartsAPI, resultaten via `results/yesterday` en noodcorrecties.
- Voetbal: TheSportsDB nader valideren, daarna adapter integreren.
- Server-side bewaakte deadlines; geheimen uitsluitend als backend secrets.
- WK Darts 2027 blijft volgens de vastgelegde puntentabel en walk-over-/tiebreakregels werken.

## Bestanden
- `index.html`, `styles.css`, `app.js`: zelfstandig werkende browserdemo.
- `manifest.webmanifest`: basis-PWA-metadata, nog geen pushimplementatie.
- `supabase/schema.sql`: databasebasis. Niet productierijp zonder aanvullende RLS, procedures en tests.
- `docs/roadmap.md`: volledige vervolgbouw en afvinkcriteria.

**Geen API-sleutels, service_role keys of wachtwoorden in GitHub plaatsen.**
