# Directe poule-uitnodigingen en verwijderen — 22 oktober 2026

Poulebeheerders zoeken vanaf drie tekens naar maximaal drie gebruikersnamen en moeten een resultaat selecteren. Wijzigen van de invoer wist de selectie. Bestaande leden en gebruikers met een geldige openstaande uitnodiging worden uitgesloten. Verouderde zoekantwoorden worden genegeerd. De uitnodiging gebruikt de geselecteerde account-ID.

De ontvanger accepteert of weigert via toernooi > Poules. Ook de introductie voor spelers die nog niet deelnemen heeft een Poules-knop. Acceptatie voegt de gebruiker aan zowel de poule als de centrale toernooideelname toe. Uitnodigingen blijven zeven dagen geldig. Bestaande openstaande poulecodes zijn waar mogelijk aan het bestaande account gekoppeld. Er worden geen nieuwe poulecodes meer aangemaakt; de afzonderlijke accountactivatie blijft intact.

Eigenaren kunnen hun poule verwijderen; admin en super_admin zien ook poules van andere eigenaren en kunnen die verwijderen. De interface vraagt bevestiging. Alleen pouleleden en bijbehorende uitnodigingen worden via de bestaande foreign keys verwijderd. Centrale deelname en voorspellingen blijven bestaan.

De nieuwe publieke RPC's zijn SECURITY INVOKER; de beperkte geprivilegieerde implementaties staan in predict_private en controleren auth.uid(). Browserrollen hebben geen directe toegang tot uitnodigingsrijen en krijgen geen recht om poules of leden rechtstreeks te muteren. Mutaties vergrendelen eerst de poule en dan de uitnodiging.

## Validatie

- supabase/tests/pool_direct_invitations.sql: geslaagd op de hosted database; tijdelijke gebruikers, een tijdelijk toernooi en alle testmutaties zijn teruggedraaid. Test onder andere zoekgrens, maximaal drie resultaten, uitsluiten leden/pending uitnodigingen, duplicaten, verkeerde ontvanger, accepteren, weigeren, hergebruik, intrekken, verlopen, buitenstaander/lid zonder verwijderrecht, eigenaar/admin/super_admin met verwijderrecht en cascade.
- tests/pool-direct-invitations-dom.cjs: geslaagd met jsdom 27.0.1. Test de werkelijke DOM-functies voor verplichte selectie, wissen van selectie, foutafhandeling, opnieuw proberen, oude zoekantwoorden, escaping, accepteren/weigeren, verwijderbevestiging en de introductieknop voor niet-deelnemers.
- node --check voor gewijzigde JavaScript-bestanden en git diff --check: geslaagd.
- Geen visuele mobiele browsercontrole: browserdownloads in de uitvoeromgeving mislukten. Geen volledige browserlogin met bestaande accounts uitgevoerd.
- Security Advisor: bestaande meldingen over afgeschermde tabellen zonder RLS-policies, oudere publieke SECURITY DEFINER-functies en uitgeschakelde leaked-password-protection. Nieuwe publieke RPC's gebruiken invoker-rechten. Zie https://supabase.com/docs/guides/database/database-linter en https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection.

Migratie: 20261022173644_pool_direct_invitations, toegepast op het bestaande project.
