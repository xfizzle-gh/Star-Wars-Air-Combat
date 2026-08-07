# Fighter Dependency Manifest

Source Workshop item: `2984016031`

Begin with the TIE fighter and X-wing only.

## Fighter index

| Faction | Fighter | Root entity definition | Status |
|---|---|---|---|
| Galactic Empire | TIE fighter | TBD | Not audited |
| Rebel Alliance | X-wing | TBD | Not audited |

## Dependency records

For every file, use one row and record the direct reference that caused it to be included.

| Fighter | Dependency type | Local source path | Directly referenced by | Shared dependency | Copied to project | Notes |
|---|---|---|---|---|---|---|
| TIE fighter | Entity | TBD | Root | No | No | TBD |
| X-wing | Entity | TBD | Root | No | No | TBD |

## Dependency types

- Entity
- Model
- Material
- Texture
- Weapon
- Ammunition
- Projectile
- Effect
- Sound
- Animation
- Breed or crew
- Icon
- Localization
- Include
- Constant or shared definition

## Completion rule

A fighter is audited only when every referenced path has either been resolved, explicitly rejected as unnecessary, or replaced with a project-owned equivalent.
