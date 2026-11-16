# B skating refinement — 2026-11-16

The owner prefers B Long push and asked for a modest refinement informed by real elegant
skating. B is the style base; the later slow7.2s phrase was not approved.

## References actually inspected

- [Tima Miroshnichenko: indoor gliding footage](https://www.pexels.com/video/a-woman-gliding-on-an-ice-skating-rink-6015854/).
  Downloaded the public7s clip to temporary storage and inspected its sequence at3 frames/s.
  It shows shallow alternating curved glides, a quiet upper body and restrained foot movement,
  not an instructional straight-line stroking demonstration. Used for flow/posture only.
- [Pavel Danilyuk: figure-skating footage](https://www.pexels.com/video/a-woman-ice-skating-6539118/).
  Inspected the sequence at2 frames/s. It predominantly shows a camel spin with extended free
  leg. Used only to assess controlled extension and body stability; the spiral/spin pose is
  not copied into the running stroke and its timing is not treated as stride timing.
- [Natalya Khazova: Skating Skills 1, Stroking](https://www.styleskating.com/blog/skating-skills-1).
  Read the coach's written guidance: knee/ankle bend before pushing, weight over the skating
  foot, inside-edge push and free-leg extension. Its linked YouTube video was inaccessible.
- [Special Olympics Figure Skating Coaching Guide, Badge5, p36](https://media.specialolympics.org/resources/sports-essentials/coaching-guides/Sports-Essentials-Figure-Skating-Coaching-Guide-2021-v2.pdf).
  Read the forward-stroking guidance: balanced body, alternating weight transfer, side/back
  push and free-leg extension. This is coaching text, not a video that was watched.

YouTube, a Dailymotion tutorial and a Vimeo link could not be played/downloaded through the
available tools. No private browser cookies, sign-in or access-control workaround was used.
The downloaded public clips/contact sheets stay in `/tmp`; no third-party footage, images
or likenesses are included in the game's assets or committed preview.

## Earlier animation interpretation (superseded by owner correction)

The useful change for Aura is a visible push followed by a controlled one-blade glide and
low recovery, with less torso rocking. This is a side-view artistic approximation of a
three-dimensional side/back push; it cannot represent edge angles or full lateral balance.
The existing rest art also fixes the broad torso/arm silhouette. Achieving a fully upright
figure-skating silhouette would require new art or a broader body rig; that is out of scope.

Preserve B's sweep and near-cadence. Refined B takes2.3s per alternating stroke versus2.1s:
28% drive,38% extended glide,29% return,5% transfer. Free-leg reach continues5 source pixels
beyond B's backward endpoint during the glide. Recovery lift drops17→8 source pixels;
upper-body rocking drops0.03→0.015 radians, with small knee load/rise tied to push/glide.
These timings and amplitudes are animation choices, not measured values from the footage.

The opposite blade supports the phrase; the returning foot stays low and settles before
the next push. All five skins and MeltView use the same default. No physics, hitbox, player
speed, terrain, texture or effect-system changes. Existing mesh/submission counts remain.
The original B and prior attempts are retained as reference presets, not new game modes.

Preview: `art_source/ui_review/2026-11-16-refined-b.mp4`. The motion regression checks full
cycles, planted-blade contact, fixed bones, boundary continuity, low extended glide and
support/return ordering. Owner approval and phone trial remain pending.

## Earlier owner correction: overlap, no pause (superseded below)

The owner rejected the hold/settle interpretation: "one long fluid motion" with the next
push starting before the returning foot is all the way home. This correction takes priority
over the earlier timing interpretation. Default B - Continuous retains the4.6s full cycle,
flows directly from a1.33s push into a1.24s low return, and overlaps the next stroke by0.276s.
At the next push's start the returning foot is88% home. Cosine easing avoids the long
endpoint slowdowns of the previous quintic sweep. No explicit extension hold or settling
interval remains. Motion tests measure both foot velocities at the overlap and bound
near-still intervals. New preview: `art_source/ui_review/2026-11-16-continuous-handoff.mp4`.

## Latest owner correction: quicker push, knee up, plant and switch

The owner clarified that the backward motion needs a faster single accelerating sweep,
then a visible knee lift during the return, with the next leg starting right as the foot
plants. This supersedes the previous low-recovery /88%-home overlap interpretation.
Current default B - Push and recover keeps a2.3s alternating cadence, with a0.83s push and
1.47s recovery. A skewed cosine drive delays the peak speed into the stronger part of the
push. Recovery uses an18px envelope and a lifted-knee path, not the prior8px low shuffle.
Both legs meet at contact; no held extension or settling interval is added. These remain
animation choices guided by the owner's review, not measured motion-capture timings.
The regression measures96.2px/s peak drive against50.2px/s recovery, knee lift, planting at
the next push and a maximum4/120s near-still interval. Preview:
`art_source/ui_review/2026-11-16-push-and-recover.mp4`.

## Latest tuning: emphasize the push, reduce the knee lift

The owner wants a slightly faster overall stride, the backward sweep quicker than the slow
return, and a modest knee lift. Default B - Quick push now takes2.0s per alternating stroke:
0.60s accelerating push and1.40s return. The recovery envelope is12px instead of18px.
Planting still coincides with the next push, without a settling pause. Measured peak speeds
are132.7px/s backward and52.7px/s on recovery. No new rig path or gameplay system was added;
only the existing timing/lift constants changed. Preview:
`art_source/ui_review/2026-11-16-quick-push.mp4`.

## Latest cadence request: halve the time between strokes

The owner explicitly requested half the time between strokes. One alternating stroke is
now1.0s instead of2.0s:0.30s backward push,0.70s return, with the same12px lift envelope
and no pause at planting. The full two-leg cycle is2.0s. Only the cycle duration changed
in gameplay code. New preview: `art_source/ui_review/2026-11-16-double-cadence.mp4`.
