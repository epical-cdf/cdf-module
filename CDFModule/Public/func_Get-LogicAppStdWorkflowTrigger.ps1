function Get-LogicAppStdWorkflowTrigger {
   
    Param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $false, HelpMessage = "CDF Configuration hashtable")]
        [hashtable]$CdfConfig,
        [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Name of workflow get triggers for.")]
        [string]$workflowName,
        [Parameter(Mandatory = $false, Position = 2, HelpMessage = "Name of trigger to get details for. If not provided a list of triggers will be returned.")]
        [string]$TriggerName = "",
        [Parameter(Mandatory = $false, HelpMessage = "Get the callback url of the trigger.")]
        [switch]$CallbackUrl,
        [Parameter(Mandatory = $false, HelpMessage = "Get trigger run history.")]
        [switch]$History,
        [Parameter(Mandatory = $false, HelpMessage = "Initiate manual run of the trigger.")]
        [switch]$Run,
        [Parameter(Mandatory = $false, HelpMessage = "Invoke the callback url (if available).")]
        [switch]$Invoke,
        [Parameter(Mandatory = $false, HelpMessage = "Optional body content for manual run and invoke. Defaults to 'POST'")]
        [string]$Method = 'POST',
        [Parameter(Mandatory = $false, HelpMessage = "Optional body content for manual run and invoke.")]
        [Object]$Body,
        [Parameter(Mandatory = $false, HelpMessage = "Optional content type of the body content.")]
        [string]$ContentType = 'application/json',
        [Parameter(Mandatory = $false, HelpMessage = "Indicates local development (Mgmt base url: http://7071)")]
        [switch]$Local
    )

    if ($null -eq $Local -and ($null -eq $CdfConfig.Service -or $false -eq $CdfConfig.Service.IsDeployed )) {
        throw "Function requires a CDF Config with deployed runtime details for Platform, Application, Domain and Service"        
    }
    if ($History -and !$TriggerName) {
        Write-Warning "Trigger name is required for -History, listing triggers."
    }

    if ($TriggerName -and $CallbackUrl) {
        $result = Invoke-LogicAppStdMgmtApi -CdfConfig $CdfConfig -Local:$Local -Method POST /workflows/$workflowName/triggers/$TriggerName/listCallbackUrl
        if ($result.StatusCode -lt 400) {
            if ($result.Content) {
                return ($result.Content | ConvertFrom-Json).value
            }
            else {
                return $result.value

            }
        }
        $result
        throw "Could not get callback url for [$workflowName/$TriggerName]. Did not return successful HTTP Status [$($result.Status)]"

    }

    if ($TriggerName -and $Invoke) {
        $result = Invoke-LogicAppStdMgmtApi -CdfConfig $CdfConfig -Local:$Local -Method POST /workflows/$workflowName/triggers/$TriggerName/listCallbackUrl
        if ($result.StatusCode -lt 400) {
            if ($result.Content) {
                $url = ($result.Content | ConvertFrom-Json).value
                $traceparent = New-CdfTraceParent
                $result = Invoke-RestMethod -Headers @{ traceparent = $traceparent } -SkipHttpErrorCheck -Method $Method -Uri $url -Body $Body -ContentType $ContentType 
                if ($result.StatusCode -lt 400) {
                    if ($result.Content) {
                        $triggers = ConvertFrom-Json -InputObject $result.Content
                        if ($triggers.GetType().Name -eq "PSCustomObject" -and $triggers.properties) {
                            return $triggers.properties
                        }
                        if ($triggers.GetType().Name -eq "PSCustomObject" -and $triggers.error) {
                            return $triggers.error
                        }
                        return $triggers
                    }
                    return $result
                }
                $result
                throw "Initiate callback url for [$TriggerName] was not successful HTTP Status [$($result.StatusCode)]"
            }
        }
        $result
        throw "Could not get callback url for [$workflowName/$TriggerName]. Did not return successful HTTP Status [$($result.Status)]"

    }

    # Trigger a manual run of the workflow
    if ($TriggerName -and $Run) {
        $result = Invoke-LogicAppStdMgmtApi -CdfConfig $CdfConfig -Local:$Local -Method "POST" /workflows/$workflowName/triggers/$TriggerName/run -Body $Body
        if ($result.StatusCode -lt 400) {
            if ($result.Content) {
                $triggers = ConvertFrom-Json -InputObject $result.Content
                if ($triggers.GetType().Name -eq "PSCustomObject" -and $triggers.properties) {
                    return $triggers.properties
                }
                if ($triggers.GetType().Name -eq "PSCustomObject" -and $triggers.error) {
                    return $triggers.error
                }
                return $triggers
            }
            return $result
        }
        throw "Initiate run for [$TriggerName] was not successful HTTP Status [$($result.StatusCode)]"
    }

    if ($TriggerName -and $History) {
        $result = Invoke-LogicAppStdMgmtApi -CdfConfig $CdfConfig -Local:$Local -Method "GET" /workflows/$workflowName/triggers/$TriggerName/histories
        if ($result.StatusCode -lt 400) {
            if ($result.Content) {
                $histories = ConvertFrom-Json -InputObject $result.Content
                if ($histories.GetType().Name -eq "PSCustomObject" -and $histories.value.properties.Length -eq 1) {
                    Write-Verbose "Returning one object"
                    return Format-LogicAppStdHistoryRecord $histories.value
                }
                if ($histories.GetType().Name -eq "PSCustomObject" -and $histories.error) {
                    return $histories.error
                }
                
                Write-Verbose "Returning list of objects"
                $out = @()
                foreach ($entry in $histories.value) {
                    $out += (Format-LogicAppStdHistoryRecord $entry)
                }
                [array]::Reverse($out)
                return $out
            }
        }
    } 
    
    $result = Invoke-LogicAppStdMgmtApi -CdfConfig $CdfConfig -Local:$Local /workflows/$workflowName/triggers
    if ($result.StatusCode -lt 400) {
        if ($Local) {
            $triggers = $result
        }
        else {
            $triggers = ConvertFrom-Json -InputObject $result.Content
              
        }
        if ($triggers.GetType().Name -eq "PSCustomObject" -and $triggers.error) {
            return $triggers.error
        }

        $out = @()
        foreach ($entry in $triggers.value) {
            $out += Format-LogicAppStdTriggerRecord $entry
        }
        [array]::Reverse($out)
        return $out
        #return $triggers.value.properties
    }

    return $null
}


