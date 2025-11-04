function Get-ResourceInformation {
    [OutputType([System.Collections.Generic.List[Hashtable]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [String] $ResourceId
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        $Resources = [System.Collections.Generic.List[Hashtable]]::new()
    }

    process {
        try {
            $ResourceIdentifier = [Microsoft.Azure.Management.Internal.Resources.Utilities.Models.ResourceIdentifier]::new($ResourceId)
        } catch {
            # Handle error for resource ID of a resource group
            if ($PSItem.Exception.Message -ilike "*Invalid format of the resource identifier*") {
                $ResourceIdProperties = $ResourceId.Split('/')

                # Assume if the resource ID has 5 sections it is similar to a resource group ID
                switch ($ResourceIdProperties.Count) {
                    5 {
                        $ResourceIdentifier = @{
                            ResourceName = $ResourceIdProperties[4]
                            ResourceType = $ResourceIdProperties[3]
                            Subscription = $ResourceIdProperties[2]
                        }
                    }

                    default {
                        Write-Log "Invalid format of the resource identifier '$ResourceId'" -LogLevel 'ERRORSTOP'
                    }
                }
            } else {
                $ErrorScript = $PSItem.InvocationInfo.ScriptName
                $ErrorScriptLine = "$($PSItem.InvocationInfo.ScriptLineNumber):$($PSItem.InvocationInfo.OffsetInLine)"
                $ErrorMessage = "$($PSItem.Exception.Message) Error Script: $ErrorScript, Error Line: $ErrorScriptLine"
                Write-Log $ErrorMessage -Exception $PSItem.Exception -LogLevel 'ERRORSTOP'
            }
        }

        # Ternary operator to handle resource names with periods in them e.g. ADDS Domain joined VMs
        $Resource = @{
            Name           = ($ResourceIdentifier.ResourceName -match '\.' ? ($ResourceIdentifier.ResourceName -split '\.')[0] : $ResourceIdentifier.ResourceName)
            Type           = $ResourceIdentifier.ResourceType
            SubscriptionId = $ResourceIdentifier.Subscription
            Id             = $ResourceId
        }

        if ($null -ne $ResourceIdentifier.ResourceGroupName) {
            $Resource.ResourceGroupName = $ResourceIdentifier.ResourceGroupName
        }

        if ($null -ne $ResourceIdentifier.ParentResource) {
            # Parent resource is a combination of partial resource type and resource name, ex. 'virtualMachines/AVDVAXYZ123'
            # Split original resource ID by parent resource, grab beginning of original resource ID, and add parent resource ID as suffix
            $ParentResourceId = "$($ResourceId.Split($ResourceIdentifier.ParentResource)[0])$($ResourceIdentifier.ParentResource)"
            $Resource.Parent = $ParentResourceId | Get-ResourceInformation
        }

        $ResourceContext = Get-Context -SubscriptionId "$($Resource.SubscriptionId)"
        $RegionalResourceTypes = @(
            'Microsoft.Network/virtualNetworks'
        )
        if ($RegionalResourceTypes -contains $ResourceIdentifier.ResourceType) {
            $AzResourceParameters = @{
                DefaultProfile = $ResourceContext
                ErrorAction    = "SilentlyContinue"
                ResourceId     = $ResourceId
            }
            $RegionalResource = Get-AzResource @AzResourceParameters
            if ($null -ne $RegionalResource) {
                $Resource.Location = $RegionalResource.Location
            }
        }

        $TagResourceTypes = @(
            'Microsoft.Compute/virtualMachines'
        )
        if ($TagResourceTypes -contains $ResourceIdentifier.ResourceType) {
            $AzTagParameters = @{
                DefaultProfile = $ResourceContext
                ErrorAction    = "SilentlyContinue"
                ResourceId     = $ResourceId
            }
            $TagResource = Get-AzTag @AzTagParameters
            if ($null -ne $TagResource) {
                $Resource.Tags = $TagResource.Properties.TagsProperty
            }
        }

        if ($null -ne $Resource.Parent.Location) {
            $Resource.Location = $Resource.Parent.Location
        }

        $Resources.Add($Resource)
    }

    end {
        return $Resources
    }
}
Export-ModuleMember -Function Get-ResourceInformation