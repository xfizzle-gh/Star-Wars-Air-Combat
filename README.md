# Star Wars Air Combat

A standalone Call to Arms: Gates of Hell Conquest mod focused exclusively on Star Wars fighter combat.

The project combines a Conquest-compatible air-combat framework with isolated Star Wars starfighters and their strictly required dependencies. It does not include the broader Shattered Galaxy total conversion.

## Planned factions

- Galactic Republic
- Confederacy of Independent Systems
- Galactic Empire
- Rebel Alliance

## First playable milestone

A minimal Conquest vertical slice in which an Imperial player or AI can deploy a TIE fighter and a Rebel player or AI can deploy an X-wing. Both aircraft must spawn airborne, acquire targets, dogfight, resolve destruction correctly, and leave no dependency on unrelated Shattered Galaxy content.

## Source audit

The repository includes a local Windows audit workflow that inventories both Workshop mods without copying source assets into GitHub.

After cloning the repository, double-click `Run-Source-Audit.cmd`. It locates Workshop items `3666036374` and `2984016031`, generates sanitized relative-path reports, commits only those reports to `audit/source-inventories`, and pushes the branch.

See [docs/run-source-audit.md](docs/run-source-audit.md) for full details.

## Source policy

Steam Workshop source mods are local references only. Do not commit complete Workshop folders or unreviewed third-party assets. Every extracted file must be listed in the dependency and credits manifests before publication.
