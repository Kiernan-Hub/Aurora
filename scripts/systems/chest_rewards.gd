extends RefCounted

class_name ChestRewards

# One reward per chest, banked on death before its reveal. Cosmetics never repeat while
# unowned finds remain. Exhausted cosmetic/skater rows fall back to a coin jackpot.
# Reward keys: coins, skin, cosmetic, jackpot. Cosmetic IDs come from Cosmetics.ITEMS.
const TABLE: Array[Dictionary] = [
	{"weight": 40, "coins_min": 15, "coins_max": 35},
	{"weight": 20, "coins_min": 50, "coins_max": 90},
	{"weight": 5, "coins_min": 200, "coins_max": 300, "jackpot": true},
	{"weight": 5, "skin": true},
	{"weight": 30, "cosmetic": true},
]
const JACKPOT_ROW: int = 2
const GLIDE_CHEST_NAME: String = "Ultra Mega Super Duper Chest"
const GLIDE_CHEST_COINS: int = 1000
const RARE_TABLE: Array[Dictionary] = [
	{"weight": 5, "coins_min": 50, "coins_max": 90},
	{"weight": 20, "coins_min": 100, "coins_max": 180},
	{"weight": 10, "coins_min": 200, "coins_max": 300, "jackpot": true},
	{"weight": 5, "skin": true},
	{"weight": 60, "cosmetic": true},
]


# One reward per chest. A skin won by an earlier chest of the same run is not rolled again.
static func roll_all(chest_count: int, unowned_skin_ids: Array[String], rng: RandomNumberGenerator, unowned_cosmetic_ids: Array[String] = [], tiers: Array[int] = []) -> Array[Dictionary]:
	var remaining_skins: Array[String] = unowned_skin_ids.duplicate()
	var remaining_cosmetics: Array[String] = unowned_cosmetic_ids.duplicate()
	var rewards: Array[Dictionary] = []
	for _chest: int in range(chest_count):
		var tier: int = tiers[_chest] if _chest < tiers.size() else ChestTypes.Tier.NORMAL
		var reward: Dictionary = roll(remaining_skins, rng, remaining_cosmetics, tier)
		remaining_skins.erase(reward["skin"])
		remaining_cosmetics.erase(reward["cosmetic"])
		rewards.append(reward)
	return rewards


static func roll(unowned_skin_ids: Array[String], rng: RandomNumberGenerator, unowned_cosmetic_ids: Array[String] = [], tier: int = ChestTypes.Tier.NORMAL) -> Dictionary:
	tier = ChestTypes.normalize(tier)
	if tier == ChestTypes.Tier.AURORA:
		if not unowned_cosmetic_ids.is_empty():
			return {"coins": 0, "skin": "", "cosmetic": unowned_cosmetic_ids[rng.randi_range(0, unowned_cosmetic_ids.size() - 1)], "jackpot": false, "tier": tier}
		return {"coins": rng.randi_range(200, 300), "skin": "", "cosmetic": "", "jackpot": true, "tier": tier}
	var table: Array[Dictionary] = RARE_TABLE if tier == ChestTypes.Tier.RARE else TABLE
	var total_weight: int = 0
	for row: Dictionary in table:
		total_weight += int(row["weight"])
	var remaining_weight: int = rng.randi_range(0, total_weight - 1)
	var drawn: Dictionary = table[0]
	for row: Dictionary in table:
		drawn = row
		remaining_weight -= int(row["weight"])
		if remaining_weight < 0:
			break
	if drawn.get("cosmetic", false):
		if not unowned_cosmetic_ids.is_empty():
			return {"coins": 0, "skin": "", "cosmetic": unowned_cosmetic_ids[rng.randi_range(0, unowned_cosmetic_ids.size() - 1)], "jackpot": false, "tier": tier}
		drawn = TABLE[JACKPOT_ROW]
	if drawn.get("skin", false):
		if not unowned_skin_ids.is_empty():
			return {"coins": 0, "skin": unowned_skin_ids[rng.randi_range(0, unowned_skin_ids.size() - 1)], "cosmetic": "", "jackpot": false, "tier": tier}
		drawn = TABLE[JACKPOT_ROW]
	return {
		"tier": tier,
		"coins": rng.randi_range(int(drawn["coins_min"]), int(drawn["coins_max"])),
		"skin": "",
		"cosmetic": "",
		"jackpot": bool(drawn.get("jackpot", false)),
	}


static func get_total_coins(rewards: Array[Dictionary]) -> int:
	var total: int = 0
	for reward: Dictionary in get_loot(rewards):
		total += int(reward["coins"])
	return total


# A one-off achievement bundle, not a randomly spawned tier. Roll its three finds
# together so they cannot repeat; exhausted finds use Aurora's existing jackpot.
static func roll_glide_chest(unowned_skin_ids: Array[String], rng: RandomNumberGenerator,
		unowned_cosmetic_ids: Array[String]) -> Dictionary:
	var contents: Array[Dictionary] = roll_all(3, unowned_skin_ids, rng, unowned_cosmetic_ids,
		[ChestTypes.Tier.AURORA, ChestTypes.Tier.AURORA, ChestTypes.Tier.AURORA])
	contents.append({"coins": GLIDE_CHEST_COINS, "skin": "", "cosmetic": "", "jackpot": true})
	return {"name": GLIDE_CHEST_NAME, "coins": 0, "skin": "", "cosmetic": "", "jackpot": true,
		"tier": ChestTypes.Tier.AURORA, "contents": contents}


# Bundles have one reveal but several ordinary loot entries. Only internally rolled
# rewards reach this helper; bundles are one level deep and never stored as save data.
static func get_loot(rewards: Array[Dictionary]) -> Array[Dictionary]:
	var loot: Array[Dictionary] = []
	for reward: Dictionary in rewards:
		if reward.has("contents"):
			loot.append_array(reward["contents"])
		else:
			loot.append(reward)
	return loot
