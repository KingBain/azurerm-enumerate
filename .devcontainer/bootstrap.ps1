# .devcontainer/bootstrap.ps1
# Installs Az + Microsoft.Graph PowerShell modules system-wide for the devcontainer.

$ErrorActionPreference = 'Stop'

# Ensure NuGet provider + trust PSGallery to avoid prompts
if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
  Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
}
if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
  Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
}

# Optional pin (set via devcontainer.json -> containerEnv: AZ_PWSH_VERSION)
$azVersion = $env:AZ_PWSH_VERSION

# Install Az meta-module (brings in Az.Accounts, Az.Resources, etc.)
$azParams = @{
  Name         = 'Az'
  Scope        = 'AllUsers'
  AllowClobber = $true
  Force        = $true
}
if ($azVersion) { $azParams['RequiredVersion'] = $azVersion }
Install-Module @azParams

# Install Microsoft Graph rollup (or replace with specific submodules to slim image)
Install-Module -Name Microsoft.Graph -Scope AllUsers -AllowClobber -Force

# Warm up formats/types once so first run in terminal is snappy
Import-Module Az -ErrorAction Stop
Import-Module Microsoft.Graph -ErrorAction Stop

# Quick versions
Write-Host "Az version:" (Get-Module Az -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
Write-Host "Microsoft.Graph version:" (Get-Module Microsoft.Graph -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
