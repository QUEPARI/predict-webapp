# Predict – algemene sportvoorspelwebapp

**Status:** eerste werkende, offline browserdemo + voorbereid databasemodel. **Geen productieklare app.**

## Wat werkt nu
- Responsieve interface, licht/donker thema, platform- en toernooioverzicht.
- Dart- en voetbalwedstrijdkaarten met scorevalidatie.
- Voorspellingen lokaal opslaan met `localStorage` (alleen op dit apparaat).
- Definitieve WK Darts 2027-puntentabel zichtbaar (1/3, 2/5, 3/7, 4/10, 6/15, 10/25, 15/40).
- Demo-extra-voorspellingen voor voetbal.
- Demo-privépoules en eigen overzicht.
- Conceptueel Supabase PostgreSQL-schema met standaard afgeschermde tabellen.

## Wat nog NIET werkt
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
