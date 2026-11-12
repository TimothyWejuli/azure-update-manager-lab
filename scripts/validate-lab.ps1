param(
    [string]$ResourceGroup = "rg-aumlab",
    [Parameter(Mandatory)][string]$SubscriptionId,
    [string[]]$VMs = @("DC01","WS01","WS02")
)

# Reuse an existing Az login if there is one
$ctx = Get-AzContext -ErrorAction SilentlyContinue
if (-not $ctx) { Connect-AzAccount -SubscriptionId $SubscriptionId | Out-Null }
else { Set-AzContext -SubscriptionId $SubscriptionId | Out-Null }

$results = @()
$allPass = $true

Write-Host "`n=== Azure Update Manager Compliance Validation ===" -ForegroundColor Cyan
Write-Host "Resource group: $ResourceGroup"
Write-Host "Running on-demand patch assessment (about 1-3 minutes per VM)...`n"

foreach ($vm in $VMs) {
    try {
        $a = Invoke-AzVMPatchAssessment -ResourceGroupName $ResourceGroup -VMName $vm -ErrorAction Stop
        $critical  = [int]$a.CriticalAndSecurityPatchCount
        $other     = [int]$a.OtherPatchCount
        $compliant = ($a.Status -eq "Succeeded") -and ($critical -eq 0)
        $status    = if ($compliant) { "PASS" } else { "FAIL" }
        $assessStatus = $a.Status
        $started   = $a.StartDateTime
    }
    catch {
        $critical = $null; $other = $null; $compliant = $false
        $status = "ERROR"; $assessStatus = $_.Exception.Message; $started = $null
    }

    if (-not $compliant) { $allPass = $false }
    $color = switch ($status) { "PASS" {"Green"} "FAIL" {"Yellow"} default {"Red"} }
    Write-Host ("[{0}] {1} -- Critical/Security missing: {2} | Other: {3} | Status: {4}" -f $status, $vm, $critical, $other, $assessStatus) -ForegroundColor $color

    $results += [PSCustomObject]@{
        VMName                   = $vm
        AssessmentStatus         = $assessStatus
        CriticalAndSecurityCount = $critical
        OtherPatchCount          = $other
        AssessmentStarted        = $started
        Compliant                = $compliant
        Result                   = $status
    }
}

Write-Host ""
Write-Host "Overall: $(if ($allPass) {'ALL PASS'} else {'FAILURES DETECTED'})" `
    -ForegroundColor $(if ($allPass) {"Green"} else {"Red"})

$reportPath = Join-Path (Get-Location) "aum-compliance-report.json"
@{
    GeneratedAt   = (Get-Date -Format "o")
    Subscription  = $SubscriptionId
    ResourceGroup = $ResourceGroup
    VMs           = $results
} | ConvertTo-Json -Depth 5 | Out-File $reportPath -Encoding UTF8

$results | Format-Table VMName, Result, CriticalAndSecurityCount, OtherPatchCount, AssessmentStatus -AutoSize
Write-Host "Report exported: $reportPath" -ForegroundColor Cyan
