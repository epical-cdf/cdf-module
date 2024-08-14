function Get-LogicAppStdWorkflowTriggerHistory {

    Param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $false, HelpMessage = "CDF Configuration hashtable")]
        [hashtable]$CdfConfig,
        [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Name of workflow get triggers for.")]
        [string]$workflowName,
        [Parameter(Mandatory = $true, Position = 2, HelpMessage = "Name of history to get details for.")]
        [string]$triggerName,
        [Parameter(Mandatory = $false, Position = 3, HelpMessage = "Name of history/run to get details for. If not provided a list of history runs will be returned.")]
        [string]$historyName = "",
        [Parameter(Mandatory = $false, HelpMessage = "Get the output from trigger run.")]
        [switch]$Output,
        [Parameter(Mandatory = $false, HelpMessage = "Indicates local development (Mgmt base url: http://7071)")]
        [switch]$Local
    )

    if ($null -eq $Local -and ($null -eq $CdfConfig.Service -or $false -eq $CdfConfig.Service.IsDeployed )) {
        throw "Function requires a CDF Config with deployed runtime details for Platform, Application, Domain and Service"
    }

    if ($Output -and !$historyName) {
        Write-Warning "History name is required for -Output, listing runs history."
    }
    elseif ($Output -and $historyName) {
        $result = Invoke-LogicAppStdMgmtApi -CdfConfig $CdfConfig -Local:$Local /workflows/$workflowName/triggers/$triggerName/histories/$historyName
        if ($result.Status -lt 400) {
            if ($result.Content) {
                $history = ConvertFrom-Json -InputObject $result.Content
                $result = Invoke-WebRequest -Method GET -Uri $history.properties.outputsLink.uri
                return $result
            }
        }
        throw "Getting run [$historyName] was not successful HTTP Status [$($result.Status)]"
    }

    $result = Invoke-LogicAppStdMgmtApi -CdfConfig $CdfConfig -Local:$Local /workflows/$workflowName/triggers/$triggerName/histories/$historyName
    if ($result.Status -lt 400) {
        if ($result.Content) {
            $history = ConvertFrom-Json -InputObject $result.Content
            if ($history.GetType().Name -eq "PSCustomObject" -and $history.properties) {
                return  [pscustomobject] (Format-LogicAppStdHistoryRecord $history.properties)
                #return $history.properties
            }
            if ($history.GetType().Name -eq "PSCustomObject" -and $history.value.Length -gt 0) {
                $out = @()
                foreach ($entry in $history.value) {
                    $out += [pscustomobject] (Format-LogicAppStdHistoryRecord $entry)
                }
                [array]::Reverse($out)
                return $out
            }
            return $history.value

            # Write-Host "Returning array history.properties"
            return $history.properties
        }
    }
    return $null
}
