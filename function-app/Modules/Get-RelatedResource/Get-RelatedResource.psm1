function Get-RelatedResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $Resource
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        # Do not change order or casing
        $ResourceTypeDestructionOrder = @(
            "MICROSOFT.COMPUTE/VIRTUALMACHINES/EXTENSIONS"
            "MICROSOFT.COMPUTE/VIRTUALMACHINES"
            "MICROSOFT.COMPUTE/DISKS"
            "MICROSOFT.NETWORK/NETWORKINTERFACES"
            "MICROSOFT.DESKTOPVIRTUALIZATION/HOSTPOOLS/SESSIONHOSTS"
        )

        $RelatedResources = [System.Collections.Generic.List[Object]]::new()
    }

    process {
        switch ($Resource.Type) {
            "Microsoft.Compute/virtualMachines" {
                $RelatedResourceQuery = @(
                    "resources"
                    "| where subscriptionId =~ '$($Resource.SubscriptionId)'"
                    "| where resourceGroup =~ '$($Resource.ResourceGroupName)'"
                    "| where ['id'] has '$($Resource.Type)/$($Resource.Name)/' or name has '$($Resource.Name)'"
                    "| where not(type =~ 'Microsoft.Compute/virtualMachines/runCommands')"
                    "| where not(type =~ 'Microsoft.Compute/virtualMachines/extensions')"
                    "| project ['id']"
                ) | Out-String
                $RelatedResourcesQueryResults = $RelatedResourceQuery | Search-AzGraphPaging
                if ($RelatedResourcesQueryResults.Count -gt 0) {
                    foreach ($Resource in ($RelatedResourcesQueryResults.id | Get-ResourceInformation)) {
                        if (-not ($RelatedResources.Contains($Resource))) {
                            $RelatedResources.Add($Resource)
                        }
                    }
                }
            }

            "Microsoft.DesktopVirtualization/hostpools/sessionhosts" {
                if (-not ($RelatedResources.Contains($Resource))) {
                    $RelatedResources.Add($Resource)
                }
            }

            default {
                Write-Log "Unrecognized related resource type '$($Resource.Type)'" -LogLevel 'ERRORSTOP'
            }
        }
    }

    end {
        [Object[]] $UniqueRelatedResources = $RelatedResources | Sort-Object -Unique -Property { $PSItem.Id }
        return [Object[]] $UniqueRelatedResources | Sort-Object -Property { $ResourceTypeDestructionOrder.IndexOf($PSItem.Type.ToUpper()) }, Name
    }
}
Export-ModuleMember -Function Get-RelatedResource