# Project Scope

## Goal

Create a standalone Gates of Hell Conquest experience in which Star Wars starfighters are the only imported gameplay content.

## Included

- Galactic Republic, CIS, Galactic Empire, and Rebel Alliance air factions
- Starfighters, interceptors, bombers, and required aircraft weapons
- Fighter models, textures, effects, sounds, animations, icons, and localization
- Conquest research trees and purchasing definitions
- Player and AI aircraft deployment
- Airborne spawning, target acquisition, dogfighting, destruction, retreat, and cleanup
- Strictly required shared dependencies

## Excluded

- Historical aircraft and historical faction identities
- Infantry, tanks, artillery, ships, and unrelated ground content
- Shattered Galaxy maps and campaign systems
- Unrelated total-conversion scripts
- Unreviewed third-party assets

## Initial faction structure

1. Galactic Republic
2. Confederacy of Independent Systems
3. Galactic Empire
4. Rebel Alliance

## First vertical slice

- Galactic Empire: TIE fighter
- Rebel Alliance: X-wing
- One minimal Conquest setup
- Player purchase path
- Enemy AI deployment path
- Autonomous airborne dogfight behavior
- Clean destruction and mission cleanup

## Constraints

The original Workshop directories remain untouched. Work occurs in a separate local project. No source mod is copied wholesale into this repository. Every imported file must be traceable through the dependency and credits manifests.
