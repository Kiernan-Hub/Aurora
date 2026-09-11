# Aurora audit evidence

See [the audit report](/Users/kjh/Documents/aura/docs/review/2026-09-09-aurora-audit.md) for findings and limitations.

- `night_1152_on/off.png` and `night_1440_on/off.png`: real Mobile-renderer captures with all three curtains enabled/disabled, full blend at elapsed=20 s.
- `bands_true_8_0.png`: green curtain alone, elapsed=8 s, normal parallax scenery.
- `bands_false_8_0.png`: the same frozen frame and curtain with the parallax scenery hidden to expose its placement.
- `audit.gd`: direct-method assertions and small initial gap sweep.
- `gaps.gd`: expanded 256-seed gap sweep.
- `visual.gd`: all-band on/off captures at two aspect ratios.
- `bands.gd`: individual-band contribution diagnostic. The normal-scenery series and the first green-only scenery-hidden pair were collected; the remaining scenery-hidden series was stopped when rendering stopped progressing.
- `lifecycle.gd`: native reset UI, pause, death, and completed-save reload reproductions.

These are throwaway audit probes, not shipping scripts or maintained gates. They use `res://` to load the project, and write evidence to `/private/tmp/aura-aurora-audit/`. Before rerunning any probe, create an isolated project copy, replace both SaveStore `user://save.dat` paths with temporary absolute paths in that copy, and use a writable `--log-file` path. Restore the two debug float defaults to `0.0` in the copy when testing shipping behavior. Do not run the state-changing probes against the player's live save.

Example, after preparing that isolated copy:

```sh
/Applications/Godot.app/Contents/MacOS/Godot \
  --log-file /private/tmp/aura-aurora-audit/engine.log \
  --headless --path /private/tmp/aura-aurora-audit/project \
  --script /Users/kjh/Documents/aura/art_source/audits/aurora-2026-09-09/gaps.gd
```

Omit `--headless` and add `--audio-driver Dummy` for the two visual probes and `lifecycle.gd`. They open a Godot window. `audit.gd` and `gaps.gd` run headless. The native captures used Godot 4.7, Mobile rendering, Metal, Apple M4; they do not establish Android GPU performance.
