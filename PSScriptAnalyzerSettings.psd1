@{
    # run with: Invoke-ScriptAnalyzer -Path .\PowerShellToolbox -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
    Severity     = @('Error', 'Warning')
    ExcludeRules = @()
}
