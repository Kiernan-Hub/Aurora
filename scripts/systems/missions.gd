extends RefCounted

class_name Missions

# One persistent, stable-ID goal at a time. No ticking node or service dependency. GameManager
# supplies run counters and banks only their unbanked delta on the existing save transitions.
# A full progress bar is also a pending reward: quitting before death cannot lose the chest.
const FIRST_ID: String = "coins"
const TABLE: Array[Dictionary] = [
	{"id": "coins", "title": "Earn %d coins", "target": 100},
	{"id": "distance", "title": "Travel %d m", "target": 2000},
	{"id": "chests", "title": "Collect %d chests", "target": 3},
	{"id": "geodes", "title": "Smash %d geodes", "target": 3, "slam": true},
]
const REWARD_TIER: int = ChestTypes.Tier.RARE


static func definition(id: String, completed: int, owns_slam: bool) -> Dictionary:
	var index: int = 0
	for candidate: int in range(TABLE.size()):
		if TABLE[candidate]["id"] == id:
			index = candidate
			break
	if TABLE[index].get("slam", false) and not owns_slam:
		index = (index + 1) % TABLE.size()
	var row: Dictionary = TABLE[index].duplicate()
	# Gentle progression with a ceiling; goals remain practical after many runs.
	row["target"] = int(row["target"]) * (1 + mini(completed / TABLE.size(), 2))
	row["title"] = String(row["title"]) % int(row["target"])
	return row


static func prepare(store: SaveStore, owns_slam: bool) -> Dictionary:
	var mission: Dictionary = definition(store.mission_id, store.missions_completed, owns_slam)
	if mission["id"] != store.mission_id:
		store.mission_id = mission["id"]
		store.mission_progress = 0.0
	store.mission_progress = clampf(store.mission_progress, 0.0, float(mission["target"]))
	return mission


# Purely in memory; the existing pause/death write carries this together with run data.
static func bank(store: SaveStore, mission: Dictionary, amount: float) -> bool:
	if amount <= 0.0 or store.mission_id != mission["id"]:
		return false
	var before: float = store.mission_progress
	store.mission_progress = minf(before + amount, float(mission["target"]))
	return store.mission_progress > before


# Called before rolling/banking the death rewards, never from the cosmetic reveal.
static func claim(store: SaveStore, mission: Dictionary, owns_slam: bool) -> bool:
	if store.mission_id != mission["id"] or store.mission_progress < float(mission["target"]):
		return false
	store.missions_completed += 1
	store.mission_progress = 0.0
	var index: int = 0
	for candidate: int in range(TABLE.size()):
		if TABLE[candidate]["id"] == mission["id"]:
			index = (candidate + 1) % TABLE.size()
			break
	store.mission_id = definition(TABLE[index]["id"], store.missions_completed, owns_slam)["id"]
	return true
