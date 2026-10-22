# Mastercaller schedule recovery — 22 October 2026

The results page changes absolute dates to Today/Tomorrow/Yesterday near play. The parser previously omitted these fixtures; schema sync then replaced existing start times with null. All 31 match IDs and all 18 predictions remained present.

The parser resolves English and Dutch relative labels in Europe/Amsterdam using one reference instant per fetched results page. Unknown dates still fail completed-result validation; ambiguous/nonexistent DST times remain null.

Schema sync retains an existing scheduled start when the source has no usable time. Explicit new times still update planning; the existing closed-window latch prevents reopening elapsed deadlines. No prediction rows are written.

Recovered the 16 first-round start times on the original match IDs from the live source and added match audit entries. The 18 prediction rows retained their full-row fingerprint. Later rounds without known participants remain unknown.

Validation: parser regressions (relative labels, Amsterdam midnight, year boundaries, existing absolute dates, DST, source validation) and a rollback database test (missing time, expired deadline, unchanged predictions). Workflow runs parser regressions before sync.
