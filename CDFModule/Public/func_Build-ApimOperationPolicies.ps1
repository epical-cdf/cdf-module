Function Build-ApimOperationPolicies {
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

    .PARAMETER ServiceTemplate
    Service template specific as privided in workflow inputs.

    .PARAMETER SharedPath
    File system root path to the apim shared repository contents

    .PARAMETER ServicePath
    File system root path to the service's implementation folder, defaults to CWD.

    .PARAMETER OutputPath
    File system path to write resulting policies. Defaults to <api folder>/build/policies

    .INPUTS
    None. You cannot pipe objects.

    .OUTPUTS
    None. Writes compiled policies.

    .EXAMPLE
    PS> Build-ApimOperationPolicies `
        -DomainName "mystic" `
        -ServiceName "api-shaman" `
        -ServiceTemplate "default-spell"


    # Application policy file base:
    <policies>
        <inbound>
        <apim-policy-operation />
        </inbound>
        <backend>
        <apim-policy-operation />
        </backend>
        <outbound>
        <apim-policy-operation />
        </outbound>
        <on-error>
        <apim-policy-operation />
        </on-error>
    </policies>

    # Domain policy file base:
    <policies>
        <inbound>
           <apim-policy-operation />
        </inbound>
        <backend>
           <apim-policy-operation />
        </backend>
        <outbound>
           <apim-policy-operation />
        </outbound>
        <on-error>
           <apim-policy-operation />
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
    Build-ApimGlobalPolicies

    #>

    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $DomainName = $env:CDF_DOMAIN_NAME,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $false)]
        [string] $ServiceName = $env:CDF_SERVICE_NAME,
        [ValidateNotNullOrEmpty()]
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

    $OperationPolicyPath = "$SharedPath/policies/$($PolicyTypes[0])-operation.xml"
    if (-not (Test-Path -Path $OperationPolicyPath -PathType leaf)) {
        Write-Host "Could not find application policy at path: $OperationPolicyPath"
        return 1
    }

    Write-Verbose "Build-ApimOperationPolicies - OperationPolicyPath: $OperationPolicyPath"
    Write-Verbose "Build-ApimOperationPolicies - ServicePoliciesPath: $ServicePath/policies"

    $PolicyFiles = Get-ChildItem -Path "$ServicePath/policies" -Include 'operation-*.xml' -File -Name
    foreach ($PolicyFile in $PolicyFiles) {
        [xml]$PAppOperation = Get-Content -Path $OperationPolicyPath
        $PAppOperation.PreserveWhitespace = true

        $PolicyFilePath = Resolve-Path "$ServicePath/policies/$PolicyFile"
        Write-Host '---------------------------------------'
        Write-Host "Loading XML policy: $PolicyFile"
        Write-Host "Path: $PolicyFilePath"
        [xml]$ServicePolicy = Get-Content -Path $PolicyFilePath
        $ServicePolicy.PreserveWhitespace = true

        # Add policy header comment with service identity
        $PAppOperation.InsertBefore( $PAppOperation.CreateComment(" cdf: Begin Global policy ($(Split-Path $OperationPolicyPath -leaf)) "), $PAppOperation.policies) | Out-Null
        $PAppOperation.InsertBefore( $PAppOperation.CreateComment(" cdf: DateTime Created: $(Get-Date -Format o) "), $PAppOperation.policies) | Out-Null
        $PAppOperation.InsertBefore( $PAppOperation.CreateComment(' cdf: Domain Name:      #{DomainName}# '), $PAppOperation.policies) | Out-Null
        $PAppOperation.InsertBefore( $PAppOperation.CreateComment(' cdf: Service Name:     #{ServiceName}# '), $PAppOperation.policies) | Out-Null
        $PAppOperation.InsertBefore( $PAppOperation.CreateComment(' cdf: Service Type:     #{ServiceType}# '), $PAppOperation.policies) | Out-Null
        $PAppOperation.InsertBefore( $PAppOperation.CreateComment(' cdf: Service Group:    #{ServiceGroup}# '), $PAppOperation.policies) | Out-Null
        $PAppOperation.InsertBefore( $PAppOperation.CreateComment(' cdf: Service Template: #{ServiceTemplate}# '), $PAppOperation.policies) | Out-Null
        $PAppOperation.InsertBefore( $PAppOperation.CreateComment(' cdf: Build Repo:      #{BuildRepo}# '), $PAppOperation.policies) | Out-Null
        $PAppOperation.InsertBefore( $PAppOperation.CreateComment(' cdf: Build Branch:    #{BuildBranch}# '), $PAppOperation.policies) | Out-Null
        $PAppOperation.InsertBefore( $PAppOperation.CreateComment(' cdf: Build Commit:    #{BuildCommit}# '), $PAppOperation.policies) | Out-Null
        $PAppOperation.InsertBefore( $PAppOperation.CreateComment(' cdf: Build Workflow:  #{BuildPipeline}# '), $PAppOperation.policies) | Out-Null
        $PAppOperation.InsertBefore( $PAppOperation.CreateComment(' cdf: Build Run:       #{BuildRun}# '), $PAppOperation.policies) | Out-Null
        $PAppOperation.InsertAfter( $PAppOperation.CreateComment(" cdf: End Global policy ($(Split-Path $OperationPolicyPath -leaf)) "), $PAppOperation.policies) | Out-Null

        #####################################################################
        # Replace "<apim-policy-operation />" with domain policy definition
        #####################################################################

        $DomainPolicyPath = Resolve-Path "$ServicePath/../domain-policies/$($ServiceType)_$($DomainName)_operation.xml"
        if (Test-Path -Path $DomainPolicyPath -PathType leaf) {

            [xml]$PDomainOperation = Get-Content -Path $DomainPolicyPath

            Write-Host 'Insert domain policy nodes'
            # Replace inbound
            Write-Host '  Inbound'
            foreach ($node in $PAppOperation.policies['inbound'].ChildNodes) {
                if ($node.Name -eq 'apim-policy-operation') {
                    $PAppOperation.policies["inbound"].InsertBefore( $PAppOperation.CreateComment(" cdf: Begin Domain policy ($(Split-Path $DomainPolicyPath -leaf)) "), $node) | Out-Null
                    foreach ($domainPolicyNode in $PDomainOperation.policies['inbound'].ChildNodes) {
                        Write-Host "`tDomain policy node: $($domainPolicyNode.Name)"
                        $ImportedNode = $PAppOperation.ImportNode($domainPolicyNode, $true)
                        $PAppOperation.policies['inbound'].InsertBefore($ImportedNode, $node) | Out-Null
                    }
                    $PAppOperation.policies["inbound"].InsertBefore( $PAppOperation.CreateComment(" cdf: End Domain policy ($(Split-Path $DomainPolicyPath -leaf)) "), $node) | Out-Null
                    $PAppOperation.policies['inbound'].RemoveChild($node) | Out-Null
                }
                else {
                    Write-Host "`tOperation policy node: $($node.LocalName)"
                }
            }

            # Replace backend
            Write-Host '  Backend'
            foreach ($node in $PAppOperation.policies['backend'].ChildNodes) {
                if ($node.Name -eq 'apim-policy-operation') {
                    $PAppOperation.policies["backend"].InsertBefore( $PAppOperation.CreateComment(" cdf: Begin Domain policy ($(Split-Path $DomainPolicyPath -leaf)) "), $node) | Out-Null
                    foreach ($domainPolicyNode in $PDomainOperation.policies['backend'].ChildNodes) {
                        Write-Host "`tDomain policy node: $($domainPolicyNode.Name)"
                        $ImportedNode = $PAppOperation.ImportNode($domainPolicyNode, $true)
                        $PAppOperation.policies['backend'].InsertBefore($ImportedNode, $node) | Out-Null
                    }
                    $PAppOperation.policies["backend"].InsertBefore( $PAppOperation.CreateComment(" cdf: End Domain policy ($(Split-Path $DomainPolicyPath -leaf)) "), $node) | Out-Null
                    $PAppOperation.policies['backend'].RemoveChild($node) | Out-Null
                }
                else {
                    Write-Host "`tOperation policy node: $($node.LocalName)"
                }
            }

            # Replace outbound
            Write-Host '  Outbound'
            foreach ($node in $PAppOperation.policies['outbound'].ChildNodes) {
                if ($node.Name -eq 'apim-policy-operation') {
                    $PAppOperation.policies["outbound"].InsertBefore( $PAppOperation.CreateComment(" cdf: Begin Domain policy ($(Split-Path $DomainPolicyPath -leaf)) "), $node) | Out-Null
                    foreach ($domainPolicyNode in $PDomainOperation.policies['outbound'].ChildNodes) {
                        Write-Host "`tDomain policy node: $($domainPolicyNode.Name)"
                        $ImportedNode = $PAppOperation.ImportNode($domainPolicyNode, $true)
                        $PAppOperation.policies['outbound'].InsertBefore($ImportedNode, $node) | Out-Null
                    }
                    $PAppOperation.policies["outbound"].InsertBefore( $PAppOperation.CreateComment(" cdf: End Domain policy ($(Split-Path $DomainPolicyPath -leaf)) "), $node) | Out-Null
                    $PAppOperation.policies['outbound'].RemoveChild($node) | Out-Null
                }
                else {
                    Write-Host "`tOperation policy node: $($node.LocalName)"
                }
            }

            # Replace on-error
            Write-Host '  On-Error'
            foreach ($node in $PAppOperation.policies['on-error'].ChildNodes) {
                if ($node.Name -eq 'apim-policy-operation') {
                    $PAppOperation.policies["on-error"].InsertBefore( $PAppOperation.CreateComment(" cdf: Begin Domain policy ($(Split-Path $DomainPolicyPath -leaf)) "), $node) | Out-Null
                    foreach ($domainPolicyNode in $PDomainOperation.policies['on-error'].ChildNodes) {
                        Write-Host "`tDomain policy node: $($domainPolicyNode.Name)"
                        $ImportedNode = $PAppOperation.ImportNode($domainPolicyNode, $true)
                        $PAppOperation.policies['on-error'].InsertBefore($ImportedNode, $node) | Out-Null
                    }
                    $PAppOperation.policies["on-error"].InsertBefore( $PAppOperation.CreateComment(" cdf: End Domain policy ($(Split-Path $DomainPolicyPath -leaf)) "), $node) | Out-Null
                    $PAppOperation.policies['on-error'].RemoveChild($node) | Out-Null
                }
                else {
                    Write-Host "`tOperation policy node: $($node.LocalName)"
                }
            }
        }
        else {
            Write-Host "Could not find any domain specifc policy at path: $DomainPolicyPath"
        }

        #####################################################################
        # Replace "<apim-policy-operation />" with service policy definition
        #####################################################################

        Write-Host 'Insert service policy nodes'
        # Replace inbound
        Write-Host '  Inbound'
        foreach ($node in $PAppOperation.policies['inbound'].ChildNodes) {
            if ($node.Name -eq 'apim-policy-operation') {
                $PAppOperation.policies["inbound"].InsertBefore( $PAppOperation.CreateComment(" cdf: Begin Service policy ($(Split-Path $PolicyFilePath -leaf)) "), $node) | Out-Null
                foreach ($servicePolicyNode in $ServicePolicy.policies['inbound'].ChildNodes) {
                    Write-Host "`tService policy node: $($servicePolicyNode.Name)"
                    $ImportedNode = $PAppOperation.ImportNode($servicePolicyNode, $true)
                    $PAppOperation.policies['inbound'].InsertBefore($ImportedNode, $node) | Out-Null
                }
                $PAppOperation.policies["inbound"].InsertBefore( $PAppOperation.CreateComment(" cdf: End Service policy ($(Split-Path $PolicyFilePath -leaf)) "), $node) | Out-Null
                $PAppOperation.policies['inbound'].RemoveChild($node) | Out-Null
            }
            else {
                Write-Host "`tOperation policy node: $($node.LocalName)"
            }
        }

        # Replace backend
        Write-Host '  Backend'
        foreach ($node in $PAppOperation.policies['backend'].ChildNodes) {
            if ($node.Name -eq 'apim-policy-operation') {
                $PAppOperation.policies["backend"].InsertBefore( $PAppOperation.CreateComment(" cdf: Begin Service policy ($(Split-Path $PolicyFilePath -leaf)) "), $node) | Out-Null
                foreach ($servicePolicyNode in $ServicePolicy.policies['backend'].ChildNodes) {
                    Write-Host "`tService policy node: $($servicePolicyNode.Name)"
                    $ImportedNode = $PAppOperation.ImportNode($servicePolicyNode, $true)
                    $PAppOperation.policies['backend'].InsertBefore($ImportedNode, $node) | Out-Null
                }
                $PAppOperation.policies["backend"].InsertBefore( $PAppOperation.CreateComment(" cdf: End Service policy ($(Split-Path $PolicyFilePath -leaf)) "), $node) | Out-Null
                $PAppOperation.policies['backend'].RemoveChild($node) | Out-Null
            }
            else {
                Write-Host "`tOperation policy node: $($node.LocalName)"
            }
        }

        # Replace outbound
        Write-Host '  Outbound'
        foreach ($node in $PAppOperation.policies['outbound'].ChildNodes) {
            if ($node.Name -eq 'apim-policy-operation') {
                $PAppOperation.policies["outbound"].InsertBefore( $PAppOperation.CreateComment(" cdf: Begin Service policy ($(Split-Path $PolicyFilePath -leaf)) "), $node) | Out-Null
                foreach ($servicePolicyNode in $ServicePolicy.policies['outbound'].ChildNodes) {
                    Write-Host "`tService policy node: $($servicePolicyNode.Name)"
                    $ImportedNode = $PAppOperation.ImportNode($servicePolicyNode, $true)
                    $PAppOperation.policies['outbound'].InsertBefore($ImportedNode, $node) | Out-Null
                }
                $PAppOperation.policies["outbound"].InsertBefore( $PAppOperation.CreateComment(" cdf: End Service policy ($(Split-Path $PolicyFilePath -leaf)) "), $node) | Out-Null
                $PAppOperation.policies['outbound'].RemoveChild($node) | Out-Null
            }
            else {
                Write-Host "`tOperation policy node: $($node.LocalName)"
            }
        }

        # Replace on-error
        Write-Host '  On-Error'
        foreach ($node in $PAppOperation.policies['on-error'].ChildNodes) {
            if ($node.Name -eq 'apim-policy-operation') {
                $PAppOperation.policies["on-error"].InsertBefore( $PAppOperation.CreateComment(" cdf: Begin Service policy ($(Split-Path $PolicyFilePath -leaf)) "), $node) | Out-Null
                foreach ($servicePolicyNode in $ServicePolicy.policies['on-error'].ChildNodes) {
                    Write-Host "`tService policy node: $($servicePolicyNode.Name)"
                    $ImportedNode = $PAppOperation.ImportNode($servicePolicyNode, $true)
                    $PAppOperation.policies['on-error'].InsertBefore($ImportedNode, $node) | Out-Null
                }
                $PAppOperation.policies["on-error"].InsertBefore( $PAppOperation.CreateComment(" cdf: End Service policy ($(Split-Path $PolicyFilePath -leaf)) "), $node) | Out-Null
                $PAppOperation.policies['on-error'].RemoveChild($node) | Out-Null
            }
            else {
                Write-Host "`tOperation policy node: $($node.LocalName)"
            }
        }

        # Save the new service policy XML to file
        $PAppOperation.PreserveWhitespace = true
        $PAppOperation.Save("$OutputPath/policies/$PolicyFile") | Out-Null

    }
