extends RefCounted

class_name ChestRewards

# What a chest holds, rolled when the run ends. One weighted table: three sizes of coins and,
# rarely, a skater the player does not own yet. A reward is {"coins": int, "skin": String,
# "jackpot": bool}; "skin" is a Skins id or "".
#
# Tuned against a run's own income (about 170 coins in two minutes): a chest averages ~60 coins
# and one arrives every 80-120s, so chests add roughly a quarter on top, most of it in the rare
# jackpot. The skin row falls back to the jackpot once every skater is owned.
const TABLE: Array[Dictionary] = [
	{"weight": 55, "coins_min": 15, "coins_max": 35},
	{"weight": 30, "coins_min": 50, "coins_max": 90},
	{"weight": 10, "coins_min": 200, "coins_max": 300, "jackpot": true},
	{"weight": 5, "skin": true},
]
const JACKPOT_ROW: int = 2


# One reward per chest. A skin won by an earlier chest of the same run is not rolled again.
static func roll_all(chest_count: int, unowned_skin_ids: Array[String], rng: RandomNumberGenerator) -> Array[Dictionary]:
	var remaining_skins: Array[String] = unowned_skin_ids.duplicate()
	var rewards: Array[Dictionary] = []
	for _chest: int in range(chest_count):
		var reward: Dictionary = roll(remaining_skins, rng)
		remaining_skins.erase(reward["skin"])
		rewards.append(reward)
	return rewards


static func roll(unowned_skin_ids: Array[String], rng: RandomNumberGenerator) -> Dictionary:
	var total_weight: int = 0
	for row: Dictionary in TABLE:
		total_weight += int(row["weight"])
	var remaining_weight: int = rng.randi_range(0, total_weight - 1)
	var drawn: Dictionary = TABLE[0]
	for row: Dictionary in TABLE:
		drawn = row
		remaining_weight -= int(row["weight"])
		if remaining_weight < 0:
			break
	if drawn.get("skin", false):
		if not unowned_skin_ids.is_empty():
			return {"coins": 0, "skin": unowned_skin_ids[rng.randi_range(0, unowned_skin_ids.size() - 1)], "jackpot": false}
		drawn = TABLE[JACKPOT_ROW]
	return {
		"coins": rng.randi_range(int(drawn["coins_min"]), int(drawn["coins_max"])),
		"skin": "",
		"jackpot": bool(drawn.get("jackpot", false)),
	}


static func get_total_coins(rewards: Array[Dictionary]) -> int:
	var total: int = 0
	for reward: Dictionary in rewards:
		total += int(reward["coins"])
	return total
