
class CdfBaseInputPlatformConfig {
    [hashtable]$Env
    [hashtable]$Config
    [hashtable]$Features
    [hashtable]$NetworkConfig
    [hashtable]$AccessControl

    CdfBaseOutputConfig() { 
        $this.Init(@{})
    }
}

class CdfTemplateConfig {
    [bool]$IsDeployed
    [hashtable]$Env
    [hashtable]$Tags
    [hashtable]$Config
    [hashtable]$Features
    [hashtable]$ResourceNames
    [hashtable]$NetworkConfig
    [hashtable]$AccessControl
  
    # Default constructor
    CdfTemplateConfig() { $this.Init(@{}) }
    # Convenience constructor from hashtable
    CdfTemplateConfig([hashtable]$Properties) { $this.Init($Properties) }
    # Shared initializer method
    [void] Init([hashtable]$Properties) {
        Write-Host "Initializing CdfTemplateConfig"
        foreach ($Property in $Properties.Keys) {
            Write-Host "Setting $($Properties.$Property)"
            $this.$Property = $Properties.$Property
        }
    }
  
}
  
class CdfServiceConfig : CdfTemplateConfig {
  
    # Default constructor
    CdfServiceConfig() { $this.Init(@{}) }
    # Convenience constructor from hashtable
    CdfServiceConfig([hashtable]$Properties) { $this.Init($Properties) }
  
    [string] ToString() {
        return "$($this.Config.serviceGroup)|$($this.Config.serviceName) ($($this.Config.templateName)/$($this.Config.templateVersion)/$($this.Env.definitionId))"
    }
}
class CdfDomainConfig : CdfTemplateConfig {
  
    # Default constructor
    CdfDomainConfig() { $this.Init(@{}) }
    # Convenience constructor from hashtable
    CdfDomainConfig([hashtable]$Properties) { $this.Init($Properties) }
  
    [string] ToString() {
        return "$($this.Config.domainName) ($($this.Config.templateName)/$($this.Config.templateVersion)/$($this.Env.definitionId))"
    }
}
  
class CdfApplicationConfig : CdfTemplateConfig {
  
    # Default constructor
    CdfApplicationConfig() { $this.Init(@{}) }
    # Convenience constructor from hashtable
    CdfApplicationConfig([hashtable]$Properties) { $this.Init($Properties) }
  
    [string] ToString() {
        return "$($this.Config.templateName)$($this.Config.applicationInstanceId)$($this.Env.nameId) ($($this.Config.templateName)/$($this.Config.templateVersion)/$($this.Env.definitionId))"
    }
}
  
class CdfPlatformConfig : CdfTemplateConfig {
  
    # Default constructor
    CdfPlatformConfig() { $this.Init(@{}) }
    # Convenience constructor from hashtable
    CdfPlatformConfig([hashtable]$Properties) { $this.Init($Properties) }
  
    [string] ToString() {
        return "$($this.Config.platformId)$($this.Config.platformInstanceId)$($this.Env.nameId) ($($this.Config.templateName)/$($this.Config.templateVersion)/$($this.Env.definitionId))"
    }
}
  
class CdfConfig {
    [CdfPlatformConfig]$Platform
    [CdfApplicationConfig]$Application
    [CdfDomainConfig]$Domain
    [CdfServiceConfig]$Service
  
    # Default constructor
    CdfConfig() { $this.Init(@{}) }
    # Convenience constructor from hashtable
    CdfConfig([hashtable]$Properties) { $this.Init($Properties) }
    # Shared initializer method
    [void] Init([hashtable]$Properties) {
        Write-Host "Initializing CdfConfig"
        $this.Platform = [CdfPlatformConfig]::new($Properties.Platform)
        $this.Application = [CdfApplicationConfig]::new($Properties.Application)
        $this.Domain = [CdfDomainConfig]::new($Properties.Domain)
        $this.Service = [CdfServiceConfig]::new($Properties.Service)
    }
}
  