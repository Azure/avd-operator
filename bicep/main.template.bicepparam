using './main.bicep'

@description('Name of the Storage Account to be created for the downloading required binaries.')
@minLength(3)
@maxLength(24)
param pAssetStorageAccount = {
  name: ''
  resourceGroupName: ''
  subscriptionId: ''
}

@description('Name of the existing Key Vault that contains the credentials for the service principal to be used to authenticate AVD Operator.')
param pAuthKeyVault = {
  name: ''
  resourceGroupName: ''
  subscriptionId: ''
}

@description('''
This object allows for multiple deployments across cloud regions.
If multiple regions are specified, resources will be deployed or referenced in each region.
Each deployment location requires the following properties:
- name: A unique name for the deployment.
- computeResourceGroup: The existing resource group where compute resources will be deployed.
- diskEncryptionSet: The existing Disk Encryption Set used for encrypting disks.
- fslogixStorageAccountName: The name of the existing Storage Account for FSLogix profile containers.
- location: The Azure region for the deployment.
- sessionHostNamePrefix: The prefix for naming session hosts. E.g. 'avdvahost', which gets appended with a 3 digit number with '0' padding.
- virtualNetworkSubnet: The existing subnet within a virtual network where session hosts will be deployed.
''')
param pDeploymentLocations = [
  {
    name: ''
    computeResourceGroup: {
      name: ''
      subscriptionId: ''
    }
    diskEncryptionSet: {
      name: ''
      resourceGroupName: ''
      subscriptionId: ''
    }
    fslogixStorageAccountName: ''
    location: ''
    sessionHostNamePrefix: ''
    virtualNetworkSubnet: {
      name: ''
      resourceGroupName: ''
      subscriptionId: ''
      virtualNetworkName: ''
    }
  }
]

@description('OPTIONAL: Name of the Entra ID Security Device Group to be created for the session hosts. Used when Entra-joining the session hosts.')
param pEntraIdSecurityDeviceGroupName = ''

@description('OPTIONAL: By default, the function app will be deployed to the same resource group as the host pool. Specify an alternative here.')
param pFunctionAppResourceGroupName = ''

@description('Properties of the Azure Gallery Image Definition to be used for the session hosts.')
param pGalleryImageDefinition = {
  name: ''
  version: 'latest'
  galleryName: ''
  resourceGroupName: ''
  subscriptionId: ''
}

@description('Properties of the existing Host Pool.')
param pHostPool = {
  name: ''
  resourceGroupName: ''
  subscriptionId: ''
}

@description('Location for new resources to be deployed.')
param pLocation = ''

@description('Properties of the existing Log Analytics Workspace to be used for monitoring and diagnostics.')
param pLogAnalyticsWorkspace = {
  name: ''
  resourceGroupName: ''
  subscriptionId: ''
  workspaceId: ''
}

@description('Properties of the scaling plans to be used by AVD Operator. Only modify the empty values.')
param pScalingPlans = [
  {
    name: 'BAKE'
    rampDownMinimumHostsPercent: 100
    rampUpMinimumHostsPercent: 100
    resourceGroupName: ''
    subscriptionId: ''
  }
  {
    name: 'CLEANUP'
    rampDownMinimumHostsPercent: 0
    rampUpMinimumHostsPercent: 0
    resourceGroupName: ''
    subscriptionId: ''
  }
  {
    name: 'COMPLIANT'
    rampDownMinimumHostsPercent: 5
    rampUpMinimumHostsPercent: 25
    resourceGroupName: ''
    subscriptionId: ''
  }
]

@description('Object ID of the Service Principal to be assigned the required roles on resources created by AVD Operator.')
param pServicePrincipalObjectId = ''

@description('Tags to be applied to all resources deployed by AVD Operator.')
param pTags = {
  deployment_source: 'cli'
  deployment_tool: 'PowerShell'
  environment: ''
  owner: ''
  project: ''
}

@description('SKU of the Virtual Machines to be used for session hosts.')
param pVirtualMachineSKU = 'Standard_D4as_v5'
