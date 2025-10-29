function Invoke-AppConfigKeyValueValidation {
    [OutputType()]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $Configuration
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        $ValidateAppConfigKeyValues = @{
            ChangesAllowed                           = @(
                "False"
                "True"
            )
            DeploymentLocationModel                  = @(
                "Centralize"
                "Distribute"
            )
            DisconnectUsersOnlyOnDrainedSessionHosts = @(
                "False"
                "True"
            )
            Environment                              = @(
                "DEV"
                "PROD"
                "SBX"
            )
            ReplacementMethod                        = @(
                "Disabled"
                "Image"
                "Tags"
            )
            ScalingPlanMode                          = @(
                "Bake"
                "Cleanup"
                "Compliant"
                "Off"
            )
        }
    }

    process {
        if ($ValidateAppConfigKeyValues.ContainsKey($Configuration.Key)) {
            $AcceptableAppConfigKeyValues = $ValidateAppConfigKeyValues.$($Configuration.Key)

            if ($AcceptableAppConfigKeyValues -inotcontains $Configuration.Value) {
                Write-Log "Failed to validate app configuration setting '$($Configuration.Key)' and value '$($Configuration.Value)', acceptable values are: $($AcceptableAppConfigKeyValues -join ', ')" -LogLevel 'ERRORSTOP'
            }
        }
    }

    end {}
}

function Invoke-ParseAppConfig {
    [OutputType([System.Collections.Generic.List[Hashtable]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $Configuration
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        $ParsedAppConfig = [System.Collections.Generic.List[Hashtable]]::new()
    }

    process {
        $Configuration | Invoke-AppConfigKeyValueValidation

        # Re-assigning is necessary to avoid
        # an issue where object settings are
        # not populated correctly but instead
        # are populated as 'System.Collections.Hashtable'

        $KeyName = $Configuration.Key
        $KeyLabel = $Configuration.Label
        $KeyValue = $Configuration.Value

        if ($KeyName.EndsWith("Id")) {
            $KeyName = $KeyName.Trim("Id")
            $KeyValue = ($KeyValue | Get-ResourceInformation)
        }

        if ("True" -ieq $KeyValue) {
            $KeyValue = $true
        } elseif ("False" -ieq $KeyValue) {
            $KeyValue = $false
        }

        if ($null -eq $Configuration.Label) {
            $ParsedAppConfig.Add(@{
                    $KeyName = $KeyValue
                }
            )
        } else {
            $ParsedAppConfig.Add(@{
                    $KeyName = @{
                        Label        = $KeyLabel
                        LabeledValue = $KeyValue
                    }
                }
            )
        }
    }

    end {
        return $ParsedAppConfig
    }
}

function Get-Settings {
    [OutputType([System.Collections.Generic.List[Hashtable]])]
    [CmdletBinding()]
    param(
        [Parameter()]
        [String] $AppConfigurationEndpoint = $env:_AppConfigURI
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $AppConfigKeyValue = Get-AzAppConfigurationKeyValue -Endpoint $AppConfigurationEndpoint
    if ($null -eq $AppConfigKeyValue) {
        Write-Log "App configuration store '$AppConfigurationEndpoint' returned null key values" -LogLevel 'ERRORSTOP'
    }

    return ($AppConfigKeyValue | Invoke-ParseAppConfig)
}
Export-ModuleMember -Function Get-Settings
