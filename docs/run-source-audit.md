# Run the local source audit

The Workshop source files stay on the local Windows machine. GitHub and GitHub Actions cannot read `E:\Steam` directly.

## Supported source locations

The launcher checks these locations automatically, in order:

### Air-combat framework

1. `E:\Star-Wars-Air-Combat\sources\air-combat-script`
2. `E:\Steam\steamapps\workshop\content\400750\3666036374`

### Shattered Galaxy

1. `E:\Star-Wars-Air-Combat\sources\shattered-galaxy`
2. `E:\Steam\steamapps\workshop\content\400750\2984016031`

## One-click workflow

1. Clone this repository with GitHub Desktop.
2. Pull the latest `main` branch.
3. Double-click `Run-Source-Audit.cmd` in the repository folder.

The launcher will:

1. Find both Workshop sources.
2. Inventory every file using source-relative paths.
3. Search for Conquest air-combat scripts and include directives.
4. Search for TIE fighter and X-wing definitions and references.
5. Write sanitized reports under `audit/generated/`.
6. Reject reports containing local absolute paths.
7. Create or update branch `audit/source-inventories`.
8. Commit only `audit/generated/`.
9. Push the branch.
10. Open a pull request when GitHub CLI is installed and authenticated.

It never copies Workshop source assets.

## Manual PowerShell command

```powershell
.\tools\Invoke-AuditAndPublish.ps1
```

Explicit source paths can be supplied when needed:

```powershell
.\tools\Invoke-AuditAndPublish.ps1 `
  -AirCombatSource 'E:\Steam\steamapps\workshop\content\400750\3666036374' `
  -ShatteredGalaxySource 'E:\Steam\steamapps\workshop\content\400750\2984016031'
```

## Generated reports

- `air-combat-files.csv`
- `shattered-galaxy-files.csv`
- `air-combat-path-candidates.csv`
- `fighter-path-candidates.csv`
- `air-combat-text-candidates.csv`
- `fighter-text-candidates.csv`
- `air-combat-includes.csv`
- `shattered-galaxy-includes.csv`
- `summary.md`

## Dependency closure

After the root entity definition paths are confirmed, run:

```powershell
.\tools\Resolve-ModDependencies.ps1 `
  -SourceRoot 'E:\Steam\steamapps\workshop\content\400750\2984016031' `
  -RootRelativePath @(
    'REPLACE_WITH_TIE_ROOT_PATH',
    'REPLACE_WITH_XWING_ROOT_PATH'
  )
```

The resolver produces a heuristic recursive closure with resolved, unresolved, and ambiguous references. It does not copy files. Every ambiguous or unresolved entry must be reviewed before extraction.
