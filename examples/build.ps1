#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Builds every example into a RAM binary and a pasteable S-record file.

.DESCRIPTION
    Each .s file beside this script is assembled and linked with example.cfg
    to a flat binary that runs from $010000, then wrapped into Motorola
    S-records: S2 data records carrying the 24-bit load address, and an S8
    terminator naming $010000 as the entry point, so the monitor's G command
    needs no operand. Load one by typing L at the monitor prompt and pasting
    the .srec file.

.PARAMETER OutputDirectory
    Where the binaries and S-record files land. Defaults to out/examples
    under the repository.

.EXAMPLE
    pwsh examples/build.ps1
#>

[CmdletBinding()]
param(
    [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$exampleRoot = $PSScriptRoot

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repositoryRoot 'out/examples'
}

$loadAddress = 0x010000

function Find-Tool {
    param([string] $Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue

    if ($command) {
        return $command.Source
    }

    $candidates = @(
        'C:\Tools\cc65\bin',
        'C:\cc65\bin',
        '/usr/local/bin',
        '/usr/bin'
    )

    foreach ($directory in $candidates) {
        foreach ($extension in @('.exe', '')) {
            $path = Join-Path $directory "$Name$extension"

            if (Test-Path -LiteralPath $path -PathType Leaf) {
                return $path
            }
        }
    }

    return $null
}

# Wraps a flat binary into S2 data records and an S8 terminator.
function ConvertTo-SRecords {
    param(
        [byte[]] $Data,
        [uint32] $Address,
        [uint32] $Entry
    )

    $lines = [System.Collections.Generic.List[string]]::new()

    for ($offset = 0; $offset -lt $Data.Length; $offset += 32) {
        $length = [Math]::Min(32, $Data.Length - $offset)
        $recordAddress = $Address + [uint32]$offset
        $count = $length + 4

        $sum = $count
        $sum += ($recordAddress -shr 16) -band 0xFF
        $sum += ($recordAddress -shr 8) -band 0xFF
        $sum += $recordAddress -band 0xFF

        $hex = [System.Text.StringBuilder]::new()

        for ($i = 0; $i -lt $length; $i++) {
            $value = $Data[$offset + $i]
            $sum += $value
            [void]$hex.Append($value.ToString('X2'))
        }

        $checksum = 0xFF - ($sum -band 0xFF)
        $lines.Add(('S2{0:X2}{1:X6}{2}{3:X2}' -f $count, $recordAddress, $hex.ToString(), $checksum))
    }

    $sum = 4
    $sum += ($Entry -shr 16) -band 0xFF
    $sum += ($Entry -shr 8) -band 0xFF
    $sum += $Entry -band 0xFF
    $checksum = 0xFF - ($sum -band 0xFF)
    $lines.Add(('S804{0:X6}{1:X2}' -f $Entry, $checksum))

    return $lines
}

$ca65 = Find-Tool 'ca65'
$ld65 = Find-Tool 'ld65'

if (-not $ca65 -or -not $ld65) {
    throw 'ca65 and ld65 were not found. Install cc65 (V2.19 or later) and try again.'
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$configPath = Join-Path $exampleRoot 'example.cfg'
$includeDirectory = Join-Path $repositoryRoot 'src/inc'

foreach ($source in Get-ChildItem -Path $exampleRoot -Filter '*.s' | Sort-Object Name) {
    $name = [IO.Path]::GetFileNameWithoutExtension($source.Name)
    $objectPath = Join-Path $OutputDirectory "$name.o"
    $binaryPath = Join-Path $OutputDirectory "$name.bin"
    $recordPath = Join-Path $OutputDirectory "$name.srec"

    & $ca65 -g -t none --cpu 65816 -I $includeDirectory -o $objectPath $source.FullName

    if ($LASTEXITCODE -ne 0) {
        throw "ca65 failed on $($source.FullName)."
    }

    & $ld65 $objectPath -o $binaryPath -C $configPath

    if ($LASTEXITCODE -ne 0) {
        throw "ld65 failed on $name."
    }

    $bytes = [IO.File]::ReadAllBytes($binaryPath)
    $records = ConvertTo-SRecords -Data $bytes -Address $loadAddress -Entry $loadAddress
    [IO.File]::WriteAllLines($recordPath, $records)

    Write-Host "Wrote $recordPath ($($bytes.Length) bytes in $($records.Count) records)."
}
