# PowerShellToolbox - loader.
# Every function lives in its own file: Private/ holds the helpers, Public/ the
# commands. The file name is the function name, and the public names are exported.

$privateFiles = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$publicFiles = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($privateFiles + $publicFiles)) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to load $($file.FullName): $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function $publicFiles.BaseName
