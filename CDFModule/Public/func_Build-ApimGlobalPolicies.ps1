Function Build-ApimGlobalPolicies {
    <#
    .SYNOPSIS

    Compiles API policies from domain and application templates

    .DESCRIPTION

    Compiles API policies from domain and application templates

    .PARAMETER DomainName
    Domain name of the service as provided in workflow inputs

    .PARAMETER ServiceName
    Name of the service as provided in workflow inputs

    .PARAMETER ServiceTemplate
    Service template specific as privided in workflow inputs.

    .PARAMETER SharedPath
    File system root path to the apim shared repository contents
    
    .PARAMETER ServicePath
    File system root path to the service's implementation folder, defaults to CWD.

    .PARAMETER OutputPath
    File system path to write resulting policies. Defaults to "build" and appends "<OutputPath>/policies"

    .INPUTS
    None. You cannot pipe objects.

    .OUTPUTS
    None. Writes compiled policies.

    .EXAMPLE
    PS> Build-ApimGlobalPolicies `
        -DomainName "mystic" `
        -ServiceName "api-shaman" `
        -ServiceTemplate "default-spell"

    # Application policy file base:
    <policies>
        <inbound>
           <apim-policy-global />
        </inbound>
        <backend>
           <apim-policy-global />
        </backend>
        <outbound>
           <apim-policy-global />
        </outbound>
        <on-error>
           <apim-policy-global />
        </on-error>
    </policies>

    Domain policy file base:
    <policies>
        <inbound>
           <apim-policy-global />
        </inbound>
        <backend>
           <apim-policy-global />
        </backend>
        <outbound>
           <apim-policy-global />
        </outbound>
        <on-error>
           <apim-policy-global />
        </on-error>
    </policies>

    # Service policy file base:
    <policies>
        <inbound>
            <base />
        </inbound>
        <backend>
            <base />
        </backend>
        <outbound>
            <base />
        </outbound>
        <on-error>
            <base />
        </on-error>
    </policies>

    .LINK
    Build-ApimOperationPolicies

    #>

    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $DomainName = $env:CDF_DOMAIN_NAME,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ServiceName = $env:CDF_SERVICE_NAME,
        [Parameter(Mandatory = $true)]
        [string] $ServiceType = $env:CDF_SERVICE_TYPE,
        [Parameter(Mandatory = $true)]
        [string] $ServiceTemplate = $env:CDF_SERVICE_TEMPLATE,
        [Parameter(Mandatory = $false)]
        [string] $SharedPath = $env:CDF_SHARED_SOURCE_PATH,
        [Parameter(Mandatory = $false)]
        [string] $ServicePath = '.',
        [Parameter(Mandatory = $false)]
        [string] $OutputPath = 'tmp'
       
    )

    $PolicyTypes = $ServiceType.Split('_')

    $GlobalPolicyPath = Resolve-Path "$SharedPath/policies/$($PolicyTypes[0])-global.xml"
    if (-not (Test-Path -Path $GlobalPolicyPath -PathType leaf)) {
        Write-Host "Could not find application policy at path: $GlobalPolicyPath"
        return 1
    }
   
    Write-Verbose "Build-ApimGlobalPolicies - GlobalPolicyPath: $GlobalPolicyPath"
    Write-Verbose "Build-ApimGlobalPolicies - ServicePoliciesPath: $ServicePath/policies"
   
    $PolicyFiles = Get-ChildItem -Path (Resolve-Path -Path "$ServicePath/policies") -Include 'global-*.xml' -File -Name 
    foreach ($PolicyFile in $PolicyFiles) {
        [xml]$PAppGlobal = Get-Content -Path $GlobalPolicyPath
        $PAppGlobal.PreserveWhitespace = true

        $PolicyFilePath = Resolve-Path "$ServicePath/policies/$PolicyFile"
        Write-Host '---------------------------------------'
        Write-Host "Loading XML policy: $PolicyFile"
        Write-Host "Path: $PolicyFilePath"
        [xml]$ServicePolicy = Get-Content -Path $PolicyFilePath

        # Add policy header comment with service identity 
        $PAppGlobal.InsertBefore( $PAppGlobal.CreateComment(" cdf: Begin Global policy ($(Split-Path $GlobalPolicyPath -leaf)) "), $PAppGlobal.policies) | Out-Null
        $PAppGlobal.InsertBefore( $PAppGlobal.CreateComment(" cdf: DateTime Created: $(Get-Date -Format o) "), $PAppGlobal.policies) | Out-Null
        $PAppGlobal.InsertBefore( $PAppGlobal.CreateComment(' cdf: Domain Name:      #{DomainName}# '), $PAppGlobal.policies) | Out-Null
        $PAppGlobal.InsertBefore( $PAppGlobal.CreateComment(' cdf: Service Name:     #{ServiceName}# '), $PAppGlobal.policies) | Out-Null
        $PAppGlobal.InsertBefore( $PAppGlobal.CreateComment(' cdf: Service Type:     #{ServiceType}# '), $PAppGlobal.policies) | Out-Null
        $PAppGlobal.InsertBefore( $PAppGlobal.CreateComment(' cdf: Service Group:    #{ServiceGroup}# '), $PAppGlobal.policies) | Out-Null
        $PAppGlobal.InsertBefore( $PAppGlobal.CreateComment(' cdf: Service Template: #{ServiceTemplate}# '), $PAppGlobal.policies) | Out-Null
        $PAppGlobal.InsertBefore( $PAppGlobal.CreateComment(' cdf: GitHub Repo:      #{BuildRepo}# '), $PAppGlobal.policies) | Out-Null
        $PAppGlobal.InsertBefore( $PAppGlobal.CreateComment(' cdf: GitHub Branch:    #{BuildBranch}# '), $PAppGlobal.policies) | Out-Null
        $PAppGlobal.InsertBefore( $PAppGlobal.CreateComment(' cdf: GitHub Commit:    #{BuildCommit}# '), $PAppGlobal.policies) | Out-Null
        $PAppGlobal.InsertBefore( $PAppGlobal.CreateComment(' cdf: GitHub Workflow:  #{BuildPipeline}# '), $PAppGlobal.policies) | Out-Null
        $PAppGlobal.InsertBefore( $PAppGlobal.CreateComment(' cdf: GitHub Run:       #{BuildRun}# '), $PAppGlobal.policies) | Out-Null
        $PAppGlobal.InsertAfter( $PAppGlobal.CreateComment(" cdf: End Global policy ($(Split-Path $GlobalPolicyPath -leaf)) "), $PAppGlobal.policies) | Out-Null

        #####################################################################
        # Replace "<apim-policy-global />" with domain policy definition
        #####################################################################

        $DomainPolicyPath = Resolve-Path "$ServicePath/../domain-policies/$($ServiceType)_$($DomainName)_global.xml"
        if (Test-Path -Path $DomainPolicyPath -PathType leaf) {

            [xml]$PDomainOperation = Get-Content -Path $DomainPolicyPath
            Write-Host "Policy Path: $DomainPolicyPath"

            Write-Host 'Insert domain policy nodes'
            # Replace inbound
            Write-Host '  Inbound'
            foreach ($node in $PAppGlobal.policies['inbound'].ChildNodes) {
                if ($node.Name -eq 'apim-policy-global') {
                    $PAppGlobal.policies["inbound"].InsertBefore( $PAppGlobal.CreateComment(" cdf: Begin Domain policy ($(Split-Path $DomainPolicyPath -leaf)) "), $node) | Out-Null
                    foreach ($domainPolicyNode in $PDomainOperation.policies['inbound'].ChildNodes) {
                        Write-Host "`tDomain policy node: $($domainPolicyNode.Name)"
                        $ImportedNode = $PAppGlobal.ImportNode($domainPolicyNode, $true)
                        $PAppGlobal.policies['inbound'].InsertBefore($ImportedNode, $node) | Out-Null
                    }
                    $PAppGlobal.policies["inbound"].InsertBefore( $PAppGlobal.CreateComment(" cdf: End Domain policy ($(Split-Path $DomainPolicyPath -leaf)) "), $node) | Out-Null
                    $PAppGlobal.policies['inbound'].RemoveChild($node) | Out-Null
                }
                else {
                    Write-Host "`tExisting policy node: $($node.LocalName)"
                }
            }

            # Replace backend
            Write-Host '  Backend'
            foreach ($node in $PAppGlobal.policies['backend'].ChildNodes) {
                if ($node.Name -eq 'apim-policy-global') {
                    $PAppGlobal.policies["backend"].InsertBefore( $PAppGlobal.CreateComment(" cdf: Begin Domain policy ($(Split-Path $DomainPolicyPath -leaf)) "), $node) | Out-Null
                    foreach ($domainPolicyNode in $PDomainOperation.policies['backend'].ChildNodes) {
                        Write-Host "`tDomain policy node: $($domainPolicyNode.Name)"
                        $ImportedNode = $PAppGlobal.ImportNode($domainPolicyNode, $true)
                        $PAppGlobal.policies['backend'].InsertBefore($ImportedNode, $node) | Out-Null
                    }
                    $PAppGlobal.policies["backend"].InsertBefore( $PAppGlobal.CreateComment(" cdf: End Domain policy ($(Split-Path $DomainPolicyPath -leaf)) "), $node) | Out-Null
                    $PAppGlobal.policies['backend'].RemoveChild($node) | Out-Null
                }
                else {
                    Write-Host "`tExisting policy node: $($node.LocalName)"
                }
            }

            # Replace outbound
            Write-Host '  Outbound'
            foreach ($node in $PAppGlobal.policies['outbound'].ChildNodes) {
                if ($node.Name -eq 'apim-policy-global') {
                    $PAppGlobal.policies["outbound"].InsertBefore( $PAppGlobal.CreateComment(" cdf: Begin Domain policy ($(Split-Path $DomainPolicyPath -leaf)) "), $node) | Out-Null
                    foreach ($domainPolicyNode in $PDomainOperation.policies['outbound'].ChildNodes) {
                        Write-Host "`tDomain policy node: $($domainPolicyNode.Name)"
                        $ImportedNode = $PAppGlobal.ImportNode($domainPolicyNode, $true)
                        $PAppGlobal.policies['outbound'].InsertBefore($ImportedNode, $node) | Out-Null
                    }
                    $PAppGlobal.policies["outbound"].InsertBefore( $PAppGlobal.CreateComment(" cdf: End Domain policy ($(Split-Path $DomainPolicyPath -leaf)) "), $node) | Out-Null
                    $PAppGlobal.policies['outbound'].RemoveChild($node) | Out-Null
                }
                else {
                    Write-Host "`tExisting policy node: $($node.LocalName)"
                }
            }

            # Replace on-error
            Write-Host '  On-Error'
            foreach ($node in $PAppGlobal.policies['on-error'].ChildNodes) {
                if ($node.Name -eq 'apim-policy-global') {
                    $PAppGlobal.policies["on-error"].InsertBefore( $PAppGlobal.CreateComment(" cdf: Begin Domain policy ($(Split-Path $DomainPolicyPath -leaf)) "), $node) | Out-Null
                    foreach ($domainPolicyNode in $PDomainOperation.policies['on-error'].ChildNodes) {
                        Write-Host "`tDomain policy node: $($domainPolicyNode.Name)"
                        $ImportedNode = $PAppGlobal.ImportNode($domainPolicyNode, $true)
                        $PAppGlobal.policies['on-error'].InsertBefore($ImportedNode, $node) | Out-Null
                    }
                    $PAppGlobal.policies["on-error"].InsertBefore( $PAppGlobal.CreateComment(" cdf: End Domain policy ($(Split-Path $DomainPolicyPath -leaf)) "), $node) | Out-Null
                    $PAppGlobal.policies['on-error'].RemoveChild($node) | Out-Null
                }
                else {
                    Write-Host "`tExisting policy node: $($node.LocalName)"
                }
            }
        }
        else {
            Write-Host "Could not find any domain specifc policy at path: $DomainPolicyPath"
        }

        #####################################################################
        # Replace "<apim-policy-global />" with service policy definition
        #####################################################################

        Write-Host 'Insert service policy nodes'
        # Replace inbound
        Write-Host '  Inbound'
        foreach ($node in $PAppGlobal.policies['inbound'].ChildNodes) {
            if ($node.Name -eq 'apim-policy-global') {
                $PAppGlobal.policies["inbound"].InsertBefore( $PAppGlobal.CreateComment(" cdf: Begin Service policy ($(Split-Path $PolicyFilePath -leaf)) "), $node) | Out-Null
                foreach ($servicePolicyNode in $ServicePolicy.policies['inbound'].ChildNodes) {
                    Write-Host "`tService policy node: $($servicePolicyNode.Name)"
                    $ImportedNode = $PAppGlobal.ImportNode($servicePolicyNode, $true)
                    $PAppGlobal.policies['inbound'].InsertBefore($ImportedNode, $node) | Out-Null
                }
                $PAppGlobal.policies["inbound"].InsertBefore( $PAppGlobal.CreateComment(" cdf: End Service policy ($(Split-Path $PolicyFilePath -leaf)) "), $node) | Out-Null
                $PAppGlobal.policies['inbound'].RemoveChild($node) | Out-Null
            }
            else {
                Write-Host "`tExisting policy node: $($node.LocalName)"
            }
        }

        # Replace backend
        Write-Host '  Backend'
        foreach ($node in $PAppGlobal.policies['backend'].ChildNodes) {
            if ($node.Name -eq 'apim-policy-global') {
                $PAppGlobal.policies["backend"].InsertBefore( $PAppGlobal.CreateComment(" cdf: Begin Service policy ($(Split-Path $PolicyFilePath -leaf)) "), $node) | Out-Null
                foreach ($servicePolicyNode in $ServicePolicy.policies['backend'].ChildNodes) {
                    Write-Host "`tService policy node: $($servicePolicyNode.Name)"
                    $ImportedNode = $PAppGlobal.ImportNode($servicePolicyNode, $true)
                    $PAppGlobal.policies['backend'].InsertBefore($ImportedNode, $node) | Out-Null
                }
                $PAppGlobal.policies["backend"].InsertBefore( $PAppGlobal.CreateComment(" cdf: End Service policy ($(Split-Path $PolicyFilePath -leaf)) "), $node) | Out-Null
                $PAppGlobal.policies['backend'].RemoveChild($node) | Out-Null
            }
            else {
                Write-Host "`tExisting policy node: $($node.LocalName)"
            }
        }

        # Replace outbound
        Write-Host '  Outbound'
        foreach ($node in $PAppGlobal.policies['outbound'].ChildNodes) {
            if ($node.Name -eq 'apim-policy-global') {
                $PAppGlobal.policies["outbound"].InsertBefore( $PAppGlobal.CreateComment(" cdf: Begin Service policy ($(Split-Path $PolicyFilePath -leaf)) "), $node) | Out-Null
                foreach ($servicePolicyNode in $ServicePolicy.policies['outbound'].ChildNodes) {
                    Write-Host "`tService policy node: $($servicePolicyNode.Name)"
                    $ImportedNode = $PAppGlobal.ImportNode($servicePolicyNode, $true)
                    $PAppGlobal.policies['outbound'].InsertBefore($ImportedNode, $node) | Out-Null
                }
                $PAppGlobal.policies["outbound"].InsertBefore( $PAppGlobal.CreateComment(" cdf: End Service policy ($(Split-Path $PolicyFilePath -leaf)) "), $node) | Out-Null
                $PAppGlobal.policies['outbound'].RemoveChild($node) | Out-Null
            }
            else {
                Write-Host "`tExisting policy node: $($node.LocalName)"
            }
        }

        # Replace on-error
        Write-Host '  On-Error'
        foreach ($node in $PAppGlobal.policies['on-error'].ChildNodes) {
            if ($node.Name -eq 'apim-policy-global') {
                $PAppGlobal.policies["on-error"].InsertBefore( $PAppGlobal.CreateComment(" cdf: Begin Service policy ($(Split-Path $PolicyFilePath -leaf)) "), $node) | Out-Null
                foreach ($servicePolicyNode in $ServicePolicy.policies['on-error'].ChildNodes) {
                    Write-Host "`tService policy node: $($servicePolicyNode.Name)"
                    $ImportedNode = $PAppGlobal.ImportNode($servicePolicyNode, $true)
                    $PAppGlobal.policies['on-error'].InsertBefore($ImportedNode, $node) | Out-Null
                }
                $PAppGlobal.policies["on-error"].InsertBefore( $PAppGlobal.CreateComment(" cdf: End Service policy ($(Split-Path $PolicyFilePath -leaf)) "), $node) | Out-Null
                $PAppGlobal.policies['on-error'].RemoveChild($node) | Out-Null
            }
            else {
                Write-Host "`tExisting policy node: $($node.LocalName)"
            }
        }

        # Save the new service policy XML to file
        $PAppGlobal.PreserveWhitespace = true
        $PAppGlobal.Save("$OutputPath/policies/$PolicyFile") | Out-Null 

    }
}