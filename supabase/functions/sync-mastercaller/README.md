# Mastercaller test integration

The handler authenticates either a verified Supabase admin JWT (getUser plus live role lookup) or the private Vault worker token. Gateway JWT checking is disabled only because the scheduled worker uses its own authentication. Anonymous requests never fetch a source or write a result.

Only HTTPS Mastercaller tournament result URLs are accepted; redirects are disabled, body sizes and timeouts bounded. Dutch URLs are normalised to the English results and bracket pages to avoid locale-dependent parsing. The source must identify PDC as organiser.

Automatic setup reads the bracket's round formats, positions and names and the results page's published planning and completed scores. Unknown or ambiguous times remain null; they do not open predictions. Current support is complete, power-of-two knockouts such as European Championship 2026. Seeded entry/byes and group phases fail closed until their source graphs are supported. There is no manual review queue or automatic fuzzy name matching.

Only current source-owned games are polled. Before play the interval is four hours; while a known start has passed without a result it is fifteen minutes. For TBA starts the event's first day begins the fifteen-minute fallback. Once all results exist, polling stops. A five-minute dispatcher checks which games are due; it does not fetch every five minutes.

On 19 October 2026, the specified European Championship page was readable in the browser, including 32 players, five rounds and 31 slots, with all match times TBA. Both pg_net and the actual Edge Function returned HTTP 418 from Mastercaller. The app shows this as a failed source connection, not as an empty successful import. Before creating a tournament the server fetches both source pages, so a failed source creates no partial tournament. No proxy, challenge bypass or fingerprint spoofing is implemented. Update timing after real matches has not been validated.
