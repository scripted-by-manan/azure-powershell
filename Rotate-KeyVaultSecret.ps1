<#
.SYNOPSIS
    Rotates secrets in Azure Key Vault and updates bound Azure App Services or Function Apps.

.DESCRIPTION
    - Generates a new value for a given secret
    - Sets the new version in Key Vault
    - Optionally updates linked App Settings or triggers restarts
    - Logs all actions

.NOTES
    Author: Manan Shah
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory=$true)]
    [string[]]$SecretNames,

    [switch]$RestartApps,

    [string[]]$LinkedAppNames = @()  # Optional: Azure Web Apps/Function Apps to update
)

Connect-AzAccount
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

foreach ($secret in $SecretNames) {
    # 1. Generate new secret value (example: GUID-based, customize as needed)
    $newSecretValue = [guid]::NewGuid().ToString("N")
    $newSecretName = "$secret"

    # 2. Set new version of the secret
    Write-Host "Rotating secret: $newSecretName"
    $setSecret = Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $newSecretName -SecretValue (ConvertTo-SecureString $newSecretValue -AsPlainText -Force)

    Write-Host "Secret rotated: $newSecretName @ $($setSecret.Version)"
}

# 3. Update connected App Services / Function Apps
foreach ($app in $LinkedAppNames) {
    Write-Host "`n Updating App Service Config: $app"

    $appSettings = Get-AzWebApp -Name $app
    $currentSettings = (Get-AzWebApp -Name $app).SiteConfig.AppSettings

    $newSettings = @()
    foreach ($setting in $currentSettings) {
        if ($SecretNames -contains $setting.Name) {
            $newValue = "@Microsoft.KeyVault(SecretUri=https://$KeyVaultName.vault.azure.net/secrets/$($setting.Name))"
            $newSettings += @{ Name = $setting.Name; Value = $newValue }
            Write-Host "🔧 Updating App Setting: $($setting.Name)"
        } else {
            $newSettings += @{ Name = $setting.Name; Value = $setting.Value }
        }
    }

    Set-AzWebApp -Name $app -AppSettings $newSettings
    Write-Host "App settings updated."

    if ($RestartApps) {
        Restart-AzWebApp -Name $app
        Write-Host "App restarted: $app"
    }
}

Write-Host "`n Secret rotation complete at $timestamp."
