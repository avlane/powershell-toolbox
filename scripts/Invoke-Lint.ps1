<#
.SYNOPSIS
Runs PSScriptAnalyzer over the module and the scripts with the repository settings.

.DESCRIPTION
Prints every finding and exits with 1 if there is one of severity Error, or, with
-Strict, of severity Warning too. Needs the PSScriptAnalyzer module
(Install-Module PSScriptAnalyzer).

.EXAMPLE
./scripts/Invoke-Lint.ps1 -Strict
#>
[CmdletBinding()]
param(
    [switch]$Strict
)

$root = Split-Path -Parent $PSScriptRoot
Import-Module -Name PSScriptAnalyzer -ErrorAction Stop

$paths = @((Join-Path $root 'PowerShellToolbox'), (Join-Path $root 'scripts'))
$results = foreach ($path in $paths) {
    Invoke-ScriptAnalyzer -Path $path -Recurse -Settings (Join-Path $root 'PSScriptAnalyzerSettings.psd1')
}

$results | Format-Table -AutoSize -Property Severity, RuleName, ScriptName, Line, Message

$failing = @($results | Where-Object { $_.Severity -eq 'Error' -or ($Strict -and $_.Severity -eq 'Warning') })
Write-Host "$(@($results).Count) finding(s), $($failing.Count) of them failing."
if ($failing.Count -gt 0) { exit 1 }
