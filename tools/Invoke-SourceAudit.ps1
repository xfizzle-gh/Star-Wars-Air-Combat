[CmdletBinding()]
param(
    [Parameter()]
    [string]$AirCombatSource = 'E:\Star-Wars-Air-Combat\sources\air-combat-script',

    [Parameter()]
    [string]$ShatteredGalaxySource = 'E:\Star-Wars-Air-Combat\sources\shattered-galaxy',

    [Parameter()]
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\audit\generated'),

    [Parameter()]
    [switch]$HashFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param([Parameter(Mandatory)][string]$Path)

    return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
}

function Get-SafeRelativePath {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$Path
    )

    $base = $BasePath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $baseUri = [Uri]($base + [System.IO.Path]::DirectorySeparatorChar)
    $pathUri = [Uri]$Path
    $relative = [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString())
    return $relative.Replace('/', '\')
}

function Test-ProbablyTextFile {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    $knownTextExtensions = @(
        '.inc', '.set', '.def', '.txt', '.xml', '.json', '.csv', '.cfg', '.ini',
        '.lua', '.script', '.mission', '.map', '.info', '.lng', '.po', '.pot',
        '.mdl', '.mtl', '.fx', '.shader', '.ammo', '.weapon', '.entity', '.breed'
    )

    if ($knownTextExtensions -contains $File.Extension.ToLowerInvariant()) {
        return $true
    }

    if ($File.Length -gt 8MB) {
        return $false
    }

    try {
        $stream = [System.IO.File]::OpenRead($File.FullName)
        try {
            $buffer = New-Object byte[] 4096
            $read = $stream.Read($buffer, 0, $buffer.Length)
            for ($index = 0; $index -lt $read; $index++) {
                if ($buffer[$index] -eq 0) {
                    return $false
                }
            }
            return $true
        }
        finally {
            $stream.Dispose()
        }
    }
    catch {
        return $false
    }
}

function Get-FileInventory {
    param(
        [Parameter(Mandatory)][string]$SourceName,
        [Parameter(Mandatory)][string]$SourceRoot
    )

    Write-Host "Inventorying $SourceName..."
    $files = Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -Force
    $count = $files.Count
    $current = 0

    foreach ($file in $files) {
        $current++
        if (($current % 2500) -eq 0) {
            Write-Progress -Activity "Inventorying $SourceName" -Status "$current / $count" -PercentComplete (($current / [Math]::Max($count, 1)) * 100)
        }

        $record = [ordered]@{
            Source       = $SourceName
            RelativePath = Get-SafeRelativePath -BasePath $SourceRoot -Path $file.FullName
            FileName     = $file.Name
            Extension    = $file.Extension.ToLowerInvariant()
            LengthBytes  = $file.Length
            IsText       = Test-ProbablyTextFile -File $file
        }

        if ($HashFiles) {
            $record.Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }

        [pscustomobject]$record
    }

    Write-Progress -Activity "Inventorying $SourceName" -Completed
}

function Read-TextSafely {
    param([Parameter(Mandatory)][string]$Path)

    try {
        return [System.IO.File]::ReadAllText($Path)
    }
    catch {
        try {
            return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop)
        }
        catch {
            return $null
        }
    }
}

function Find-TextMatches {
    param(
        [Parameter(Mandatory)][string]$SourceName,
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][object[]]$Inventory,
        [Parameter(Mandatory)][hashtable]$Patterns
    )

    $textFiles = @($Inventory | Where-Object IsText)
    $count = $textFiles.Count
    $current = 0

    foreach ($entry in $textFiles) {
        $current++
        if (($current % 500) -eq 0) {
            Write-Progress -Activity "Scanning text in $SourceName" -Status "$current / $count" -PercentComplete (($current / [Math]::Max($count, 1)) * 100)
        }

        $fullPath = Join-Path $SourceRoot $entry.RelativePath
        $content = Read-TextSafely -Path $fullPath
        if ($null -eq $content) {
            continue
        }

        foreach ($patternName in $Patterns.Keys) {
            $regex = [regex]$Patterns[$patternName]
            $matches = $regex.Matches($content)
            if ($matches.Count -eq 0) {
                continue
            }

            $examples = @($matches | Select-Object -First 5 | ForEach-Object { $_.Value.Trim() })
            [pscustomobject]@{
                Source       = $SourceName
                RelativePath = $entry.RelativePath
                Pattern      = $patternName
                MatchCount   = $matches.Count
                Examples     = ($examples -join ' | ')
            }
        }
    }

    Write-Progress -Activity "Scanning text in $SourceName" -Completed
}

function Find-IncludeDirectives {
    param(
        [Parameter(Mandatory)][string]$SourceName,
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][object[]]$Inventory
    )

    $includePatterns = @(
        '(?im)^\s*(?:#?include|include_once)\s*[\(\{]?\s*["''](?<target>[^"'']+)["'']',
        '(?im)\{\s*include\s+["''](?<target>[^"'']+)["'']',
        '(?im)\{\s*import\s+["''](?<target>[^"'']+)["'']'
    )

    foreach ($entry in @($Inventory | Where-Object IsText)) {
        $fullPath = Join-Path $SourceRoot $entry.RelativePath
        $content = Read-TextSafely -Path $fullPath
        if ($null -eq $content) {
            continue
        }

        foreach ($pattern in $includePatterns) {
            foreach ($match in [regex]::Matches($content, $pattern)) {
                [pscustomobject]@{
                    Source       = $SourceName
                    RelativePath = $entry.RelativePath
                    Target       = $match.Groups['target'].Value.Trim()
                    Directive    = $match.Value.Trim()
                }
            }
        }
    }
}

