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

    $normalized = $Path.Trim().Trim('"', "'", '{', '}', '(', ')', '[', ']')
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

    $base = $BasePath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
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

function Read-TextSafely {
    param([Parameter(Mandatory)][string]$Path)

    try {
        return [System.IO.File]::ReadAllText($Path)
    }
    catch {
        return $null
    }
}

function Get-ReferenceTokens {
    param([Parameter(Mandatory)][string]$Content)

    $tokens = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    $patterns = @(
        '(?im)^\s*(?:#?include|include_once)\s*[\(\{]?\s*["''](?<token>[^"'']+)["'']',
        '(?im)\{\s*(?:include|import)\s+["''](?<token>[^"'']+)["'']',
        '["''](?<token>[^"'']*[\\/][^"'']+)["'']',
        '["''](?<token>[^"'']+\.(?:inc|set|def|mdl|mtl|dds|tga|png|jpg|jpeg|wav|ogg|bank|fx|shader|anim|anm|lua|xml|json|cfg|entity|weapon|ammo|breed))["'']'
    )

    foreach ($pattern in $patterns) {
        foreach ($match in [regex]::Matches($Content, $pattern)) {
            $token = $match.Groups['token'].Value.Trim()
            if ($token.Length -lt 2 -or $token.Length -gt 512) {
                continue
            }
            [void]$tokens.Add($token)
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

    $normalized = Normalize-RelativePath -Path $Token
    $candidates = New-Object System.Collections.ArrayList

    if ($ByRelativePath.ContainsKey($normalized)) {
        [void]$candidates.Add($ByRelativePath[$normalized])
    }

    $fromDirectory = Split-Path -Parent $FromRelativePath
    if (-not [string]::IsNullOrWhiteSpace($fromDirectory)) {
        $relativeToParent = Normalize-RelativePath -Path (Join-Path $fromDirectory $Token)
        if ($ByRelativePath.ContainsKey($relativeToParent)) {
            [void]$candidates.Add($ByRelativePath[$relativeToParent])
        }
    }

    $leaf = [System.IO.Path]::GetFileName($normalized)
    if (-not [string]::IsNullOrWhiteSpace($leaf) -and $ByFileName.ContainsKey($leaf)) {
        foreach ($entry in $ByFileName[$leaf]) {
            [void]$candidates.Add($entry)
        }
    }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($leaf)
    if (-not [string]::IsNullOrWhiteSpace($stem) -and $ByStem.ContainsKey($stem)) {
        foreach ($entry in $ByStem[$stem]) {
            [void]$candidates.Add($entry)
        }
    }

    $unique = @($candidates | Sort-Object RelativePath -Unique)
    if ($unique.Count -eq 1) {
        return [pscustomobject]@{
            Status     = 'resolved'
            Resolution = 'unique'
            Target     = $unique[0]
            Candidates = $unique
        }
    }
    if ($unique.Count -gt 1) {
        return [pscustomobject]@{
            Status     = 'ambiguous'
            Resolution = 'multiple candidates'
            Target     = $null
            Candidates = $unique
        }
    }

    return [pscustomobject]@{
        Status     = 'unresolved'
        Resolution = 'no candidate'
        Target     = $null
        Candidates = @()
    }
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

    $content = Read-TextSafely -Path $current.FullName
    if ($null -eq $content) {
        continue
    }

    foreach ($token in @(Get-ReferenceTokens -Content $content)) {
        $result = Resolve-Token -Token $token -FromRelativePath $current.RelativePath -ByRelativePath $byRelativePath -ByFileName $byFileName -ByStem $byStem

        if ($result.Status -eq 'resolved') {
            $target = $result.Target
            [void]$edges.Add([pscustomobject]@{
                From       = $current.RelativePath
                Token      = $token
                To         = $target.RelativePath
                Resolution = $result.Resolution
            })
            if (-not $visited.Contains($target.RelativePath)) {
                [void]$queue.Enqueue($target)
            }
        }
        elseif ($result.Status -eq 'ambiguous') {
            [void]$ambiguous.Add([pscustomobject]@{
                From       = $current.RelativePath
                Token      = $token
                Candidates = (($result.Candidates | ForEach-Object RelativePath) -join ' | ')
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
$edges = @($edges | Sort-Object From, To, Token -Unique)
$unresolved = @($unresolved | Sort-Object From, Token -Unique)
$ambiguous = @($ambiguous | Sort-Object From, Token -Unique)

$closure | Export-Csv -LiteralPath (Join-Path $output 'closure-files.csv') -NoTypeInformation -Encoding UTF8
$edges | Export-Csv -LiteralPath (Join-Path $output 'resolved-edges.csv') -NoTypeInformation -Encoding UTF8
$unresolved | Export-Csv -LiteralPath (Join-Path $output 'unresolved-references.csv') -NoTypeInformation -Encoding UTF8
$ambiguous | Export-Csv -LiteralPath (Join-Path $output 'ambiguous-references.csv') -NoTypeInformation -Encoding UTF8

$summary = @"
# Dependency closure

Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')

## Roots

$(@($roots | ForEach-Object { "- `$_`" }) -join "`n")

## Results

- Closure files: $($closure.Count)
- Resolved edges: $($edges.Count)
- Unresolved references: $($unresolved.Count)
- Ambiguous references: $($ambiguous.Count)

This is a heuristic reference scan. Every unresolved or ambiguous entry must be reviewed before files are copied into the standalone mod.
"@
[System.IO.File]::WriteAllText((Join-Path $output 'summary.md'), $summary, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Dependency closure written to: $output"
if ($unresolved.Count -gt 0 -or $ambiguous.Count -gt 0) {
    Write-Warning 'The closure has unresolved or ambiguous references. Review the generated reports before extraction.'
}
