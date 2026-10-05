#!/usr/bin/env bash
#
# check.sh — the fast validation runner.
#
# Runs the five fast headless gates plus the export-content check in sequence and
# exits non-zero if any of them failed. Quiet on PASS (one line each); on FAIL it
# prints that gate's full output, because the gates' own failure text is the
# diagnosis. Every gate runs under a time limit, so a harness left paused fails
# instead of hanging the runner.
#
#   ./scripts/check.sh              the fast six (~75s)
#   ./scripts/check.sh --full       the fast six, then every asserting physics gate (~3 min)
#   ./scripts/check.sh -v           print every gate's output, pass or fail
#   GODOT=/path/to/Godot ./scripts/check.sh
#
# Three tiers exist; see docs/development/debugging.md:
#
#   fast         shipping_values, biome_schedule, terrain_invariant, lake_suppression,
#                regression, export_content -- before every commit
#   physics      air_moves, aurora_calm, chasm, freeze_search (+ slam, double),
#   (--full)     floor_flicker, freeze_replay -- after the changes debugging.md lists.
#                camera_shake_probe is left out: it prints metrics and cannot fail.
#   visual       sky_layer_check, ice_look_capture, biome_contact_sheet
#                — MUST run WITHOUT --headless, they diff or save rendered frames,
#                  so they can never join a headless runner
#
# NOT run here, deliberately: project import (`--headless --editor --quit`). It is slow,
# needed only after adding a class_name, and this runner stays free of any command that
# CAN write to the project. (Import was measured not to rewrite project.godot; a
# project-setting SAVE is what strips the pins -- debugging.md has the measurements.)

set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Godot's own log goes to a temp file instead of user://logs under ~/Library. A sandboxed agent
# (Codex, 2026-09-27) can't write there, and Godot 4.7 then CRASHES at startup, with signal 11
# right after "Failed to open 'user://logs/...'", instead of running without a log.
GODOT_LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$GODOT_LOG_DIR"' EXIT

VERBOSE=0
FULL=0
for arg in "$@"; do
	case "$arg" in
		-v|--verbose) VERBOSE=1 ;;
		--full) FULL=1 ;;
		*) echo "usage: $(basename "$0") [-v] [--full]" >&2; exit 2 ;;
	esac
done

if [[ ! -x "$GODOT" ]]; then
	echo "check.sh: Godot not found at $GODOT (set GODOT=/path/to/Godot)" >&2
	exit 2
fi

# name : script : extra args after `--`
# terrain_invariant's seeds/to are NOT tunable here: the coin-density band is
# calibrated for the full 1758-slot sample, so a shortened run FAILs meaninglessly.
GATES=(
	"shipping_values|shipping_values_check.gd|"
	"biome_schedule|biome_schedule_check.gd|"
	"terrain_invariant|terrain_invariant_check.gd|--seeds=8 --to=300000"
	"lake_suppression|lake_suppression_probe.gd|"
	"regression|regression_probe.gd|"
)

# --full only. Run with --fixed-fps 60, which gives the same results as real time, uncapped.
FREEZE_SEARCH_ARGS="--seed=941462462 --warp=175000 --to=178000 --phases=8 --phasestep=0.25 --scan=1 --trialframes=500 --rebase=1"
FULL_GATES=(
	"air_moves|air_move_probe.gd|"
	"aurora_calm|aurora_calm_probe.gd|"
	"chasm|chasm_probe.gd|--seed=683407368 --chasms=3 --phases=4"
	"freeze_search|freeze_search.gd|$FREEZE_SEARCH_ARGS"
	"freeze_slam|freeze_search.gd|$FREEZE_SEARCH_ARGS --slam=1"
	"freeze_double|freeze_search.gd|$FREEZE_SEARCH_ARGS --double=1"
	"floor_flicker|floor_flicker_probe.gd|--frames=20000"
	"freeze_replay|freeze_replay_runner.gd|--seed=941462462 --frames=60000 --runs=1"
)
GATE_TIME_LIMIT="${GATE_TIME_LIMIT:-900}"

# Paths that must never reach a player's device. HARDCODED on purpose rather than
# read out of export_presets.cfg's exclude_filter: deriving them from the preset
# would make the check agree with the preset by construction, including when
# someone deletes a line from it, which is the exact regression worth catching.
#
# THE THREE experiments/ PATHS NO LONGER EXIST (deleted 2026-09-03 with the abandoned
# procedural-background line), so today res://scripts/debug and res://art_source can trip this.
# They stay listed, and stay in the preset's exclude_filter, as a standing rule about
# where throwaway work goes: recreate any of them and it is excluded and checked from
# the first commit, rather than needing someone to remember both files.
FORBIDDEN=(
	"res://scripts/debug"
	# ~96 MiB of source and reference art. Kept out by art_source/.gdignore, not by the preset:
	# without that file it imports and ships (measured: a 7 MB pack became 67 MB).
	"res://art_source"
	"res://scripts/experiments"
	"res://scenes/experiments"
	"res://assets/textures/experiments"
)