function Find-PathCandidates {
    param(
        [Parameter(Mandatory)][object[]]$Inventory,
        [Parameter(Mandatory)][string]$Regex,
        [Parameter(Mandatory)][string]$Reason
    )

    foreach ($entry in $Inventory) {
        if ($entry.RelativePath -match $Regex -or $entry.FileName -match $Regex) {
            [pscustomobject]@{
                Source       = $entry.Source
                RelativePath = $entry.RelativePath
                LengthBytes  = $entry.LengthBytes
                Reason       = $Reason
            }
        }
    }
}

function Write-Utf8Csv {
    param(
        [Parameter(Mandatory)][object[]]$InputObject,
        [Parameter(Mandatory)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $InputObject | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $AirCombatSource -PathType Container)) {
    throw "Air-combat source folder was not found: $AirCombatSource"
}
if (-not (Test-Path -LiteralPath $ShatteredGalaxySource -PathType Container)) {
    throw "Shattered Galaxy source folder was not found: $ShatteredGalaxySource"
}

$airRoot = Resolve-FullPath -Path $AirCombatSource
$galaxyRoot = Resolve-FullPath -Path $ShatteredGalaxySource
$output = [System.IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $output -Force | Out-Null

$airInventory = @(Get-FileInventory -SourceName 'air-combat-script' -SourceRoot $airRoot)
$galaxyInventory = @(Get-FileInventory -SourceName 'shattered-galaxy' -SourceRoot $galaxyRoot)

Write-Utf8Csv -InputObject $airInventory -Path (Join-Path $output 'air-combat-files.csv')
Write-Utf8Csv -InputObject $galaxyInventory -Path (Join-Path $output 'shattered-galaxy-files.csv')

$airPathCandidates = @(Find-PathCandidates -Inventory $airInventory -Regex '(?i)(airborne|aircraft|fighter|dogfight|dynamic.?campaign|conquest|dcg|squadron|flight)' -Reason 'air-combat path keyword')
$fighterPathCandidates = @(
    Find-PathCandidates -Inventory $galaxyInventory -Regex '(?i)(^|[\\/_ .-])(tie|tie_fighter|tiefighter|x.?wing|xwing|t.?65)([\\/_ .-]|$)' -Reason 'TIE or X-wing path keyword'
)

Write-Utf8Csv -InputObject $airPathCandidates -Path (Join-Path $output 'air-combat-path-candidates.csv')
Write-Utf8Csv -InputObject $fighterPathCandidates -Path (Join-Path $output 'fighter-path-candidates.csv')

$airPatterns = @{
    Airborne        = '(?i)\bairborne\b'
    Aircraft        = '(?i)\b(?:aircraft|fighter|bomber|interceptor|plane)\b'
    Dogfight        = '(?i)\b(?:dogfight|pursue|air.?target|target.?air)\b'
    Conquest        = '(?i)\b(?:conquest|dynamic.?campaign|dcg)\b'
    SpawnDeployment = '(?i)\b(?:spawn|deploy|reinforcement|purchase|call.?in)\b'
    Cleanup         = '(?i)\b(?:despawn|retreat|destroyed|cleanup|remove)\b'
}
$fighterPatterns = @{
    TieFighter = '(?i)\b(?:tie[ _-]?fighter|tiefighter)\b'
    XWing      = '(?i)\b(?:x[ _-]?wing|xwing|t[ _-]?65)\b'
    Starfighter = '(?i)\b(?:starfighter|interceptor|bomber)\b'
}

$airTextMatches = @(Find-TextMatches -SourceName 'air-combat-script' -SourceRoot $airRoot -Inventory $airInventory -Patterns $airPatterns)
$fighterTextMatches = @(Find-TextMatches -SourceName 'shattered-galaxy' -SourceRoot $galaxyRoot -Inventory $galaxyInventory -Patterns $fighterPatterns)

Write-Utf8Csv -InputObject $airTextMatches -Path (Join-Path $output 'air-combat-text-candidates.csv')
Write-Utf8Csv -InputObject $fighterTextMatches -Path (Join-Path $output 'fighter-text-candidates.csv')

$airIncludes = @(Find-IncludeDirectives -SourceName 'air-combat-script' -SourceRoot $airRoot -Inventory $airInventory)
$galaxyIncludes = @(Find-IncludeDirectives -SourceName 'shattered-galaxy' -SourceRoot $galaxyRoot -Inventory $galaxyInventory)
Write-Utf8Csv -InputObject $airIncludes -Path (Join-Path $output 'air-combat-includes.csv')
Write-Utf8Csv -InputObject $galaxyIncludes -Path (Join-Path $output 'shattered-galaxy-includes.csv')

$summary = @"
# Generated source audit

Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')

This report contains sanitized relative paths only. No source assets were copied.

## Air-combat framework

- Files: $($airInventory.Count)
- Total bytes: $(($airInventory | Measure-Object LengthBytes -Sum).Sum)
- Path candidates: $($airPathCandidates.Count)
- Text candidate records: $($airTextMatches.Count)
- Include directives: $($airIncludes.Count)

## Shattered Galaxy

- Files: $($galaxyInventory.Count)
- Total bytes: $(($galaxyInventory | Measure-Object LengthBytes -Sum).Sum)
- TIE/X-wing path candidates: $($fighterPathCandidates.Count)
- Fighter text candidate records: $($fighterTextMatches.Count)
- Include directives: $($galaxyIncludes.Count)

## Next command

Use `Resolve-ModDependencies.ps1` after selecting the root TIE fighter and X-wing definition files from the candidate reports.
"@

[System.IO.File]::WriteAllText((Join-Path $output 'summary.md'), $summary, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ''
Write-Host "Audit complete: $output"
Write-Host 'Review and commit only the generated CSV and Markdown reports. Do not commit either source folder.'
