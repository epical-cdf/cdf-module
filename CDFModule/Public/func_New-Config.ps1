Function New-Config {

    [CmdletBinding()]
    Param(
      [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
      [Object]$CdfConfig
    )
  
    return [CdfConfig]::new($CdfConfig)
}