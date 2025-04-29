Function Deploy-PostgresConfig {
    <#
    .SYNOPSIS
    Deploy service bus queues, topics and subscriptions

    .DESCRIPTION
    The cmdlet makes token substitution for the Platform config environment.
    Then deploys the service bus queues, topics and subscriptions for the service bus resource.

    .PARAMETER CdfConfig
    The CDFConfig object that holds the current scope configurations (Platform, Application and Domain)

    .PARAMETER InputPath
    The deployment package path, where servicebus.config.json is located.
    Optional, defaults to "./build"

    .PARAMETER OutputPath
    Output path for the environment specific config file servicebus.config.<env nameId>.json
    Optional, defaults to "./build"

    .PARAMETER TemplateDir
    Path to the bicep template folder where main.bicep is found. Defaults to ".".

    .INPUTS
    None. You cannot pipe objects.

    .OUTPUTS
    None.

    .EXAMPLE
    Deploy-CdfPostgresConfig `
        -CdfConfig $config `
        -Scope "Platform"

    .LINK
    Deploy-CdfTemplateDomain
    #>

    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [Object]$CdfConfig,
        [Parameter(Mandatory = $false)]
        [string] $Scope = 'Platform'
    )

    Begin {}
    Process {
        try {
            $OutputDetails = [ordered]@{}
            if ($CdfConfig.Domain.Features.usePostgres) {
                $ServerName = $CdfConfig.Platform.Config.platformPostgres.databaseServerFQDN
                $DefaultDatabase = $CdfConfig.Platform.Config.platformPostgres.database
                $Port = 5432
                $DomainName = $CdfConfig.Domain.Config.domainName
                $AdminUserName = Get-AzKeyVaultSecret `
                    -VaultName $CdfConfig.Platform.ResourceNames.keyVaultName `
                    -Name $CdfConfig.Platform.Config.platformPostgres.userSecretName `
                    -AsPlainText
                $AdminPassword = Get-AzKeyVaultSecret `
                    -VaultName $CdfConfig.Platform.ResourceNames.keyVaultName `
                    -Name $CdfConfig.Platform.Config.platformPostgres.passwordSecretName `
                    -AsPlainText
                $DomainDbPassword = GeneratePassword
                $DatabaseName = $DomainName
                $DatabaseUser = $DomainName
                $DatabaseUserSecretName = "Domain-$DomainName-Postgres-UserName"
                $DatabasePasswordSecretName = "Domain-$DomainName-Postgres-Password"
                Write-Host "Preparing Postgres database, user and permissions."
                $PlainDomainDbPassword = (New-Object System.Net.NetworkCredential("", $DomainDbPassword)).Password
                $env:PGPASSWORD = $AdminPassword
                #Command to check if database exists
                $checkDbQuery = "SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname = '$DatabaseName');"
                $checkRoleQuery = "SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname = '$DatabaseUser');"
                $databaseExists = & psql -h $ServerName -U $AdminUserName -d $DefaultDatabase -p $Port -c $checkDbQuery
                if ($LASTEXITCODE -ne 0) {
                    throw $databaseExists
                }
                else {
                    if ($databaseExists -match "f") {
                        $output = & psql -h $ServerName -U $AdminUserName -d $DefaultDatabase -p $Port -c "CREATE DATABASE $DatabaseName;"
                        if ($LASTEXITCODE -ne 0) {
                            throw $output
                        }
                        else {
                            $roleExists = & psql -h $ServerName -U $AdminUserName -d $DefaultDatabase -p $Port -c $checkRoleQuery
                            if ($LASTEXITCODE -ne 0) {
                                throw $roleExists
                            }
                            else {
                                if ($roleExists -match "f") {
                                    $output = & psql -h $ServerName -U $AdminUserName -d $DefaultDatabase -p $Port -c "CREATE USER $DatabaseUser WITH PASSWORD '$plainDomainDbPassword';"
                                    if ($LASTEXITCODE -ne 0) {
                                        throw $output
                                    }
                                    $output = & psql -h $ServerName -U $AdminUserName -d $DefaultDatabase -p $Port -c "GRANT ALL PRIVILEGES ON DATABASE $DatabaseName TO $DatabaseUser;"
                                    if ($LASTEXITCODE -ne 0) {
                                        throw $output
                                    }
                                    $null = Set-AzKeyVaultSecret `
                                        -VaultName $CdfConfig.Platform.ResourceNames.keyVaultName `
                                        -Name $DatabasePasswordSecretName `
                                        -SecretValue $DomainDbPassword
                                    $DatabaseUserName = ConvertTo-SecureString -String $DomainName -AsPlainText -Force
                                    $null = Set-AzKeyVaultSecret `
                                        -VaultName $CdfConfig.Platform.ResourceNames.keyVaultName `
                                        -Name  $DatabaseUserSecretName `
                                        -SecretValue $DatabaseUserName
                                }
                                else {
                                    Write-Host 'Domain user already exists.'
                                }
                            }
                        }
                    }
                }
                $OutputDetails.Add("Postgres-UserSecretName", $DatabaseUserSecretName)
                $OutputDetails.Add("Postgres-PasswordSecretName", $DatabasePasswordSecretName)
                $OutputDetails.Add("Postgres-Database", $DatabaseName)
            }
            return ,$OutputDetails;
        }
        catch {
            Write-Host $_;
            throw $_;
        }
    }
    End {
    }
}
