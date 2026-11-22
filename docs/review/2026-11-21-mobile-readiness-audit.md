# Aura stability audit — 2026-11-21

Reviewed `play/next` from `d2c0e94`. The owner requested desktop-only testing. The review covered
touch and Back handling, suspend/resume, saves, terrain and hazards, menu layouts, and Android
package contents. Runtime tests used a memory save. Android exports came from a separate copy.

| Finding | Fix and evidence |
|---|---|
| App suspend could miss Aura's focus-loss pause path. Buffered input could also fire after resuming. | Mobile suspend uses the same pause path as focus loss. A rendered regression injects suspend, focus loss and resume, verifies that progress banks once, and checks for a clean manual resume. The Melt clears its pending jump too. |
| Back could close the shop underneath its Reset Progress confirmation. | Reproduced with the Back notification on desktop. Back now dismisses that dialog first, keeping the shop open. The next Back leaves the shop. |
| A failed run save looked successful, and a failed reset could clear live progress. | Results show Save pending and let the player retry the same write. Retrying preserves the rolled chest and publishes the recorded run once. A failed reset restores the full prior save state. Tests inject both failures and then retry. |
| The export gate accepted packs as long as Godot exited successfully and wrote a file. | It now rejects reported parse or resource-load failures. Tested by pointing a disposable scene at a missing script: Godot wrote a pack and the gate rejected it. A separate Android export verified the arm64 APK, expected package, matching prior Playtest signature, and asset exclusions. The exported data loaded all 16 game scenes, including a spawned spike with its collision script connected. |
| Late obstacle searches repeat cached segment lookups inside a single physics tick. | Reused the resolved segment's baseline and avoided redundant work in the binary search. In two alternating A/B pairs on the M4, the 99th percentile fell from 7.8–7.9 ms to 5.3–5.7 ms across 9,600 searches per run. First legal offsets and 20,366 paired height/slope samples matched byte for byte, including negative X, segment seams, chasms, a lake, and an Aurora reservation. |

The baseline and the main set of fixes passed all 15 headless and physics gates. The six
standard gates passed again after the final Back fix. All 14 rendered UI cases passed, covering
pause, suspend, Back, purchase/reset, reward persistence, and the lake and Melt transitions.
Visible controls fit six screens at 16:9, 19.5:9, 21:9 and 4:3. All three visual checks passed.

Physical Android behavior, thermal performance, and device frame pacing remain unmeasured.
The earlier rendered desktop run saw occasional frame hitches, including one long frame gap
whose cause was not identified. The search benchmark measures CPU placement work only.

Godot's [Node notification reference](https://docs.godotengine.org/en/stable/classes/class_node.html#constants)
distinguishes application suspend, focus loss and Android Back. The desktop tests deliver those
notifications to the game's handler directly.
