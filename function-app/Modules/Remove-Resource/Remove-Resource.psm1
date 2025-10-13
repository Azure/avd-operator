function Remove-Resource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $Resource
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        $RemovedResources = [System.Collections.Generic.List[Object]]::new()
    }

    process {
        Write-Log "Removing resource with ID '$($Resource.Id)'"
        $ResourceContext = Get-Context -SubscriptionId $Resource.SubscriptionId
        $AzResourceParameters = @{
            DefaultProfile = $ResourceContext
            ErrorAction    = "Stop"
            Force          = $true
            ResourceId     = $Resource.Id
        }
        $RemovedResource = Remove-AzResource @AzResourceParameters
        if (-not $RemovedResource) {
            Write-Log "Failed to remove resource with ID '$($Resource.Id)'" -LogLevel 'ERRORSTOP'
        }

        switch ($Resource.Type) {
            "Microsoft.Compute/virtualMachines" {
                $Resource.Name | Set-EntraIdDeviceGroupMembership -DeviceGroupName $env:EntraIdSecurityDeviceGroupName -Action "Remove"
                $Resource.Name | Remove-EntraIdIntuneDevice
            }

            "Microsoft.DesktopVirtualization/hostpools/sessionhosts" {
                $AzWvdSessionHostParameters = @{
                    ErrorAction       = "Stop"
                    Force             = $true
                    HostPoolName      = $Resource.Parent.Name
                    Name              = $Resource.Name
                    ResourceGroupName = $Resource.ResourceGroupName
                    SubscriptionId    = $Resource.SubscriptionId
                }
                Remove-AzWvdSessionHost @AzWvdSessionHostParameters
            }
        }

        $RemovedResources.Add(@{
                Resource = $Resource
                Status   = $true
            }
        )
    }

    end {
        return $RemovedResources
    }
}
Export-ModuleMember -Function Remove-Resource
