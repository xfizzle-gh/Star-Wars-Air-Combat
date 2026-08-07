[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourceRoot,

    [Parameter(Mandatory)]
    [string[]]$RootRelativePath,

    [Parameter()]
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\audit\generated\dependency-closure'),

    [Parameter()]
    [int]$MaximumTextFileBytes = 8388608
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Normalize-RelativePath {
    param([Parameter(Mandatory)][string]$Path)

    $trimChars = [char[]]@('"', "'", '{', '}', '(', ')', '[', ']')
    $normalized = $Path.Trim().Trim($trimChars)
    $normalized = $normalized -replace '/', '\'
    $normalized = $normalized -replace '^\.\\', ''
    $normalized = $normalized -replace '^\\+', ''
    $normalized = $normalized -replace '^(?i:resource\\)', ''
    return $normalized.ToLowerInvariant()
}

function Get-SafeRelativePath {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$Path
    )

    $base = $BasePath.TrimEnd([char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ))
    $baseUri = [Uri]($base + [System.IO.Path]::DirectorySeparatorChar)
    $pathUri = [Uri]$Path
    return ([Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString())).Replace('/', '\')
}

function Test-TextFile {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    if ($File.Length -gt $MaximumTextFileBytes) {
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

function Get-ReferenceTokens {
    param([Parameter(Mandatory)][string]$Content)

    $tokens = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $patterns = @(
        "(?im)^\s*(?:#?include|include_once)\s*[\(\{]?\s*[`\"'](?<token>[^`\"']+)[`\"']",
        "(?im)\{\s*(?:include|import)\s+[`\"'](?<token>[^`\"']+)[`\"']",
        "[`\"'](?<token>[^`\"']*[\\/][^`\"']+)[`\"']",
        "[`\"'](?<token>[^`\"']+\.(?:inc|set|def|mdl|mtl|dds|tga|png|jpg|jpeg|wav|ogg|bank|fx|shader|anim|anm|lua|xml|json|cfg|entity|weapon|ammo|breed))[`\"']"
    )

    foreach ($pattern in $patterns) {
        foreach ($match in [regex]::Matches($Content, $pattern)) {
            $token = $match.Groups['token'].Value.Trim()
            if ($token.Length -ge 2 -and $token.Length -le 512) {
                [void]$tokens.Add($token)
            }
        }
    }

    return @($tokens)
}

function Add-ToLookup {
    param(
        [Parameter(Mandatory)][hashtable]$Lookup,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][object]$Value
    )

    if (-not $Lookup.ContainsKey($Key)) {
        $Lookup[$Key] = New-Object System.Collections.ArrayList
    }
    [void]$Lookup[$Key].Add($Value)
}

function Resolve-Token {
    param(
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$FromRelativePath,
        [Parameter(Mandatory)][hashtable]$ByRelativePath,
        [Parameter(Mandatory)][hashtable]$ByFileName,
        [Parameter(Mandatory)][hashtable]$ByStem
    )

    $candidateMap = @{}
    $normalized = Normalize-RelativePath -Path $Token

    if ($ByRelativePath.ContainsKey($normalized)) {
        $candidateMap[$ByRelativePath[$normalized].RelativePath] = $ByRelativePath[$normalized]
    }

    $fromDirectory = Split-Path -Parent $FromRelativePath
    if (-not [string]::IsNullOrWhiteSpace($fromDirectory)) {
        $parentRelative = Normalize-RelativePath -Path (Join-Path $fromDirectory $Token)
        if ($ByRelativePath.ContainsKey($parentRelative)) {
            $candidateMap[$ByRelativePath[$parentRelative].RelativePath] = $ByRelativePath[$parentRelative]
        }
    }

    $leaf = [System.IO.Path]::GetFileName($normalized)
    if (-not [string]::IsNullOrWhiteSpace($leaf) -and $ByFileName.ContainsKey($leaf)) {
        foreach ($candidate in $ByFileName[$leaf]) {
            $candidateMap[$candidate.RelativePath] = $candidate
        }
    }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($leaf)
    if (-not [string]::IsNullOrWhiteSpace($stem) -and $ByStem.ContainsKey($stem)) {
        foreach ($candidate in $ByStem[$stem]) {
            $candidateMap[$candidate.RelativePath] = $candidate
        }
    }

    $candidates = @($candidateMap.Values | Sort-Object RelativePath)
    if ($candidates.Count -eq 1) {
        return [pscustomobject]@{ Status = 'resolved'; Target = $candidates[0]; Candidates = $candidates }
    }
    if ($candidates.Count -gt 1) {
        return [pscustomobject]@{ Status = 'ambiguous'; Target = $null; Candidates = $candidates }
    }
    return [pscustomobject]@{ Status = 'unresolved'; Target = $null; Candidates = @() }
}

$root = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $SourceRoot).Path)
$output = [System.IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $output -Force | Out-Null

Write-Host 'Indexing source files...'
$files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object {
    [pscustomobject]@{
        RelativePath = Get-SafeRelativePath -BasePath $root -Path $_.FullName
        FullName     = $_.FullName
        FileName     = $_.Name.ToLowerInvariant()
        Stem         = $_.BaseName.ToLowerInvariant()
        LengthBytes  = $_.Length
        IsText       = Test-TextFile -File $_
    }
})

