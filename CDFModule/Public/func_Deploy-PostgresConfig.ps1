Function Deploy-PostgresConfig {
    <#
    .SYNOPSIS
    Deploy postgres database, user and permission for a domain and a schema under domain database.

    .DESCRIPTION
    The cmdlet Deploy postgres database, user and permission for a domain and a schema under domain database.

    .PARAMETER CdfConfig
    The CDFConfig object that holds the current scope configurations (Platform, Application and Domain)

    .PARAMETER Scope
    Target scope : Domain or Service

    .INPUTS
    None. You cannot pipe objects.

    .OUTPUTS
    None.

    .EXAMPLE
    Deploy-CdfPostgresConfig `
        -CdfConfig $config `
        -Scope "Domain"

    Deploy-CdfPostgresConfig `
        -CdfConfig $config `
        -Scope "Service"

    .LINK
    Deploy-CdfTemplateDomain
    Deploy-CdfService
    #>

    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [Object]$CdfConfig,
        [Parameter(Mandatory = $false)]
        [string] $Scope = 'Domain'
    )

    Begin {}
    Process {
        try {
            $OutputDetails = [ordered]@{}
            if ($CdfConfig.Domain.Features.usePostgres) {
                $ServerName = $CdfConfig.Platform.Config.platformPostgres.databaseServerFQDN
                $DefaultDatabase = $CdfConfig.Platform.Config.platformPostgres.database
                $Port = 5432
                $ApplicationKey = "{0}{1}-{2}{3}" -f `
                    $CdfConfig.Platform.Config.platformId, `
                    $CdfConfig.Platform.Config.instanceId, `
                    $CdfConfig.Application.Config.applicationId, `
                    $CdfConfig.Application.Config.instanceId

                $DomainName = $CdfConfig.Domain.Config.domainName
                $DomainKey = "{0}-{1}-{2}-{3}" -f `
                    $ApplicationKey, `
                    $DomainName, `
                    $CdfConfig.Application.Env.nameId, `
                    $CdfConfig.Application.Env.regionCode
                $DomainDatabaseName = $DomainKey
                $DomainDatabaseUser = $DomainKey

                $BuildAgentIP = Get-IP
                if ($Scope -eq 'Service') {
                    $ServiceName = $CdfConfig.Service.Config.serviceName
                }
                $FullRuleName = "BuildAgentIP-$Scope-$DomainKey-Deployment"
                $RuleName = $FullRuleName.Substring(0, [Math]::Min(80, $FullRuleName.Length))

                $null = New-AzPostgreSqlFlexibleServerFirewallRule `
                    -ResourceGroupName $CdfConfig.Platform.ResourceNames.platformResourceGroupName `
                    -ServerName $CdfConfig.Platform.Config.platformPostgres.name `
                    -Name $RuleName `
                    -StartIpAddress $BuildAgentIP `
                    -EndIpAddress $BuildAgentIP `
                    -ErrorAction:Stop


                if ($Scope -eq 'Domain') {
                    $AdminUserName = Get-AzKeyVaultSecret `
                        -VaultName $CdfConfig.Platform.ResourceNames.keyVaultName `
                        -Name $CdfConfig.Platform.Config.platformPostgres.userSecretName `
                        -AsPlainText
                    $AdminPassword = Get-AzKeyVaultSecret `
                        -VaultName $CdfConfig.Platform.ResourceNames.keyVaultName `
                        -Name $CdfConfig.Platform.Config.platformPostgres.passwordSecretName `
                        -AsPlainText

                    $DatabaseUserSecretName = "Cdf-Domain-$DomainKey-Postgres-UserName"
                    $DatabasePasswordSecretName = "Cdf-Domain-$DomainKey-Postgres-Password"

                    Write-Host "Preparing Postgres database, user and permissions."
                    $DomainDbPassword = GeneratePassword
                    $PlainDomainDbPassword = (New-Object System.Net.NetworkCredential("", $DomainDbPassword)).Password
                    $env:PGPASSWORD = $AdminPassword
                    $env:CDF_PG_SERVER_NAME = $ServerName
                    $env:CDF_PG_DATABASE = $DefaultDatabase
                    $env:CDF_PG_USER_NAME = $AdminUserName

                    #PSQL Commands
                    $checkDbQuery = "SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname = '$DomainDatabaseName');"
                    $checkRoleQuery = "SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname = '$DomainDatabaseUser');"
                    $createDb = "CREATE DATABASE `"$DomainDatabaseName`";"
                    $createUser = "CREATE USER `"$DomainDatabaseUser`" WITH PASSWORD '$plainDomainDbPassword';"
                    $grantPermissions = "GRANT ALL PRIVILEGES ON DATABASE `"$DomainDatabaseName`" TO `"$DomainDatabaseUser`";"

                    $databaseExists = Invoke-PostgresQuery -Query $checkDbQuery
                    if ($databaseExists -match "f") {
                        Invoke-PostgresQuery -Query $createDb | Out-Null
                        $roleExists = Invoke-PostgresQuery -Query $checkRoleQuery
                        if ($roleExists -match "f") {
                            Invoke-PostgresQuery -Query $createUser | Out-Null
                            Invoke-PostgresQuery -Query $grantPermissions | Out-Null
                            $null = Set-AzKeyVaultSecret `
                                -VaultName $CdfConfig.Platform.ResourceNames.keyVaultName `
                                -Name $DatabasePasswordSecretName `
                                -SecretValue $DomainDbPassword
                            $DatabaseUserName = ConvertTo-SecureString -String $DomainDatabaseUser -AsPlainText -Force
                            $null = Set-AzKeyVaultSecret `
                                -VaultName $CdfConfig.Platform.ResourceNames.keyVaultName `
                                -Name  $DatabaseUserSecretName `
                                -SecretValue $DatabaseUserName
                        }
                        else {
                            Write-Host 'Strange! Domain user already exists.'
                        }
                    }
                    else {
                        Write-Host 'Domain database already exists.'
                    }
                    $OutputDetails.Add("Postgres-UserSecretName", $DatabaseUserSecretName)
                    $OutputDetails.Add("Postgres-PasswordSecretName", $DatabasePasswordSecretName)
                    $OutputDetails.Add("Postgres-Database", $DomainDatabaseName)
                }
                else {
                    $DomainUserName = Get-AzKeyVaultSecret `
                        -VaultName $CdfConfig.Domain.ResourceNames.keyVaultName `
                        -Name $CdfConfig.Domain.Config.domainPostgres.userSecretName `
                        -AsPlainText
                    $DomainPassword = Get-AzKeyVaultSecret `
                        -VaultName $CdfConfig.Domain.ResourceNames.keyVaultName `
                        -Name $CdfConfig.Domain.Config.domainPostgres.passwordSecretName `
                        -AsPlainText
                    $env:PGPASSWORD = $DomainPassword
                    $env:CDF_PG_SERVER_NAME = $ServerName
                    $env:CDF_PG_DATABASE = $DomainDatabaseName
                    $env:CDF_PG_USER_NAME = $DomainUserName

                    Write-Host "Preparing Postgres database schema for service $ServiceName."
                    #$PlainDomainDbPassword = (New-Object System.Net.NetworkCredential("", $DomainPassword)).Password
                    $checkDbSchemaQuery = "SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = '$ServiceName');"
                    $dbSchemaExists = Invoke-PostgresQuery -Query $checkDbSchemaQuery
                    if ($dbSchemaExists -match "f") {
                        Invoke-PostgresQuery -Query "CREATE SCHEMA $ServiceName;" | Out-Null
                    }
                }
                $null = Remove-AzPostgreSqlFlexibleServerFirewallRule `
                    -ResourceGroupName $CdfConfig.Platform.ResourceNames.platformResourceGroupName `
                    -ServerName $CdfConfig.Platform.Config.platformPostgres.name `
                    -Name $RuleName `
                    -ErrorAction:Stop

            }
            return $OutputDetails
        }
        catch {
            Write-Host $_;
            throw $_;
        }
    }
    End {
    }
}

Function Invoke-PostgresQuery {
    param (
        [string]$Query,
        [string]$ServerName = $env:CDF_PG_SERVER_NAME,
        [string]$UserName = $env:CDF_PG_USER_NAME,
        [string]$Database = $env:CDF_PG_DATABASE,
        [int]$Port = 5432
    )
    $result = & psql -h $ServerName -U $UserName -d $Database -p $Port -c $Query
    if ($LASTEXITCODE -ne 0) {
        throw $result
    }
    return $result
}
