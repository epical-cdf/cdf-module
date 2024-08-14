class PlatformEnv {
    [ValidateNotNullOrEmpty()] 
    [string] $DefinitionId;
    [ValidateNotNullOrEmpty()] 
    [string] $NameId;
    [ValidateNotNullOrEmpty()] 
    [string] $ShortName;
    [ValidateNotNullOrEmpty()] 
    [string] $Name;
    [ValidateNotNullOrEmpty()] 
    [string] $Description;
    [ValidateNotNullOrEmpty()] 
    [string] $Purpose;
    [ValidateNotNullOrEmpty()] 
    [string] $Quality;
    [bool] $IsEnabled = $false;
    [bool] $ReleaseApproval = $false;
    [ValidateNotNullOrEmpty()] 
    [string] $TenantId;
    [ValidateNotNullOrEmpty()] 
    [string] $SubscriptionId;
    [string] $InfraDeployerName;
    [string] $InfraDeployerAppId;
    [string] $InfraDeployerSPObjectId;
    [string] $SolutionDeployerName;
    [string] $SolutionDeployerAppId;
    [string] $SolutionDeployerSPObjectId;
    [string] $ParentDnsZone;
    [string] $ParentPrivateDnsZone;
    [string] $ParentPublicDnsZone;
    [string] $CustomDomainVerificationId;
}

class ApplicationEnv:PlatformEnv {
    [ValidateNotNullOrEmpty()] 
    [string] $PlatformDefinitionId; 
}


<#
    .SYNOPSIS
    Deserialize a supplied json string into an object of type [PlatformEnv].
    Response will be either an instance of the class or an array of the class, depending on the JSON input.

    .DESCRIPTION
    Uses ConvertFrom-Json to deserialize a json string into a [pscustomobject] object graph.
    Parses the [pscustomobject] graph into a strongly typed object graph based on the generated classes.

    .PARAMETER Json
    The json string to be deserialized.

    .EXAMPLE
    Get-PlatformEnvClass -Json $json
#>
function  Get-PlatformEnvClass {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "String representation of json to be deserialized.")]
        [string] $Json
    )

    Begin {}

    Process {
        $obj = ConvertFrom-Json $Json

        if ($obj -is [array]) {
            $outArr = @()

            foreach ($o in $obj) {
                $outArr + ([PlatformEnv] $o)
            }

            return $outArr
        }

        return [PlatformEnv] (ConvertFrom-Json $Json)
    }

    End {}
}

<#
    .SYNOPSIS
    Deserialize a supplied json string into an object of type [ApplicationEnv].
    Response will be either an instance of the class or an array of the class, depending on the JSON input.

    .DESCRIPTION
    Uses ConvertFrom-Json to deserialize a json string into a [pscustomobject] object graph.
    Parses the [pscustomobject] graph into a strongly typed object graph based on the generated classes.

    .PARAMETER Json
    The json string to be deserialized.

    .EXAMPLE
    Get-PlatformEnvClass -Json $json
#>
function Get-ApplicationEnvClass {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "String representation of json to be deserialized.")]
        [string] $Json
    )

    Begin {}

    Process {
        $obj = ConvertFrom-Json $Json

        if ($obj -is [array]) {
            $outArr = @()

            foreach ($o in $obj) {
                $outArr + ([ApplicationEnv] $o)
            }

            return $outArr
        }

        return [ApplicationEnv] (ConvertFrom-Json $Json)
    }

    End {}
}
