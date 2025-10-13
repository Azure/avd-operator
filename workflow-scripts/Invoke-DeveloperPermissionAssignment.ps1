[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [String] $DeveloperUsername,

    [Parameter(Mandatory)]
    [String] $PullRequestNumber
)

function Set-ResourceGroupPermission {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String] $DeveloperUsername,

        [Parameter(Mandatory)]
        [String] $DeveloperUserPrincipalName,

        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $ResourceGroup,

        [Parameter(Mandatory)]
        [String] $RoleAssignmentName
    )

    begin {}

    process {
        $AzRoleAssignmentParameters = @{
            ResourceGroupName  = $ResourceGroup.ResourceGroupName
            RoleDefinitionName = $RoleAssignmentName
            SignInName         = $DeveloperUserPrincipalName
        }
        $ExistingAssignment = Get-AzRoleAssignment @AzRoleAssignmentParameters -ErrorAction SilentlyContinue
        if ($null -eq $ExistingAssignment) {
            Write-Output "Assigning RBAC permission '${RoleAssignmentName}' on resource group '$($ResourceGroup.ResourceGroupName)' for developer '${DeveloperUsername}'"
            New-AzRoleAssignment @AzRoleAssignmentParameters | Out-Null
        } else {
            Write-Output "RBAC permission '${RoleAssignmentName}' is already assigned on resource group '$($ResourceGroup.ResourceGroupName)' for developer '${DeveloperUsername}'"
        }
    }

    end {}
}

# Add GitHub actor handle and Army.mil UPN
# below to get permissions during deployments
$DeveloperUserPrincipalNames = @{
    "devopsjesus" = "jaryber@gfim.onmicrosoft.us"
}

if ($DeveloperUserPrincipalNames.ContainsKey($DeveloperUsername)) {
    $DeveloperUserPrincipalName = $DeveloperUserPrincipalNames.$DeveloperUsername
    Write-Output "Found developer user principal name '$DeveloperUserPrincipalName' for developer '$DeveloperUsername'"

    Write-Output "Getting resource groups with tag 'pull_request_number:${PullRequestNumber}'"
    $ResourceGroups = Get-AzResourceGroup -Tag @{ pull_request_number = $PullRequestNumber }
    Write-Output "Found $($ResourceGroups.Count) resource groups with tag 'pull_request_number:${PullRequestNumber}'"

    $ComputeResourceGroups = $ResourceGroups.where({ $PSItem.ResourceGroupName.EndsWith("-VM") })
    Write-Output "Found $($ComputeResourceGroups.Count) compute resource groups with tag 'pull_request_number:${PullRequestNumber}'"

    $HostPoolResourceGroups = $ResourceGroups.where({ $PSItem.ResourceGroupName.EndsWith("-HP") })
    Write-Output "Found $($HostPoolResourceGroups.Count) host pool resource groups with tag 'pull_request_number:${PullRequestNumber}'"

    $ComputeResourceGroups | Set-ResourceGroupPermission -DeveloperUsername $DeveloperUsername -DeveloperUserPrincipalName $DeveloperUserPrincipalName -RoleAssignmentName "Virtual Machine User Login"
    $HostPoolResourceGroups | Set-ResourceGroupPermission -DeveloperUsername $DeveloperUsername -DeveloperUserPrincipalName $DeveloperUserPrincipalName -RoleAssignmentName "Desktop Virtualization User"
} else {
    Write-Output "Found no user principal name for developer '$DeveloperUsername'"
    Write-Output "Permissions will not be assigned to test resources for developer '$DeveloperUsername'"
}
