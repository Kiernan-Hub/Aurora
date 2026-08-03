# The pause button jumped as well as pausing (2026-08-03)

**Status: fixed.** Reported symptom, desktop mouse: *"when I press pause, it jumps"* —
and specifically it **paused AND jumped**, not one or the other.

## What was already in place, and why it looked fixed

A guard for this shipped earlier the same day: `Main.is_pause_button_press()` hit-tests
a pointer press against the pause button and, on a hit, calls
`Input.action_release(&"ui_accept")` before returning. `input.md` and the comment block
in `main.gd` both described that release as the desktop fix.

It is not, and the reasoning behind it was wrong in a way that reads as obviously
correct: `_input` genuinely does run during event flush, genuinely does land before that
frame's `_physics_process`, and the same `action_release()` trick genuinely does work on
the START and RESUME transitions. Every step of that argument is true. The conclusion
still does not follow.

## Root cause

`Input.is_action_just_pressed()` compares the action's **press frame stamp** against the
current frame. It does not re-check the pressed flag. So releasing an action in the same
event flush as its press leaves the just-pressed edge fully intact — the release moves
the pressed flag, not the stamp that `just_pressed` reads.

Timeline of a pause click under the old wiring:

| when | what |
|---|---|
| flush | mouse-DOWN sets `ui_accept` pressed, stamped with this frame |
| flush | `Main._input` hit-tests, calls `action_release` — **no effect on the stamp** |
| physics | `player.gd` polls `is_action_just_pressed` → **true** → jump |
| flush (later frame) | mouse-UP → `BaseButton` emits `pressed` → `set_state(PAUSED)` |

Both halves of the report, in order: jump first, pause after.

Why START/RESUME were never affected: there the press happens while the tree is paused
on a menu, i.e. on an *earlier* frame, so the stamp is already stale by the first
gameplay frame. The release call is redundant there rather than load-bearing.

## Measurement

Two facts had to be separated, because the first one poisons any attempt to measure the
second.

**1. Headless cannot see the input path at all.** A probe that pushed a real
`InputEventMouseButton` through `Input.parse_input_event()` at the button's centre
reported the bug — but for the wrong reason. Instrumenting it:

- `root.size` is `(64, 64)`; the button's rect is `(8,8)–(48,40)`, so the hit test was
  fine, and `is_pause_button_press()` returned `true` in isolation.
- After `parse_input_event()` + `flush_buffered_events()`, `ui_accept` was **still
  pressed** — so `Main._input` never ran. Pointer events update Input singleton state
  but are not dispatched to `_input` or to Controls in a headless `--script` run. The
  Button never emitted `pressed` either (`reached_pause=false`).

That probe was deleted rather than kept. It would have "passed" against a completely
broken delivery path — precisely the failure mode `CLAUDE.md` warns about for the 18
archived probes.

**2. The engine semantics, which headless *can* test**, because it is Input-singleton
behaviour plus the real `Player` consumer, no delivery involved. A control case is
mandatory here: an `action_press()` issued from script context is **not** visible to the
first awaited `physics_frame`, only the second, so a too-short measurement window
reports zero jumps for everything and looks like a pass.

```
CONTROL  press_only                  jumps=1   (verified the window is right)
TEST     press_then_release_together jumps=1   <- release did not cancel the edge
```

**3. The fix, A/B'd** on transition timing (the half that is testable):

```
OLD  pause on pointer-UP   (game live across the click) jumps=1  reproduces the bug
NEW  pause on pointer-DOWN (same flush as the press)    jumps=0  no jump
```

## The fix

`game_manager.gd` connects the pause button's **`button_down`** instead of `pressed`.
The pause then lands during event flush, before that frame's physics, so
`get_tree().paused` is already true and `player.gd` never polls the action. This does
not depend on any `Input` frame-stamp behaviour, and it removes the whole down-to-up
window during which the game was still live under the pointer.

The hit-test guard in `Main._input` **stays** — it is what stops the separate touch path
from calling `Player.buffer_jump()` directly, and that half was always working.

## Traps for anyone returning here

- **Never measure a suppression fix without a control that fires.** Both wrong readings
  in this investigation (`jumps=0` on a press that should have jumped, and an
  `INCONCLUSIVE` A/B) were measurement-window artifacts, not behaviour.
- **`Input.action_release()` is not a general "cancel this input" call.** It works only
  when the press is from an earlier frame.
- **A headless probe cannot verify anything about input delivery.** If a probe claims to,
  check whether `_input` actually ran before believing it.
- A fix whose supporting argument is entirely true can still be the wrong fix.