# Exports a pack and fails if any FORBIDDEN path survived export_presets.cfg's
# exclude_filter. ~2s. Sets `output` and returns non-zero on failure, matching the
# gate loop's contract.
#
# The search is an unanchored byte search over the whole pack, not a parse of its
# path table: a merged `strings` line or a path embedded inside a resource still
# trips it. That direction is deliberate -- this check errs toward failing, and a
# false positive is a five-minute look, where a false pass ships 636 KB of probes.
# No shipping script embeds these literals today (verified 2026-08-25); if one ever
# legitimately needs to, that is the moment to switch to a real path-table parse.
run_export_check() {
	local pack status entries
	# Checked by name as well as through the pack below, so the failure names the cause.
	if [[ ! -f "$PROJECT_DIR/art_source/.gdignore" ]]; then
		output="EXPORT_CONTENT_CHECK FAIL  art_source/.gdignore is missing -- source art would ship."
		return 1
	fi
	pack="$(mktemp -d)/content_check.pck"

	output="$("$GODOT" --headless --log-file "$GODOT_LOG_DIR/godot.log" --path "$PROJECT_DIR" \
		--export-pack Android "$pack" 2>&1)"
	status=$?

	if [[ $status -ne 0 || ! -f "$pack" ]]; then
		output="$output"$'\n''EXPORT FAILED -- export templates missing, or the '
		output="$output""Android preset is broken."
		rm -rf "$(dirname "$pack")"
		return 1
	fi

	local hits=()
	for path in "${FORBIDDEN[@]}"; do
		if strings -a "$pack" | grep -qF "$path"; then
			hits+=("$path")
		fi
	done

	entries="$(strings -a "$pack" | grep -cF 'res://')"
	rm -rf "$(dirname "$pack")"

	if [[ ${#hits[@]} -ne 0 ]]; then
		output="EXPORT_CONTENT_CHECK FAIL  ${#hits[@]} forbidden path(s) in the pack:"
		for path in "${hits[@]}"; do
			output="$output"$'\n'"    $path"
		done
		output="$output"$'\n'"  Check exclude_filter in export_presets.cfg."
		return 1
	fi

	output="EXPORT_CONTENT_CHECK PASS  $entries resources, none forbidden"
	return 0
}

failed=()
ran=0

# Prints one result line, and the captured `output` if it failed or -v is on.
report() {
	local name="$1" status="$2" elapsed="$3"
	ran=$((ran + 1))
	printf '%-18s ' "$name"
	if [[ $status -eq 0 ]]; then
		printf 'PASS  %3ds\n' "$elapsed"
		[[ $VERBOSE -eq 1 ]] && printf '%s\n\n' "$output"
	else
		printf 'FAIL  %3ds  (exit %d)\n' "$elapsed" "$status"
		printf '%s\n\n' "$output"
		failed+=("$name")
	fi
	return 0
}

# Runs one gate script under GATE_TIME_LIMIT, sets `output` and returns its status. Extra
# Godot flags (--fixed-fps) follow the script and its args.
run_gate() {
	local script="$1" args="$2"
	shift 2
	local out="$GODOT_LOG_DIR/gate.out"
	# shellcheck disable=SC2086 -- args is a deliberately word-split flag list
	"$GODOT" --headless "$@" --log-file "$GODOT_LOG_DIR/godot.log" --path "$PROJECT_DIR" \
		--script "res://scripts/debug/$script" -- $args > "$out" 2>&1 &
	local pid=$! waited=0
	while kill -0 "$pid" 2>/dev/null; do
		if [[ $waited -ge $GATE_TIME_LIMIT ]]; then
			kill "$pid" 2>/dev/null
			wait "$pid" 2>/dev/null
			output="$(cat "$out")"$'\n'"TIMED OUT after ${GATE_TIME_LIMIT}s -- a paused or hung harness."
			return 124
		fi
		sleep 1
		waited=$((waited + 1))
	done
	wait "$pid"
	local status=$?
	output="$(cat "$out")"
	# Godot exits 0 when the --script itself fails to parse or load, so a gate that never ran
	# would read as PASS. Measured 2026-10-04 on aurora_calm_probe after a signature change.
	if [[ $status -eq 0 ]] && grep -qE 'Parse Error|Failed to load script' <<< "$output"; then
		status=1
	fi
	return $status
}

started_all=$SECONDS

for gate in "${GATES[@]}"; do
	IFS='|' read -r name script args <<< "$gate"
	started=$SECONDS
	run_gate "$script" "$args"
	report "$name" "$?" "$((SECONDS - started))"
done

started=$SECONDS
run_export_check
report "export_content" "$?" "$((SECONDS - started))"

if [[ $FULL -eq 1 ]]; then
	for gate in "${FULL_GATES[@]}"; do
		IFS='|' read -r name script args <<< "$gate"
		started=$SECONDS
		run_gate "$script" "$args" --fixed-fps 60
		report "$name" "$?" "$((SECONDS - started))"
	done
fi

total=$((SECONDS - started_all))

echo "----"
if [[ ${#failed[@]} -eq 0 ]]; then
	printf 'all %d gates PASS in %ds\n' "$ran" "$total"
	exit 0
fi

printf '%d of %d gates FAILED in %ds: %s\n' \
	"${#failed[@]}" "$ran" "$total" "${failed[*]}"
exit 1
