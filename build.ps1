#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Assembles and links the HB816 KERNAL into its 512 KiB ROM image.

.DESCRIPTION
    Assembles every source under src/ with ca65 (--cpu 65816), links the objects
    with the repository's hb816-kernal.cfg, and installs hb816-kernal.bin plus
    its VICE label file and link map into the output directory.

    This is the standalone build: unlike the emulator repository's corpus
    scripts, which warn and do nothing when cc65 is absent so that tests can
    skip, this script fails outright - a standalone build that silently does
    nothing is a footgun.

.PARAMETER OutputDirectory
    Directory the ROM, label file and map are written to. Defaults to out/
    under this repository.

.PARAMETER WorkDirectory
    Directory the object files are kept in. Defaults to out/obj/.

.EXAMPLE
    pwsh build.ps1
#>

[CmdletBinding()]
param(
    [string] $OutputDirectory,
    [string] $WorkDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repositoryRoot = $PSScriptRoot

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repositoryRoot 'out'
}

if (-not $WorkDirectory) {
    $WorkDirectory = Join-Path $OutputDirectory 'obj'
}

$romSize = 524288

function Find-Tool {
    param([string] $Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue

    if ($command) {
        return $command.Source
    }

    # cc65 is commonly unpacked rather than installed, so a handful of usual
    # places are worth looking in before giving up.
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

$ca65 = Find-Tool 'ca65'
$ld65 = Find-Tool 'ld65'

if (-not $ca65 -or -not $ld65) {
    throw 'ca65 and ld65 were not found. Install cc65 (V2.19 or later) and try again.'
}

Write-Host "Using $ca65"
Write-Host (& $ca65 --version 2>&1 | Select-Object -First 1)

New-Item -ItemType Directory -Force -Path $WorkDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$configPath = Join-Path $repositoryRoot 'hb816-kernal.cfg'
$binaryPath = Join-Path $OutputDirectory 'hb816-kernal.bin'
$labelPath = Join-Path $OutputDirectory 'hb816-kernal.lbl'
$mapPath = Join-Path $OutputDirectory 'hb816-kernal.map'

$sourceDirectory = Join-Path $repositoryRoot 'src'
$includeDirectory = Join-Path $sourceDirectory 'inc'
$assetsDirectory = Join-Path $repositoryRoot 'assets'

$sources = Get-ChildItem -Path $sourceDirectory -Recurse -Filter '*.s' | Sort-Object FullName

if (-not $sources) {
    throw "No sources were found under $sourceDirectory."
}

$objects = @()

foreach ($source in $sources) {
    $objectName = [IO.Path]::ChangeExtension($source.Name, '.o')
    $objectPath = Join-Path $WorkDirectory $objectName

    & $ca65 -g -t none --cpu 65816 -I $includeDirectory --bin-include-dir $assetsDirectory `
        -o $objectPath $source.FullName

    if ($LASTEXITCODE -ne 0) {
        throw "ca65 failed on $($source.FullName)."
    }

    $objects += $objectPath
}

& $ld65 @objects -o $binaryPath -m $mapPath -C $configPath -Ln $labelPath

if ($LASTEXITCODE -ne 0) {
    throw 'ld65 failed to link the HB816 KERNAL.'
}

$size = (Get-Item -LiteralPath $binaryPath).Length

if ($size -ne $romSize) {
    Remove-Item -LiteralPath $binaryPath -Force
    throw "The linked image is $size bytes and the ROM is $romSize."
}

Write-Host "Wrote $binaryPath ($size bytes)."
Write-Host "Wrote $labelPath."
Write-Host "Wrote $mapPath."
