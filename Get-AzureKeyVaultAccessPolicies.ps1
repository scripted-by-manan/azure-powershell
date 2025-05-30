<#
.SYNOPSIS
    Audits Azure Key Vault access policies across multiple subscriptions.

.DESCRIPTION
    This script authenticates to Azure, loops through a defined list of subscriptions,
    and identifies all Key Vaults that follow a specific naming convention (e.g., "kv-name-*").
    For each Key Vault found, it extracts access policies, including key, secret, and certificate permissions.
    The results are exported to a timestamped Excel file using the ImportExcel module for easy review.

.USE CASES
    - Security audits and access reviews
    - RBAC cleanup and policy validation
    - Gaining visibility into over-provisioned roles
    - Reporting for compliance or internal governance

.NOTES
    - Requires Az PowerShell module and ImportExcel module.
    - Make sure you have sufficient permissions to read Key Vaults and access policies.
    - Customize the vault name prefix or output file path as needed.

.AUTHOR
    Manan Shah
#>

# Install the ImportExcel module if not already installed
# Install-Module -Name ImportExcel -Scope CurrentUser -Force

# Authenticate to Azure
Connect-AzAccount

# Define the subscription names
$subscriptions = @{
    Prod = "Production"
    Sandbox = "Sandbox"
    #Staging = "Staging"
}

# Create an empty array to store results
$results = @()

foreach ($sub in $subscriptions.GetEnumerator()) {
    # Select the subscription
    $subscription = Get-AzSubscription -SubscriptionName $sub.Value
    if (-not $subscription) {
        Write-Warning "Subscription not found: $($sub.Value)"
        continue
    }
    Set-AzContext -SubscriptionId $subscription.Id

    # Get all the key vaults starting with 'kv-name-'
    $keyVaults = Get-AzKeyVault | Where-Object { $_.VaultName.StartsWith("kv-name-") }
    if (-not $keyVaults) {
        Write-Warning "No Key Vaults found in subscription: $($sub.Value)"
        continue
    }

    foreach ($kv in $keyVaults) {
        # Get the access policies for each Key Vault
        $accessPolicies = (Get-AzKeyVault -VaultName $kv.VaultName).AccessPolicies

        if (-not $accessPolicies) {
            Write-Warning "No Access Policies found for Key Vault: $($kv.VaultName)"
            continue
        }

        foreach ($policy in $accessPolicies) {
            # Extract the necessary information
            $appName = $policy.DisplayName
            $groupName = if ($policy.ObjectType -eq 'Group') { $policy.DisplayName } else { $null }
            $keyPermissions = ($policy.PermissionsToKeys -join ', ')
            $secretPermissions = ($policy.PermissionsToSecrets -join ', ')
            $certificatePermissions = ($policy.PermissionsToCertificates -join ', ')

            # Create a custom object for each access policy
            $results += [pscustomobject]@{
                'Name of keyvault'           = $kv.VaultName
                'Application name'           = $appName
                'Group name'                 = $groupName
                'Key Permission'             = $keyPermissions
                'Secret Permissions'         = $secretPermissions
                'Certificate Permissions'    = $certificatePermissions
            }
        }
    }
}

if ($results.Count -eq 0) {
    Write-Warning "No data found to export to Excel. Please check the Azure permissions and the presence of Key Vaults."
    exit
}

# Define the file path with a timestamp to prevent overwriting issues
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$filePath = "C:\scripts\KeyVaultAccessPolicies_$timestamp.xlsx"

# Export the results to an Excel file
$results | Export-Excel -Path $filePath -WorksheetName 'Access Policies' -AutoFilter

# Provide the path to the output file
Write-Host "The Excel file has been created at: $filePath"
