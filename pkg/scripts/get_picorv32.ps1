# Windows PowerShell: download official upstream RTL, rather than a modified copy.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
New-Item -ItemType Directory -Force -Path 'third_party' | Out-Null
$Uri = 'https://raw.githubusercontent.com/YosysHQ/picorv32/main/picorv32.v'
Invoke-WebRequest -Uri $Uri -OutFile 'third_party/picorv32.v'
Write-Host 'Downloaded third_party/picorv32.v. Review upstream license and record a pinned commit for production.'
