using './main.bicep'

param pAssetStorageAccount = {
  name: ''
  resourceGroupName: ''
  subscriptionId: ''
}

param pAuthKeyVault = {
  name: ''
  resourceGroupName: ''
  subscriptionId: ''
}

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

param pEntraIdSecurityDeviceGroupName = ''

param pFunctionAppResourceGroupName = ''

param pGalleryImageDefinition = {
  name: ''
  version: 'latest'
  galleryName: ''
  resourceGroupName: ''
  subscriptionId: ''
}

param pHostPool = {
  name: ''
  resourceGroupName: ''
  subscriptionId: ''
}

param pLocation = ''

param pLogAnalyticsWorkspace = {
  name: ''
  resourceGroupName: ''
  subscriptionId: ''
  workspaceId: ''
}

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

param pTags = {
  deployment_source: 'cli'
  deployment_tool: 'PowerShell'
  environment: ''
  owner: ''
  project: ''
}

param pVirtualMachineSKU = 'Standard_D4as_v5'
