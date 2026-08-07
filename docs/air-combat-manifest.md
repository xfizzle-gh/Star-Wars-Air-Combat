# Air-Combat Framework Manifest

Source Workshop item: `3666036374`

Complete this manifest before copying framework files into the project.

| Local source path | Purpose | Referenced by | Override or additive | Required for vertical slice | Notes |
|---|---|---|---|---|---|
| TBD | TBD | TBD | TBD | TBD | TBD |

## Required behavior map

| Behavior | Entry file or definition | Dependencies | Validation method |
|---|---|---|---|
| Conquest purchase integration | TBD | TBD | Fighter appears in purchase tree |
| Airborne spawn initialization | TBD | TBD | Fighter begins in flight |
| Target acquisition | TBD | TBD | Fighter selects valid enemy aircraft |
| Dogfight loop | TBD | TBD | Fighters pursue and attack |
| Enemy AI deployment | TBD | TBD | AI purchases or spawns fighter |
| Destruction handling | TBD | TBD | Destroyed craft resolves cleanly |
| Retreat or despawn | TBD | TBD | Surviving craft exits cleanly |
| Mission cleanup | TBD | TBD | No persistent script errors |

## Audit rules

- Record every include recursively.
- Flag any file that replaces a base-game file.
- Do not copy broad directories without file-level justification.
- Note any assumptions about mod load order.
