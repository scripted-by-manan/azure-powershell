<#
.SYNOPSIS
This script scans specified Azure subscriptions to identify and optionally delete 
Resource Groups (RGs) that meet criteria such as inactivity, dev/test patterns, and safe deletion.

.DESCRIPTION
- Authenticates into multiple subscriptions
- Filters RGs based on name patterns and last modified time
- Detects and skips critical or dependent resources
- Flags or deletes RGs based on mode (dry-run or cleanup)
- Exports audit report in CSV format

.NOTES
Author: Manan Shah
Script: Weekly DevOps Script Giveaway #4
Disclaimer: Use in test subscriptions first. Not liable for unintended deletions.
#>

param (
    [string[]] $SubscriptionIds,
    [int] $InactiveDaysThreshold = 30,
    [string[]] $NamePatterns = @("*-test*", "*-temp*", "rg-*"),
    [switch] $PerformCleanup = $false,
    [string] $OutputReportPath = "./RG_Cleanup_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

$ErrorActionPreference = "Stop"
Install-Module Az.Accounts, Az.Resources -Scope CurrentUser -Force -AllowClobber

Connect-AzAccount | Out-Null
$finalReport = @()

# Define resource types we consider unsafe to auto-delete
$unsafeTypes = @(
    "Microsoft.Compute/virtualMachines",
    "Microsoft.Network/networkInterfaces",
    "Microsoft.Network/virtualNetworks",
    "Microsoft.Sql/servers",
    "Microsoft.ContainerService/managedClusters"
)

foreach ($subId in $SubscriptionIds) {
    Write-Host "`n🔁 Scanning subscription: $subId" -ForegroundColor Cyan
    Set-AzContext -SubscriptionId $subId | Out-Null

    $allRGs = Get-AzResourceGroup
    foreach ($rg in $allRGs) {
        $rgName = $rg.ResourceGroupName
        $rgMatch = $NamePatterns | Where-Object { $rgName -like $_ }
        if (-not $rgMatch) { continue }

        $resources = Get-AzResource -ResourceGroupName $rgName
        $latestActivity = ($resources | Sort-Object LastModifiedTime -Descending | Select-Object -First 1).LastModifiedTime
        if (-not $latestActivity) { $latestActivity = $rg.Tags["CreatedDate"] }

        $daysSinceLastChange = (New-TimeSpan -Start $latestActivity -End (Get-Date)).Days
        if ($daysSinceLastChange -lt $InactiveDaysThreshold) { continue }

        # Check for critical resources
        $hasUnsafeResources = $resources | Where-Object { $_.ResourceType -in $unsafeTypes }
        if ($hasUnsafeResources) {
            $status = "SKIPPED_CRITICAL_RESOURCES"
            Write-Host "⛔ Skipping $rgName — contains critical resources." -ForegroundColor Yellow
        }
        else {
            # Check for resource lock
            $lock = Get-AzResourceLock -ResourceGroupName $rgName -ErrorAction SilentlyContinue
            if ($lock) {
                $status = "SKIPPED_LOCKED"
                Write-Host "🔒 Skipping $rgName — has resource lock." -ForegroundColor Yellow
            }
            elseif ($PerformCleanup) {
                Write-Host "🗑️ Deleting RG: $rgName" -ForegroundColor Red
                Remove-AzResourceGroup -Name $rgName -Force -AsJob
                $status = "DELETED"
            }
            else {
                Write-Host "🧾 Tagging RG for manual review: $rgName" -ForegroundColor Blue
                Set-AzResourceGroup -Name $rgName -Tag @{MarkedForCleanup="true"} | Out-Null
                $status = "MARKED_FOR_CLEANUP"
            }
        }

        $finalReport += [PSCustomObject]@{
            Subscription   = $subId
            ResourceGroup  = $rgName
            Location       = $rg.Location
            LastModified   = $latestActivity
            DaysInactive   = $daysSinceLastChange
            Status         = $status
        }
    }
}

$finalReport | Export-Csv -NoTypeInformation -Path $OutputReportPath
Write-Host "`n✅ Report saved to: $OutputReportPath" -ForegroundColor Green