$byRelativePath = @{}
$byFileName = @{}
$byStem = @{}
foreach ($file in $files) {
    $byRelativePath[(Normalize-RelativePath -Path $file.RelativePath)] = $file
    Add-ToLookup -Lookup $byFileName -Key $file.FileName -Value $file
    Add-ToLookup -Lookup $byStem -Key $file.Stem -Value $file
}

$queue = New-Object System.Collections.Queue
$visited = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$roots = New-Object System.Collections.ArrayList

foreach ($requestedRoot in $RootRelativePath) {
    $normalizedRoot = Normalize-RelativePath -Path $requestedRoot
    if (-not $byRelativePath.ContainsKey($normalizedRoot)) {
        throw "Root file was not found under the source folder: $requestedRoot"
    }
    $rootFile = $byRelativePath[$normalizedRoot]
    [void]$queue.Enqueue($rootFile)
    [void]$roots.Add($rootFile.RelativePath)
}

$edges = New-Object System.Collections.ArrayList
$unresolved = New-Object System.Collections.ArrayList
$ambiguous = New-Object System.Collections.ArrayList

while ($queue.Count -gt 0) {
    $current = $queue.Dequeue()
    if (-not $visited.Add($current.RelativePath)) {
        continue
    }
    if (-not $current.IsText) {
        continue
    }

    try {
        $content = [System.IO.File]::ReadAllText($current.FullName)
    }
    catch {
        continue
    }

    foreach ($token in @(Get-ReferenceTokens -Content $content)) {
        $result = Resolve-Token -Token $token -FromRelativePath $current.RelativePath -ByRelativePath $byRelativePath -ByFileName $byFileName -ByStem $byStem

        if ($result.Status -eq 'resolved') {
            [void]$edges.Add([pscustomobject]@{
                From  = $current.RelativePath
                Token = $token
                To    = $result.Target.RelativePath
            })
            if (-not $visited.Contains($result.Target.RelativePath)) {
                [void]$queue.Enqueue($result.Target)
            }
        }
        elseif ($result.Status -eq 'ambiguous') {
            [void]$ambiguous.Add([pscustomobject]@{
                From       = $current.RelativePath
                Token      = $token
                Candidates = (($result.Candidates | ForEach-Object { $_.RelativePath }) -join ' | ')
            })
        }
        else {
            [void]$unresolved.Add([pscustomobject]@{
                From  = $current.RelativePath
                Token = $token
            })
        }
    }
}

$closure = @($files | Where-Object { $visited.Contains($_.RelativePath) } | Sort-Object RelativePath | Select-Object RelativePath, LengthBytes, IsText)
$resolvedEdges = @($edges | Sort-Object From, To, Token -Unique)
$unresolvedRows = @($unresolved | Sort-Object From, Token -Unique)
$ambiguousRows = @($ambiguous | Sort-Object From, Token -Unique)

$closure | Export-Csv -LiteralPath (Join-Path $output 'closure-files.csv') -NoTypeInformation -Encoding UTF8
$resolvedEdges | Export-Csv -LiteralPath (Join-Path $output 'resolved-edges.csv') -NoTypeInformation -Encoding UTF8
$unresolvedRows | Export-Csv -LiteralPath (Join-Path $output 'unresolved-references.csv') -NoTypeInformation -Encoding UTF8
$ambiguousRows | Export-Csv -LiteralPath (Join-Path $output 'ambiguous-references.csv') -NoTypeInformation -Encoding UTF8

$rootLines = @($roots | ForEach-Object { '- ' + $_ }) -join "`n"
$summary = @"
# Dependency closure

Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')

## Roots

$rootLines

## Results

- Closure files: $($closure.Count)
- Resolved edges: $($resolvedEdges.Count)
- Unresolved references: $($unresolvedRows.Count)
- Ambiguous references: $($ambiguousRows.Count)

This is a heuristic reference scan. Review every unresolved or ambiguous entry before copying files.
"@

[System.IO.File]::WriteAllText(
    (Join-Path $output 'summary.md'),
    $summary,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Dependency closure written to: $output"
if ($unresolvedRows.Count -gt 0 -or $ambiguousRows.Count -gt 0) {
    Write-Warning 'The closure has unresolved or ambiguous references.'
}
