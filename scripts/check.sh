#!/usr/bin/env bash
#
# check.sh — the fast validation runner.
#
# Runs the four fast headless gates in sequence and exits non-zero if any of them
# failed. Quiet on PASS (one line per gate); on FAIL it prints that gate's full
# output, because the gates' own failure text is the diagnosis.
#
#   ./scripts/check.sh              run all four
#   ./scripts/check.sh -v           print every gate's output, pass or fail
#   GODOT=/path/to/Godot ./scripts/check.sh
#
# This is the "before every commit" tier. Three tiers exist and this is only the
# first; see docs/development/debugging.md for the other two:
#
#   fast (here)  shipping_values, biome_schedule, terrain_invariant, lake_suppression
#   physics      freeze-search, freeze-replay, floor-flicker, chasm, camera-shake
#                — minutes each, run them after any player/collision/segment change
#   visual       sky_layer_check, ice_look_capture, biome_contact_sheet
#                — MUST run WITHOUT --headless, they diff or save rendered frames,
#                  so they can never join a headless runner
#
# NOT run here, deliberately: project import (`--headless --editor --quit`). An
# --editor run rewrites project.godot and strips the pinned physics settings, and
# some terrain constants derive from physics_ticks_per_second — a validation script
# that silently changes level geometry is worse than no validation script. Import
# stays the manual step it is documented as, needed only after adding a class_name.

set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

failed=()
started_all=$SECONDS

for gate in "${GATES[@]}"; do
	IFS='|' read -r name script args <<< "$gate"
	printf '%-18s ' "$name"

	started=$SECONDS
	# shellcheck disable=SC2086 -- args is a deliberately word-split flag list
	output="$("$GODOT" --headless --path "$PROJECT_DIR" \
		--script "res://scripts/debug/$script" -- $args 2>&1)"
	status=$?
	elapsed=$((SECONDS - started))

	if [[ $status -eq 0 ]]; then
		printf 'PASS  %3ds\n' "$elapsed"
		[[ $VERBOSE -eq 1 ]] && printf '%s\n\n' "$output"
	else
		printf 'FAIL  %3ds  (exit %d)\n' "$elapsed" "$status"
		printf '%s\n\n' "$output"
		failed+=("$name")
	fi
done

total=$((SECONDS - started_all))

if [[ ${#failed[@]} -eq 0 ]]; then
	echo "----"
	printf 'all %d gates PASS in %ds\n' "${#GATES[@]}" "$total"
	exit 0
fi

echo "----"
printf '%d of %d gates FAILED in %ds: %s\n' \
	"${#failed[@]}" "${#GATES[@]}" "$total" "${failed[*]}"
exit 1
