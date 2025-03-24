Function New-LetsEncryptCertificate {

    Param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
        [Object]$CdfConfig,
        [Parameter(Mandatory = $true, HelpMessage = 'Certificate hostname, use "*" for wildcard certificate')]
        [string]$HostName,
        [Parameter(Mandatory = $true, HelpMessage = 'Certificate domain name')]
        [string]$DomainName,
        [Parameter(Mandatory = $true, HelpMessage = 'Resource group name of DNS Zone. Used to add/remove TXT challenge record')]
        [string]$DnsRG,
        [Parameter(Mandatory = $true, HelpMessage = 'Email address of issuer - will receive expiration notices')]
        [string]$EmailAddress,
        [Parameter(Mandatory = $true, HelpMessage = 'Key Vault to store issued certificate')]
        [string]$KeyVaultName,
        [Parameter(Mandatory = $true, HelpMessage = 'Key Vault secret name for issued certificate')]
        [string]$CertName,
        [Parameter(Mandatory = $false, HelpMessage = 'Indicate use of staging or live services. Set to "LetsEncrypt" to issue live certificates. Default is staging certs.')]
        [string]$ServiceName = 'LetsEncrypt-Staging' # 'LetsEncrypt' for live certs
    )

    Import-Module DnsClient-PS -ErrorAction:Stop
    Import-Module ACME-PS -ErrorAction:Stop

    # Ensures that no login info is saved after the runbook is done
    # Disable-AzContextAutosave

    # Log in as the service principal from the Runbook
    # $connection = Get-AutomationConnection -Name AzureRunAsConnection
    # Login-AzAccount -ServicePrincipal -Tenant $connection.TenantID -ApplicationId $connection.ApplicationID -CertificateThumbprint $connection.CertificateThumbprint

    # Create a state object and save it to the harddrive
    # $state = New-ACMEState -Path $env:TEMP

    $tempDirPath = [System.IO.Path]::GetTempPath()
    $tempFolderName = [System.IO.Path]::GetRandomFileName()
    $tempPath = Join-Path $tempDirPath $tempFolderName
    New-Item -ItemType Directory -Path $tempPath | Out-Null
    $state = New-ACMEState -Path $tempPath
    # #$ServiceName = 'LetsEncrypt'
    # $ServiceName = 'LetsEncrypt-Staging'

    # Fetch the service directory and save it in the state
    Get-ACMEServiceDirectory $state -ServiceName $ServiceName -PassThru

    # Get the first anti-replay nonce
    New-ACMENonce $state

    # Create an account key. The state will make sure it's stored.
    New-ACMEAccountKey $state -PassThru

    # Register the account key with the acme service. The account key will automatically be read from the state
    New-ACMEAccount $state -EmailAddresses $EmailAddress -AcceptTOS

    # Load an state object to have service directory and account keys available
    $state = Get-ACMEState -Path $tempPath

    # It might be neccessary to acquire a new nonce, so we'll just do it for the sake of the example.
    New-ACMENonce $state -PassThru

    # Create the identifier for the DNS name
    $identifier = New-ACMEIdentifier "$HostName.$DomainName"

    # Create the order object at the ACME service.
    $order = New-ACMEOrder $state -Identifiers $identifier

    # Fetch the authorizations for that order
    $authZ = Get-ACMEAuthorization -State $state -Order $order

    # Select a challenge to fullfill
    # $challenge = Get-ACMEChallenge $state $authZ "http-01";
    $challenge = Get-ACMEChallenge $state $authZ 'dns-01'

    # Inspect the challenge data
    $challenge.Data

    $recordName = $challenge.Data.TxtRecordName.Replace(".$DomainName", '')
    $recordValue = $challenge.Data.Content

    # Remove any existing old keys
    $txtRecord = Get-AzDnsRecordSet `
        -Name $recordName `
        -RecordType TXT `
        -ZoneName $DomainName `
        -ResourceGroupName $DnsRG `
        -ErrorAction:SilentlyContinue

    if ($null -ne $txtRecord) {
        Write-Host "Found existing DNS record with TTL $($txtRecord.TTL) seconds, removing and waiting for it to expire."
        Remove-AzDnsRecordSet `
            -Name $recordName `
            -RecordType TXT `
            -ZoneName $DomainName `
            -ResourceGroupName $DnsRG `
            -ErrorAction:SilentlyContinue
        Start-Sleep -Seconds $txtRecord.TTL
    }

    New-AzDnsRecordSet -Name $recordName -RecordType TXT -ZoneName $DomainName -ResourceGroupName $DnsRG -Ttl 180 -DnsRecords (New-AzDnsRecordConfig -Value $recordValue)
    Write-Host 'Waiting for DNS record to propagate.' -NoNewline
    while (!$dnsResult -or $result.HasError) {
        Start-Sleep -Seconds 30
        Write-Host '.' -NoNewline
        $dnsResult = Resolve-Dns -Query "$recordName.$DomainName" -QueryType TXT -NameServer 8.8.8.8
        if ($dnsResult.Answers[0]) {
            if ($dnsResult.Answers[0].Text -ne $recordValue ) {
                Write-Warning ('Found wrong TXT record: ' + $dnsResult.Answers[0].Text)
                $dnsResult = $null
            }
        }
        else {
            $dnsResult = $null
        }
    }
    Write-Host 'Done.'

    try {
        # Signal the ACME server that the challenge is ready
        $challenge | Complete-ACMEChallenge $state

        # Wait a little bit and update the order, until we see the states
        while ($order.Status -notin ('ready', 'invalid')) {
            Start-Sleep -Seconds 10
            $order | Update-ACMEOrder $state -PassThru
        }

        if ($order.Status -ieq ("invalid")) {
            $order | Get-ACMEAuthorizationError -State $state;
            throw "Order was invalid";
        }

        # We should have a valid order now and should be able to complete it
        # Therefore we need a certificate key
        $certKey = New-ACMECertificateKey -Path (Join-Path $tempPath "$CertName.key.xml")

        # Complete the order - this will issue a certificate singing request
        Complete-ACMEOrder $state -Order $order -CertificateKey $certKey

        # Now we wait until the ACME service provides the certificate url
        while (-not $order.CertificateUrl) {
            Start-Sleep -Seconds 15
            $order | Update-ACMEOrder $state -PassThru
        }

        # As soon as the url shows up we can create the PFX
        $certificateFile = (Join-Path $tempPath "$CertName.pfx")

        # Get or create a certificate password
        $certPw = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "Cert-Password-$CertName" -AsPlainText
        if ($null -eq $certPw) {
            $password = New-Object -TypeName PSObject
            $password | Add-Member `
                -MemberType ScriptProperty `
                -Name 'Password' `
                -Value {
                ('!@#$%^&*0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz'.tochararray() | Sort-Object { Get-Random })[0..30] -join ''
            }
            $securePassword = ConvertTo-SecureString -String $password.Password.ToString() -Force -AsPlainText
            $certPw = Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "Cert-Password-$CertName" -SecretValue $securePassword -ContentType 'text/plain'
        }
        else {
            $securePassword = ConvertTo-SecureString -String $certPw -Force -AsPlainText
        }
        Export-ACMECertificate $state `
            -Order $order `
            -CertificateKey $certKey `
            -Path $certificateFile `
            -Password $securePassword

        $kvCert = Import-AzKeyVaultCertificate `
            -VaultName $KeyVaultName `
            -Name $CertName `
            -FilePath $certificateFile `
            -Password $securePassword

        # Write-Verbose 'KeyVault Results:' ($kvCert | ConvertTo-Json -Depth 10)
        # TODO: Move to separate command
        if ($null -ne $CdfConfig) {
            $region = $CdfConfig.Platform.Env.region
            $regionCode = $CdfConfig.Platform.Env.regionCode
            $platformKey = "$($CdfConfig.Platform.Config.platformId)$($CdfConfig.Platform.Config.instanceId)"
            $platformEnvKey = "$platformKey$($CdfConfig.Platform.Env.nameId)"
            $applicationKey = "$($CdfConfig.Application.Config.applicationId ?? $CdfConfig.Application.Config.templateName)$($CdfConfig.Application.Config.instanceId)"
            $applicationEnvKey = "$applicationKey$($CdfConfig.Application.Env.nameId)"

            $keyVault = Get-AzKeyVault -VaultName $CdfConfig.Application.ResourceNames.keyVaultName
            # $keyVault | ConvertTo-Json -Depth 5

            if ($null -ne $CdfConfig.Application.ResourceNames.laAppServicePlanName) {
                $appServicePlan = Get-AzAppServicePlan -Name $CdfConfig.Application.ResourceNames.laAppServicePlanName
                $appServicePlan | ConvertTo-Json -Depth 5
    
                $certProperties = @{
                    serverFarmId       = $appServicePlan.Id
                    keyVaultId         = $keyVault.ResourceId
                    keyVaultSecretName = $CertName
                }
                $certProperties | ConvertTo-Json -Depth 5
    
                Invoke-AzRestMethod `
                    -Method PUT `
                    -Uri "https://management.azure.com/subscriptions/$($CdfConfig.Platform.Env.subscriptionId)/resourceGroups/$($CdfConfig.Application.ResourceNames.appResourceGroupName)/providers/Microsoft.Web/certificates/$($platformEnvKey)-$($applicationEnvKey)-certificate?api-version=2024-04-01" `
                    -Payload (@{
                        type       = 'Microsoft.Web/certificates'
                        name       = "$($platformEnvKey)-$($applicationEnvKey)-certificate"
                        location   = $region
                        properties = $certProperties
                    } | ConvertTo-Json -Depth 10) `
                    -WaitForCompletion
            }
        }

        return $certificateFile
    }
    catch {
        Write-Error 'An error occurred:'
        Write-Error $_
    }
    finally {
        Write-Host 'Removing DNS TXT challenge record.'
        Remove-AzDnsRecordSet `
            -Name $recordName `
            -RecordType TXT `
            -ZoneName $DomainName `
            -ResourceGroupName $DnsRG
    }
}