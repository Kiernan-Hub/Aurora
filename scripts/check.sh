#!/usr/bin/env bash
#
# check.sh — the fast validation runner.
#
# Runs the four fast headless gates plus the export-content check in sequence and
# exits non-zero if any of them failed. Quiet on PASS (one line each); on FAIL it
# prints that gate's full output, because the gates' own failure text is the
# diagnosis.
#
#   ./scripts/check.sh              run all five
#   ./scripts/check.sh -v           print every gate's output, pass or fail
#   GODOT=/path/to/Godot ./scripts/check.sh
#
# This is the "before every commit" tier. Three tiers exist and this is only the
# first; see docs/development/debugging.md for the other two:
#
#   fast (here)  shipping_values, biome_schedule, terrain_invariant,
#                lake_suppression, export_content
#   physics      freeze-search, freeze-replay, floor-flicker, chasm, camera-shake,
#                air_move_probe, aurora_calm_probe
#                — run by hand after the changes debugging.md lists for each
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
case "${1:-}" in
	-v|--verbose) VERBOSE=1 ;;
	"") ;;
	*) echo "usage: $(basename "$0") [-v]" >&2; exit 2 ;;
esac

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
)

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

started_all=$SECONDS

for gate in "${GATES[@]}"; do
	IFS='|' read -r name script args <<< "$gate"
	started=$SECONDS
	# shellcheck disable=SC2086 -- args is a deliberately word-split flag list
	output="$("$GODOT" --headless --log-file "$GODOT_LOG_DIR/godot.log" --path "$PROJECT_DIR" \
		--script "res://scripts/debug/$script" -- $args 2>&1)"
	status=$?
	# Godot exits 0 when the --script itself fails to parse or load, so a gate that never ran
	# would read as PASS. Measured 2026-10-04 on aurora_calm_probe after a signature change.
	if [[ $status -eq 0 ]] && grep -qE 'Parse Error|Failed to load script' <<< "$output"; then
		status=1
	fi
	report "$name" "$status" "$((SECONDS - started))"
done

started=$SECONDS
run_export_check
report "export_content" "$?" "$((SECONDS - started))"

total=$((SECONDS - started_all))

echo "----"
if [[ ${#failed[@]} -eq 0 ]]; then
	printf 'all %d gates PASS in %ds\n' "$ran" "$total"
	exit 0
fi

printf '%d of %d gates FAILED in %ds: %s\n' \
	"${#failed[@]}" "$ran" "$total" "${failed[*]}"
exit 1
