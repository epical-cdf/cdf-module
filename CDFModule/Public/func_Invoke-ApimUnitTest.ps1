Function Invoke-ApimUnitTest {
    <#
    .SYNOPSIS

    Runs a set of validation tests on a domain API unit test

    .DESCRIPTION

    Currently this command is only building domain APIs to test build process.
    TODO: Implement validations and report generation eg junit test report xml

    <?xml version="1.0" encoding="UTF-8"?>
    <testsuites time="15.682687">
        <testsuite name="<PlatformID><PlatformInstance>.<ApplicationTemplateName><ApplicationInstance>.<DomainName>.<TestCase/ServiceName>" time="6.605871">
            <testcase name="Build API" classname="Tests.elxcapim01.apim01.api-sample" time="2.113871" />
            <testcase name="Build Backends" classname="Tests.elxcapim01.apim01.api-sample" time="1.051" />
            <testcase name="Build Products" classname="Tests.elxcapim01.apim01.api-sample" time="3.441" />
        </testsuite>
        <testsuite name="<PlatformID><PlatformInstance>.<ApplicationTemplateName><ApplicationInstance>.<DomainName>.<TestCase/ServiceName>" time="6.605871">
            <testcase name="Build API" classname="Tests.elxcapim01.apim01.api-todo" time="2.113871" />
            <testcase name="Build Backends" classname="Tests.elxcapim01.apim01.api-todo" time="1.051" />
            <testcase name="Build Products" classname="Tests.elxcapim01.apim01.api-todo" time="3.441">
                <failure message="Assertion error message" type="AssertionError">
                    <!-- Validation error message here -->
                </failure>            
            </testcase>
        </testsuite>
    </testsuites>

    .PARAMETER SharedPath
    File system root path to the apim shared repository contents

    .PARAMETER TestName
    Path to the yaml configuration file

    .PARAMETER TestCasePath
    File system path where ARM template will be written

    .PARAMETER TestResultsPath
    File system path where ARM template will be written
    
    .PARAMETER OutputPath
    File system path to working area for building and testing API

    .PARAMETER OutputPath
    File system path where ARM template will be written

    .INPUTS
    None. You cannot pipe objects.

    .OUTPUTS
    None. Writes compiled policies.

    .EXAMPLE
    PS>  Invoke-ApimUnitTest ...
       

    .LINK

    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string] $SharedPath,
        [Parameter(Mandatory = $true)]
        [string] $TestName,
        [Parameter(Mandatory = $false)]
        [string] $OutputPath = 'tmp',
        [Parameter(Mandatory = $false)]
        [string] $TestCasesPath = './test/fixtures',
        [Parameter(Mandatory = $false)]
        [string] $TestResultsPath = 'test-results'
    )

    # Setup test parameters
    if ($null -eq $TestName) {
        Get-ChildItem -Directory -Path $TestCasesPath -Name
        $TestName = Read-Host -Prompt 'Please enter a unit test to run'
        $TestFolder = Resolve-Path "$PSScriptRoot/../fixtures/$TestName"

    }
    else {
        $TestFolder = Resolve-Path "$PSScriptRoot/../fixtures/$TestName"
    }

    if (-not(Test-Path $TestFolder)) {
        Write-Host "'$TestName' does not exist. Please, provide a valid test fixture name."
        return 1
    }

    if ($null -eq $OutputPath) {
        $OutputPath = Resolve-Path "$PSScriptRoot/.."
    }
    $RunFolder = "$OutputPath/$TestName/run"
    $BuildFolder = "$OutputPath/$TestName/build"
    
    if ($null -eq $SharedPath) {
        $SharedPath = Resolve-Path "$PSScriptRoot/../.."
    }

    # Load build cmdlets and environment for unit test
    . "$SharedPath/utils/build-apim-cmdlets.ps1"
    . "$TestFolder/test-env.ps1"

    Write-Host 'Running unit test for:'
    Write-Host "  Test name: $TestName"
    Write-Host "  Output path: $OutputPath"
    Write-Host "  Run folder: $RunFolder"
    Write-Host "  Build folder: $BuildFolder"
    Write-Host "  Test folder: $TestFolder"
    Write-Host "  Domain name: $DOMAIN_NAME"
    Write-Host "  Service name: $SERVICE_NAME"
    Write-Host "  Service type: $SERVICE_TYPE"
    Write-Host "  Service group: $SERVICE_GROUP"
    Write-Host "  Service template: $SERVICE_TEMPLATE"

    # Setup unit test "run" folders
    New-Item -Force -Type Directory $RunFolder | Out-Null
    Copy-Item -Force -Path "$TestFolder/*" -Destination $RunFolder -Recurse | Out-Null

    New-Item -Force -Type Directory $BuildFolder | Out-Null
    # This cmdlet builds ARM templates for a service api specification and expects an "api.yaml" file to be found in the <SpecFolder>
    Build-ApimServiceTemplates `
        -DomainName $DOMAIN_NAME `
        -ServiceName $SERVICE_NAME `
        -DomainPath $TestFolder `
        -SharedPath $SharedPath `
        -OutputPath "$BuildFolder/api" `

    Build-ApimDomainBackendTemplates `
        -DomainName $DOMAIN_NAME `
        -DomainPath $TestFolder `
        -SharedPath $SharedPath `
        -OutputPath "$BuildFolder/backends" `

    Build-ApimDomainProductTemplates `
        -DomainName $DOMAIN_NAME `
        -DomainPath $TestFolder `
        -SharedPath $SharedPath `
        -OutputPath "$BuildFolder/products" `

}
