undefined
## Process-session verification policy

A cold process performs one silent online verification when a stored license exists. A successful verification authorizes the process until the subscription deadline derived from signed server time and monotonic elapsed time. There is no 60/120-second refresh loop. Background/foreground transitions shorter than 30 minutes preserve authorization; a return after 30 minutes disables protected behavior and performs one silent recheck. The activation window is user-invoked by three screen taps and is never presented by a silent verification failure.

This policy means suspension or revocation is enforced on the next cold launch or recheck after a 30-minute background absence. Subscription expiration is still enforced while the process remains open without trusting the device wall clock.
