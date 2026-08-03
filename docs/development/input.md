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

- **Touch** would buffer a jump in `Main._input`. A hit test suppresses that.
- **Desktop mouse never reaches `Main._input`'s jump path at all.** It goes via
  `ui_accept`, which `player.gd` polls, so a hit test suppresses nothing on its own.
  Worse, `BaseButton` emits `pressed` on mouse-**up** by default, so the jump already
  fired on mouse-**down** a frame before the pause screen appeared. Fixed by
  `Input.action_release(&"ui_accept")` in `Main._input`, which lands in time because
  `_input` runs during event flush, before this frame's `_physics_process`.

Measured on desktop 2026-08-03: a touch-only hit test did **not** fix this, which is
what exposed the two paths in the first place.

`Main.is_pause_button_press()` is the shared guard, and it covers both pointer kinds —
Android's emulated-mouse events go down the mouse branch, so a tap there is suppressed
even if it arrives in that form. The button is also `focus_mode = 0` so Space can't
activate it and jump at once.

**Any future `Control` that is live during play needs all three considerations.**