Function Format-LogicAppStdTriggerRecord {
    Param(
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Logic App Standard trigger record.")]
        $Entry
    )
    # Write-Host $Entry
    $culture = Get-Culture
    $dtFormat = $culture.DateTimeFormat.ShortDateTimePattern
    
    $createdTime = [datetime]$Entry.properties.createdTime
    $changedTime = [datetime]$Entry.properties.changedTime

    $props = [ordered] @{
        Name              = $Entry.name
        ProvisioningState = $Entry.properties.provisioningState
        State             = $Entry.properties.state
        Created           = $createdTime.ToString($dtFormat)
        Changed           = $changedTime.ToString($dtFormat)
        WorkflowVersion   = $Entry.properties.workflow.name
    }

    # Few properties - adding all as default
    $DefaultProps = @("Name", "State", "Created", "Changed")
    $DefaultDisplay = New-Object System.Management.Automation.PSPropertySet("DefaultDisplayPropertySet", [string[]]$DefaultProps)
    $PSStandardMembers = [System.Management.Automation.PSMemberInfo[]]@($DefaultDisplay)
    $nvPair = [PSCustomObject] $props
    $nvPair | Add-Member MemberSet PSStandardMembers $PSStandardMembers
         
    return $nvPair
}


Function Format-LogicAppStdHistoryRecord {
    Param(
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Logic App Standard history record.")]
        $Entry
    )
    $culture = Get-Culture
    $dtFormat = $culture.DateTimeFormat.ShortDateTimePattern
    
    $startTime = [datetime]$Entry.properties.startTime
    $endTime = [datetime]$Entry.properties.endTime

    $duration = $endTime - $startTime
    if ($duration.TotalMinutes -ge 1) {
        $durationText = (([math]::Round($duration.TotalMinutes, 2)).ToString()) + ' min'
    }
    elseif ($duration.TotalSeconds -ge 1) {
        $durationText = (([math]::Round($duration.TotalSeconds, 2)).ToString()) + ' s'
    }
    else {
        $durationText = (([math]::Round($duration.TotalMilliseconds, 2)).ToString()) + ' ms'
    }
    
    $props = [ordered] @{
        RunId           = $Entry.name
        Status          = $Entry.properties.status
        CorrelationId   = $Entry.properties.correlation.clientTrackingId
        StartTime       = $startTime.ToString($dtFormat)
        EndTime         = $endTime.ToString($dtFormat)
        Duration        = $durationText
        WorkflowVersion = $Entry.properties.workflow.name
        OutputsLinkUri  = $entry.properties.outputsLink.uri
    }   

    # Few properties - adding all as default
    $DefaultProps = @("RunId", "Status", "CorrelationId", "StartTime", "Duration")
    $DefaultDisplay = New-Object System.Management.Automation.PSPropertySet("DefaultDisplayPropertySet", [string[]]$DefaultProps)
    $PSStandardMembers = [System.Management.Automation.PSMemberInfo[]]@($DefaultDisplay)
    $nvPair = [pscustomobject] $props
    $nvPair | Add-Member MemberSet PSStandardMembers $PSStandardMembers
    return $nvPair
}