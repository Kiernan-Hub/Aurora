# Input

Jump is the only input the game has, and it arrives by **two independent paths**. A
change verified on one can be completely broken on the other — that is not theoretical,
it has shipped twice.

## The two paths

**Keyboard / gamepad / desktop mouse** go the normal Godot way: `player.gd` polls
`Input.is_action_just_pressed("ui_accept")` in `_physics_process`.
`InputSetup.configure()` (`scripts/systems/input_setup.gd`, called first thing in
`Main._ready()`) adds a left-mouse-button binding to that built-in action. `InputSetup`
guards with a `static var has_configured`, so a `reload_current_scene()` restart can
neither re-trigger nor lose it.

**Touch is a separate path and does not go through the action at all.** `Main._input`
(`scripts/main.gd`) calls `Player.buffer_jump()` directly on a touch press, setting the
same jump-buffer timer the action path sets. Only the delivery differs; the coyote/buffer
gate is shared.

## Why touch bypasses the action

Measured on device 2026-08-02 (Galaxy S21, Godot 4.7, `adb logcat`). A tap produced
correctly-formed touch **and** emulated-mouse events, and `emulate_mouse_from_touch` was
confirmed `true` on device — but:

- `ui_accept` **never** produced a `just_pressed` edge inside `_physics_process`.
- **No pointer event of any kind** ever reached `_unhandled_input` — not touches, not
  the emulated mouse buttons, not motion. An earlier fix lived there and never fired.

Root cause of either gap was never isolated further. Treat routing touch through an
`Input` action on Android as unreliable in general, not just as this one bug's fix.

The touch handler deliberately does **not** call `set_input_as_handled()`: nothing
downstream needs suppressing during play, and leaving the event alone keeps every GUI
path exactly as it was.

## Desktop testing structurally cannot validate mobile input

A real mouse click never exercises the touch path, and the emulated-mouse path that
*does* exist on Android behaves differently there than the direct polling desktop relies
on. Any input change needs an on-device check: re-export to `./aura.apk`, `adb install -r
aura.apk`, tap Start, then tap during play. If a tap does nothing, `adb logcat -s godot:V`
while tapping is the next step.

**No headless gate covers input.** Every harness drives `ui_accept` synthetically via
`Input.action_press`, so they exercise the *consumer* of input, never its delivery. A
platform input path can be completely dead with all gates green — that is exactly how
the 2026-08-02 Android bug shipped.

## Why there's no "is gameplay running" guard

`Main` uses the default `process_mode`, so `_input` does not fire while `GameManager`
holds `get_tree().paused` on the start, pause and death screens. A menu tap cannot leak
in as a jump, and no explicit check is needed.

## The pause button is the one exception

It is only visible while the game is running — i.e. exactly when input is live — so
paused-ness cannot cover it. It leaks a jump through **both** paths, for **different**
reasons, and a fix covering only one looks like it works:

- **Touch** would buffer a jump in `Main._input`. A hit test suppresses that, and that
  is still how the touch half is fixed.
- **Desktop mouse never reaches `Main._input`'s jump path at all.** It goes via
  `ui_accept`, which `player.gd` polls, so a hit test suppresses nothing on its own.
  Worse, `BaseButton` emits `pressed` on mouse-**up** by default, so the jump already
  fired on mouse-**down** a frame before the pause screen appeared.

**`Input.action_release()` does not fix the desktop half, and cannot.** This file said
it did for one day. `is_action_just_pressed()` compares the press **frame stamp** and
does not re-check the pressed flag, so releasing an action in the same event flush as
its press leaves the edge intact. Measured 2026-08-03 against a verified control (press
alone → 1 jump): press+release before the same physics frame **still jumped**. The
user-visible symptom was the click both jumping *and* pausing.

**The desktop fix is that the pause button reports on `button_down`, not `pressed`**
(`game_manager.gd`). The pause then lands during event flush, before that frame's
physics, so the tree is already paused and `player.gd` never polls the action —
independent of any `Input` frame-stamp semantics. It also removes the entire
down-to-up window in which the game was still live under the pointer. Full log:
`docs/research/pause_jump.md`.

`action_release()` is still correct on the **START** and **RESUME** transitions, where
the press happened while the tree was paused on a menu — an earlier frame, so the stamp
is stale by the first gameplay frame. Only the same-flush case is affected.

`Main.is_pause_button_press()` remains the shared guard for the touch path, and covers
both pointer kinds — Android's emulated-mouse events go down the mouse branch. The
button is also `focus_mode = 0` so Space can't activate it and jump at once.

**Headless cannot test any of this.** Pointer events pushed with
`Input.parse_input_event()` update the action state but are never dispatched to
`_input` or to Controls (measured: the root viewport is 64×64 and `Main._input` never
ran), so a probe "verifying" the guard will pass while the real path is broken. The
transition *timing* is testable; the delivery is not.

**Any future `Control` that is live during play needs all three considerations.**
