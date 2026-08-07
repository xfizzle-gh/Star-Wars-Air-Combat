# Source audit findings

This document distills the locally generated Workshop audit reports supplied on 2026-08-07. The raw Workshop trees remain local and are not committed.

## Inventory summary

| Source | Files | Candidate reports |
| --- | ---: | ---: |
| Conquest air-combat mod | 1,404 | 428 path candidates; 524 text-match records |
| Shattered Galaxy | 161,497 | 1,028 fighter path candidates; 77 fighter text-match records |

The Shattered Galaxy inventory confirms a broad 80 GB total-conversion source. Extraction must therefore remain dependency-driven rather than directory-driven.

## First vertical-slice aircraft

The strongest root entity candidates are:

- Imperial TIE/LN fighter: `resource\entity\-vehicle_star_wars\airborne\tie_ln\tie_ln.def`
- Rebel X-wing: `resource\entity\-vehicle_star_wars\airborne\xwing\xwing.def`

Do not use the small proxy/test definitions under `resource\entity\-vehicle_star_wars\airborne\x\tie_ln_xx` or `...\xwing_xx` as production roots.

### TIE/LN local entity folder

The `tie_ln` entity folder contains 12 files totaling 3,458,596 bytes:

- `tie_ln.def`
- `tie_ln_static.def`
- `tie_fighter.mdl`
- body and wing geometry
- body, wing, and window materials

### X-wing local entity folder

The `xwing` entity folder contains 20 files totaling 462,071 bytes:

- `xwing.def`
- `x-wing.mdl`
- body and four wing geometry groups
- engine animations
- `anim.txt`
- materials and collision volumes

These same-folder files are only the immediate model packages. They do not yet prove the complete weapon, ammunition, projectile, effect, texture, sound, registry, localization, or interaction dependency closure.

## Star Wars Conquest integration already present in Shattered Galaxy

Shattered Galaxy already contains dedicated four-faction Conquest scaffolding matching the approved project scope.

### Conquest units

- `resource\set\multiplayer\units\conquest\units_rep.set`
- `resource\set\multiplayer\units\conquest\units_cis.set`
- `resource\set\multiplayer\units\conquest\units_imp.set`
- `resource\set\multiplayer\units\conquest\units_reb.set`

Corresponding `inf_*.set` files also exist, but infantry content is explicitly outside this project and must not be imported.

### Dynamic Campaign research

- `resource\set\dynamic_campaign\unit_research_rep.set`
- `resource\set\dynamic_campaign\unit_research_cis.set`
- `resource\set\dynamic_campaign\unit_research_imp.set`
- `resource\set\dynamic_campaign\unit_research_reb.set`

### Faction Conquest scripts

- `resource\script\multiplayer\units\rep\conquest.rep.lua`
- `resource\script\multiplayer\units\cis\conquest.cis.lua`
- `resource\script\multiplayer\units\imp\conquest.imp.lua`
- `resource\script\multiplayer\units\reb\conquest.reb.lua`

These are valuable references, but they may contain ground-unit and total-conversion assumptions. They must be narrowed into aircraft-only definitions rather than copied wholesale.

## Star Wars aircraft interaction candidates

The strongest shared Star Wars aircraft support files are:

- `resource\set\interaction_entity\SG\SG_airborne.inc`
- `resource\set\interaction_entity\SG\SG_sound_defines.inc`
- `resource\set\registry\unit.reg`
- `resource\set\tp_control.set`

`SG_airborne.inc` is the primary candidate for Star Wars-specific fighter interactions. `SG_sound_defines.inc` is large and references X-wing audio repeatedly, so its required subset should be isolated instead of importing the complete include.

## Conquest air-combat framework entry points

The audit identifies the following high-value framework files from Workshop item `3666036374`.

### Core behavior

- `resource\map\multi\dcg_script.inc` (478,612 bytes)
- `resource\set\interaction_entity\airborne.inc` (77,701 bytes)
- `resource\properties\airborne.ext`
- `resource\properties\airborne2.ext`
- `resource\properties\airborne_combat.ext`
- `resource\properties\airborne_spawn.ext`

### Targeting

- `resource\set\target\airborne_select.inc`
- `resource\set\target\airborne_bullet.inc`
- `resource\set\target\airborne_bullet_combat.inc`

### Conquest integration

- `resource\script\multiplayer\modes\conquest.lua`
- `resource\set\multiplayer\units\conquest\settings.set`
- `resource\set\dynamic_campaign\resources_low.set`
- `resource\set\dynamic_campaign\resources_standard.set`
- `resource\set\dynamic_campaign\resources_high.set`
- `resource\set\dynamic_campaign\resources_very_high.set`

The historical faction unit and research files in the air-combat mod are implementation references only. They must not become project content.

## Audio scope warning

The immediate fighter audio directories are disproportionately large:

- TIE/LN audio: 118 files, approximately 71.2 MB
- X-wing audio: 28 files, approximately 21.7 MB

The TIE flyby directory contains many near-variant WAV files. The first private vertical slice should use the smallest proven sound subset, then expand only if the entity definitions require additional variants.

## Confirmed roster signal

The audit found 28 active Star Wars airborne entity directories, including:

- Republic examples: ARC-170, N-1, V-19 Torrent, V-wing
- CIS examples: Droid Vulture, Hyena Droid, Tri-fighter, Geonosian Starfighter
- Empire examples: TIE/LN, TIE Interceptor, TIE Bomber, TIE Striker
- Rebel examples: X-wing, A-wing, B-wing, Y-wing

This supports the planned four-faction fighter-only Conquest mode without inventing the initial roster.

## Remaining evidence required before extraction

The supplied upload did not include these generated reports:

- `air-combat-includes.csv`
- `shattered-galaxy-includes.csv`

Those reports, or direct access to the relevant text definitions, are required to prove recursive includes and references. Until that closure is reviewed:

- issue #2 is partially evidenced but not complete;
- issue #3 has authoritative root candidates but not a safe copy list;
- no third-party fighter assets should be committed;
- the TIE/X-wing vertical slice should not begin by copying broad folders.

## Next audit action

Resolve dependencies beginning from:

```powershell
.\tools\Resolve-ModDependencies.ps1 `
  -SourceRoot 'E:\Steam\steamapps\workshop\content\400750\2984016031' `
  -RootRelativePath @(
    'resource\entity\-vehicle_star_wars\airborne\tie_ln\tie_ln.def',
    'resource\entity\-vehicle_star_wars\airborne\xwing\xwing.def'
  )
```

Review every unresolved or ambiguous reference before any private extraction commit.