# Aura desktop stability audit

## November 22, 2026

Reviewed `play/next` from `556892b` using desktop runs and isolated saves.

| Finding | Fix and verification |
| --- | --- |
| Home and Restart could discard a completed Melt reward after a failed save. | Both return to the retry screen while a reward needs saving. The rendered test reproduced the old behavior, then confirmed the same rolled chest saves once and the suspended run resumes. |
| Buying a skater saved ownership and equipment in separate writes. | The purchase saves both with the wallet in one write. A failed purchase rolls all three back. The regression checks the write count, and a reopened scratch save kept the bought and equipped skater. |
| Desktop focus loss during test warmup could leave the suspend or mission test paused before it started. | Both tests now establish the active play state before the event being tested. |

A scratch save test blocked creation of the staging file. The original save stayed byte-for-byte
intact, both attempted writes rolled back, and the expected state reopened after the retry.
All 15 full gates and all 14 rendered UI cases passed. The Android APK built and its signature,
arm64 library, contents and CRCs passed desktop checks. A desktop run from the Android pack
spawned a spike with the collision signal connected.

Physical Android behavior and frame pacing remain unverified. Earlier desktop timing results
are in [the frame hitch notes](../research/frame_hitches_desktop.md).
