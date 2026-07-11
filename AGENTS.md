# Godot 4 Project: Aurora Skater

## Overview
* 2D endless skating game, Godot 4.4, GDScript
* Style reference: Alto's Adventure — clean, minimalist, smooth
* Core loop: skate on procedurally generated terrain, speed increases over time
* Systems: missions, upgrades (player + skates), weather/aurora visual events

## Architecture
* Autoloads (singletons) live in autoloads/ — e.g. GameState.gd for score/currency
* Static typing required: var speed: float = 0.0, not var speed := 0.0
* Physics logic only in _physics_process(delta)
* Physics Interpolation is ON (Project Settings > Physics > Common) for 120hz smoothness — don't write movement code that assumes a fixed timestep

## Directory Structure
* scenes/player/ - player scene + skater sprite
* scenes/terrain/ - procedural terrain chunks
* scenes/ui/ - HUD, menus
* scripts/player/ - movement, skate physics
* scripts/terrain/ - procedural generation, cleanup
* scripts/systems/ - one file per system (speed_manager.gd, mission_manager.gd, upgrade_manager.gd) — keep these separate, don't merge into one GameManager

## Style
* snake_case for vars/functions, PascalCase for classes
* Explicit return types on all functions

## Build Order (current status)
1. Core loop (terrain + movement) — NOT STARTED
2. Speed scaling — NOT STARTED
3. Visual polish (sprites, parallax, aurora/storm) — NOT STARTED
4. Missions — NOT STARTED
5. Upgrades — NOT STARTED
