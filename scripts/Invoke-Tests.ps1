<#
.SYNOPSIS
Runs the Pester tests the way the CI workflow does.

.DESCRIPTION
Needs Pester 5. Writes TestResults.xml (NUnit format) in the repository root and
exits with the number of failed tests, so a failure fails the build. With -Coverage
it also measures code coverage of the PowerShellToolbox folder (coverage.xml).

.EXAMPLE
./scripts/Invoke-Tests.ps1 -Coverage
#>
[CmdletBinding()]
param(
    [switch]$Coverage
)

$root = Split-Path -Parent $PSScriptRoot
Import-Module -Name Pester -MinimumVersion 5.0.0 -ErrorAction Stop

$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path $root 'tests'
$configuration.Run.Exit = $true
$configuration.Output.Verbosity = 'Detailed'
$configuration.TestResult.Enabled = $true
$configuration.TestResult.OutputPath = Join-Path $root 'TestResults.xml'

if ($Coverage) {
    $configuration.CodeCoverage.Enabled = $true
    $configuration.CodeCoverage.Path = Join-Path $root 'PowerShellToolbox'
    $configuration.CodeCoverage.OutputPath = Join-Path $root 'coverage.xml'
}

Invoke-Pester -Configuration $configuration
