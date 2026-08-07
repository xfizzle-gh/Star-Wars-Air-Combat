# Extraction Workflow

## Local source locations

- Air combat framework: `E:\Star-Wars-Air-Combat\sources\air-combat-script`
- Shattered Galaxy reference: `E:\Star-Wars-Air-Combat\sources\shattered-galaxy`
- Working project: `E:\Star-Wars-Air-Combat\project`
- Audit output: `E:\Star-Wars-Air-Combat\audit`

These source directories must remain outside the Git repository.

## Phase 1: Air-combat framework audit

Identify and document:

- Conquest purchase integration
- Aircraft spawn and airborne initialization
- `airborne.inc` and every include it requires
- Target search and target switching
- Fighter-versus-fighter behavior
- Player and enemy AI deployment
- Destruction, retreat, despawn, and mission cleanup
- Files that override base-game definitions

Record each required file in `docs/air-combat-manifest.md`.

## Phase 2: Fighter dependency audit

Start with only the TIE fighter and X-wing. For each craft, recursively trace:

- Entity definitions
- Models and materials
- Textures
- Weapons and mounts
- Ammunition and projectiles
- Effects
- Sounds
- Animations
- Breed or crew requirements
- Icons and localization
- Shared includes and constants

Record files in `docs/fighter-manifest.md`. Record provenance and permission status in `docs/credits-and-permissions.md`.

## Phase 3: Minimal build

Copy only audited dependencies into `project/`. Do not copy complete folders merely because one file is needed.

The first build must contain:

- A valid mod descriptor
- Minimal Imperial and Rebel faction definitions
- One TIE fighter and one X-wing
- Minimal research and purchase definitions
- Required air-combat scripts
- A reproducible test scenario

## Phase 4: Validation

The vertical slice is complete only when:

1. The mod loads without Shattered Galaxy enabled.
2. No unrelated Shattered Galaxy unit appears in logs or definitions.
3. The player can purchase and deploy the assigned fighter.
4. Enemy Conquest AI can deploy the opposing fighter.
5. Both spawn airborne.
6. Both acquire and attack valid air targets.
7. Destruction and mission cleanup complete without script errors.
8. A dependency audit reports no unresolved references.
