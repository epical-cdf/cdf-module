function Get-LogicAppStdWorkflow {
   
    Param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $false, HelpMessage = "CDF Configuration hashtable")]
        [hashtable]$CdfConfig,
        [Parameter(Mandatory = $false, Position = 1, HelpMessage = "Name of workflow to fetch. If not provided a list will returned.")]
        [string]$WorkflowName = "",
        [Parameter(Mandatory = $false, HelpMessage = "Download workflow definition.")]
        [switch]$Download,
        # [Parameter(Mandatory = $false, HelpMessage = "Download workflow definition.")]
        # [switch]$Upload,
        [Parameter(Mandatory = $false, HelpMessage = "Optional path to folder")]
        [string]$FilePath = "$WorkflowName/workflow.json",
        [Parameter(Mandatory = $false, HelpMessage = "Indicates local development (Mgmt base url: http://7071)")]
        [switch]$Local
    )

    if ($null -eq $Local -and ($null -eq $CdfConfig.Service -or $false -eq $CdfConfig.Service.IsDeployed )) {
        throw "Function requires a CDF Config with deployed runtime details for Platform, Application, Domain and Service"        
    }

    if ($Download -and $WorkflowName) {
        $result = Invoke-WebSiteAdminVfsApi $CdfConfig /site/wwwroot/$WorkflowName/workflow.json
        if ($result.StatusCode -eq 200) {
            if ($result.Content) {
                $result.Content | Set-Content $FilePath
            }
            Write-Host "Wrote workflow definition [$WorkflowName] to $FilePath"
            return $null
        }
        $result
        throw "HTTP Status [$($result.StatusCode)] - did not fetch workflow definition [$WorkflowName]"
        
    }

    # if ($Upload -and $WorkflowName -and $FilePath) {
    #     if (Test-Path $FilePath) {
    #         $definitionJson = Get-Content -Raw -Path $FilePath
    #         $request = Invoke-WebSiteAdminVfsApi $CdfConfig /site/wwwroot/$WorkflowName/workflow.json
    #         $etag = $request.Headers.ETag
    #         $result = Invoke-WebSiteAdminVfsApi $CdfConfig /site/wwwroot/$WorkflowName/workflow.json -Method PUT -Body $definitionJson -ETag $etag
    #         if ($result.StatusCode -eq 200) {
    #             if ($result.Content) {
    #                 $result.Content | Set-Content $FilePath
    #             }
    #             Write-Host "Wrote workflow definition [$WorkflowName] to $FilePath"
    #             return $null
    #         }
    #         $result
    #         throw "HTTP Status [$($result.StatusCode)] - did not fetch workflow definition [$WorkflowName]"
    #     }
    #     else {
    #         throw "Could not find file path [$FilePath] for workflow definition [$WorkflowName]."

    #     }
        
    # }

    $result = Invoke-LogicAppStdMgmtApi -CdfConfig $CdfConfig -Local:$Local /workflows/$WorkflowName
    if ($result.StatusCode -lt 400) {
        if ($result.Content) {
            # $workflows = ConvertFrom-Json -InputObject $result.Content -AsHashtable
            $workflows = ConvertFrom-Json -InputObject $result.Content
            if ($workflows -and $workflows.GetType().Name -eq "PSCustomObject" -and $workflows.value) {
                return (Format-LogicAppStdWorkflowRecord $workflows.value)
                #return $workflows.value
            }
            
            $out = @()
            foreach ($entry in $workflows) {
                $out += (Format-LogicAppStdWorkflowRecord $entry)
            }
            return [array] $out

            # return $workflows
        }
    }
    $result
    throw "HTTP Status [$($result.StatusCode)] - not succesful"
}

Function Format-LogicAppStdWorkflowRecord {
    Param(
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Logic App Standard workflow record.")]
        $Entry
    )
    
    $triggers = @()
    foreach ($trigger in $Entry.triggers) {
        $triggerName = $trigger.PSObject.Properties.Name 
        $triggerType = $trigger.PSObject.Properties.Value.type
        $triggerKind = $trigger.PSObject.Properties.Value.kind
        $triggers += [ordered] @{
            Name = $triggerName
            Type = $triggerType
            Kind = $triggerKind
        }
    }
    
    $props = [ordered] @{
        Name        = $Entry.name
        Kind        = $Entry.kind
        TriggerName = $triggers.Length -gt 0 ? $triggers[0].Name: ''
        TriggerKind = $triggers.Length -gt 0 ? $triggers[0].Kind: ''
        TriggerType = $triggers.Length -gt 0 ? $triggers[0].Type: ''
        IsEnabled   = !$Entry.isDisabled
        State       = $Entry.health.state;
        
    }

    $DefaultProps = @("Name", "TriggerName", "TriggerType", "IsEnabled")
    $DefaultDisplay = New-Object System.Management.Automation.PSPropertySet("DefaultDisplayPropertySet", [string[]]$DefaultProps)
    $PSStandardMembers = [System.Management.Automation.PSMemberInfo[]]@($DefaultDisplay)
    $nvPair = [PSCustomObject] $props
    $nvPair | Add-Member MemberSet PSStandardMembers $PSStandardMembers
    
    return $nvPair
}