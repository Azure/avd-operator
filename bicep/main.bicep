targetScope = 'resourceGroup'

////////////////
// Data Types //
////////////////

type tApplicationServicePlan = {
  name: string
  kind: string
  properties: {
    elasticScaleEnabled: bool
    maximumElasticWorkerCount: int
  }
  sku: tSku
}

type tDeploymentLocation = {
  name: string
  computeResourceGroup: tResourceGroup
  diskEncryptionSet: tResource
  fslogixStorageAccountName: string
  location: string
  sessionHostNamePrefix: tSessionHostNamePrefix
  virtualNetworkSubnet: tVirtualNetworkSubnet
}

type tGalleryImageDefinition = {
  name: string
  version: string
  galleryName: string
  resourceGroupName: string
  subscriptionId: string
}

type tLogAnalyticsWorkspace = {
  name: string
  resourceGroupName: string
  subscriptionId: string
  workspaceId: string
}

type tResource = {
  name: string
  resourceGroupName: string
  subscriptionId: string
}

type tResourceGroup = {
  name: string
  subscriptionId: string
}

type tRoleDefinition = {
  name: string
  guid: string
}

@maxLength(12)
type tSessionHostNamePrefix = string

type tScalingPlan = {
  name: string
  rampDownMinimumHostsPercent: int
  rampUpMinimumHostsPercent: int
  resourceGroupName: string
  subscriptionId: string
}

type tSku = {
  capacity: int
  family: string
  name: string
  size: string
  tier: string
}

type tTags = {
  deployment_source: string
  deployment_tool: string
  environment: string
  owner: string
  project: string
}

type tVirtualNetworkSubnet = {
  name: string
  resourceGroupName: string
  subscriptionId: string
  virtualNetworkName: string
}

///////////////////////////
// Parameters - Required //
///////////////////////////

param pAssetStorageAccount tResource
param pAuthKeyVault tResource
param pDeploymentLocations tDeploymentLocation[]
param pEntraIdSecurityDeviceGroupName string
param pGalleryImageDefinition tGalleryImageDefinition
param pHostPool tResource
param pLocation string
param pLogAnalyticsWorkspace tLogAnalyticsWorkspace
param pScalingPlans tScalingPlan[]
param pTags tTags
param pVirtualMachineSKU string

///////////////////////////
// Parameters - Default  //
///////////////////////////

param pApplicationInsightsName string = pFunctionAppName
param pApplicationServicePlan tApplicationServicePlan = {
  name: pFunctionAppName
  kind: 'elastic'
  properties: {
    elasticScaleEnabled: true
    maximumElasticWorkerCount: 20
  }
  sku: {
    name: 'EP1'
    capacity: 1
    family: 'EP'
    size: 'EP1'
    tier: 'ElasticPremium'
  }
}
param pEvaluationTime string = 'PT5M'

param pFunctionAppName string = replace('${pHostPool.name}', 'HP', 'FC')
param pFunctionAppResourceGroupName string = replace('${pHostPool.name}', 'HP', 'FC')

param pGlobalLocation string = 'global'

@maxValue(16)
param pMaxAllowedSessionsPerHost int = 16

param pSessionHostBuffer string = '0.3'

param pStorageAccountDataName string = '${toLower(replace(replace(pFunctionAppName, '-', ''), '_', ''))}d'
param pStorageAccountKind string = 'StorageV2'
param pStorageAccountName string = toLower(replace(replace(pFunctionAppName, '-', ''), '_', ''))
param pStorageAccountSkuName string = 'Standard_LRS'

@maxValue(625)
param pTargetSessionHostCount int = 5

//////////////////////////
// Resources - Existing //
//////////////////////////

resource rDiskEncryptionSet 'Microsoft.Compute/diskEncryptionSets@2024-03-02' existing = [
  for vDeploymentLocation in pDeploymentLocations: {
    name: vDeploymentLocation.diskEncryptionSet.name
    scope: resourceGroup(
      vDeploymentLocation.diskEncryptionSet.subscriptionId,
      vDeploymentLocation.diskEncryptionSet.resourceGroupName
    )
  }
]

resource rGallery 'Microsoft.Compute/galleries@2023-07-03' existing = {
  name: pGalleryImageDefinition.galleryName
  scope: resourceGroup(pGalleryImageDefinition.subscriptionId, pGalleryImageDefinition.resourceGroupName)

  resource rImage 'images@2023-07-03' existing = {
    name: pGalleryImageDefinition.name

    resource rVersion 'versions@2023-07-03' existing = {
      name: pGalleryImageDefinition.version
    }
  }
}

resource rKeyVaultAuth 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: pAuthKeyVault.name
  scope: resourceGroup(pAuthKeyVault.subscriptionId, pAuthKeyVault.resourceGroupName)

  resource rSecretServicePrincipalClientId 'secrets@2023-07-01' existing = {
    name: 'avd-operator-client-id'
  }

  resource rSecretServicePrincipalClientSecret 'secrets@2023-07-01' existing = {
    name: 'avd-operator-client-secret'
  }
}

resource rLogAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: pLogAnalyticsWorkspace.name
  scope: resourceGroup(pLogAnalyticsWorkspace.subscriptionId, pLogAnalyticsWorkspace.resourceGroupName)
}

resource rHostPool 'Microsoft.DesktopVirtualization/hostPools@2023-09-05' existing = {
  name: pHostPool.name
  scope: resourceGroup(pHostPool.subscriptionId, pHostPool.resourceGroupName)
}

resource rResourceGroupCompute 'Microsoft.Resources/resourceGroups@2024-03-01' existing = [
  for vDeploymentLocation in pDeploymentLocations: {
    name: vDeploymentLocation.computeResourceGroup.name
    scope: subscription(vDeploymentLocation.computeResourceGroup.subscriptionId)
  }
]

resource rVirtualNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' existing = [
  for vDeploymentLocation in pDeploymentLocations: {
    name: vDeploymentLocation.virtualNetworkSubnet.virtualNetworkName
    scope: resourceGroup(
      vDeploymentLocation.virtualNetworkSubnet.subscriptionId,
      vDeploymentLocation.virtualNetworkSubnet.resourceGroupName
    )
  }
]

resource rVirtualNetworkSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = [
  for vDeploymentLocation in pDeploymentLocations: {
    name: vDeploymentLocation.virtualNetworkSubnet.name
    parent: rVirtualNetwork[indexOf(pDeploymentLocations, vDeploymentLocation)]
  }
]

/////////////////////
// Resources - New //
/////////////////////

resource rScalingPlan 'Microsoft.DesktopVirtualization/scalingPlans@2025-04-01-preview' = [
  for vScalingPlan in pScalingPlans: {
    location: pLocation
    name: vScalingPlan.name
    properties: {
      description: ''
      friendlyName: vScalingPlan.name
      hostPoolType: 'Pooled'
      schedules: [
        {
          daysOfWeek: [
            'Monday'
            'Tuesday'
            'Wednesday'
            'Thursday'
            'Friday'
            'Saturday'
            'Sunday'
          ]
          name: 'Every Day'
          offPeakLoadBalancingAlgorithm: 'BreadthFirst'
          offPeakStartTime: {
            hour: 23
            minute: 59
          }
          peakLoadBalancingAlgorithm: 'BreadthFirst'
          peakStartTime: {
            hour: 11
            minute: 0
          }
          rampDownCapacityThresholdPct: 75
          rampDownForceLogoffUsers: false
          rampDownLoadBalancingAlgorithm: 'BreadthFirst'
          rampDownMinimumHostsPct: vScalingPlan.rampDownMinimumHostsPercent
          rampDownNotificationMessage: 'string'
          rampDownStartTime: {
            hour: 17
            minute: 0
          }
          rampDownStopHostsWhen: 'ZeroActiveSessions'
          rampDownWaitTimeMinutes: 30
          rampUpCapacityThresholdPct: 30
          rampUpLoadBalancingAlgorithm: 'BreadthFirst'
          rampUpMinimumHostsPct: vScalingPlan.rampUpMinimumHostsPercent
          rampUpStartTime: {
            hour: 4
            minute: 00
          }
          // scalingMethod: 'string'
        }
      ]
      timeZone: 'Eastern Standard Time'
    }
  }
]

resource rAppConfigurationStore 'Microsoft.AppConfiguration/configurationStores@2024-05-01' = {
  name: pHostPool.name
  location: pLocation
  properties: {
    disableLocalAuth: true
    dataPlaneProxy: {
      authenticationMode: 'Pass-through'
    }
  }
  tags: pTags
  sku: {
    name: 'standard'
  }
}

// Region specific app config keys
resource rAppConfigurationStoreKeyValueComputeResourceGroupId 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01' = [
  for vDeploymentLocation in pDeploymentLocations: {
    parent: rAppConfigurationStore
    name: 'ComputeResourceGroupId$${vDeploymentLocation.location}'
    properties: {
      value: rResourceGroupCompute[indexOf(pDeploymentLocations, vDeploymentLocation)].id
      tags: pTags
    }
  }
]

resource rAppConfigurationStoreKeyValueDiskEncryptionSetId 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01' = [
  for vDeploymentLocation in pDeploymentLocations: {
    parent: rAppConfigurationStore
    name: 'DiskEncryptionSetId$${vDeploymentLocation.location}'
    properties: {
      value: rDiskEncryptionSet[indexOf(pDeploymentLocations, vDeploymentLocation)].id
      tags: pTags
    }
  }
]

resource rAppConfigurationStoreKeyValueFSLogixStorageAccountName 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01' = [
  for vDeploymentLocation in pDeploymentLocations: {
    parent: rAppConfigurationStore
    name: 'FSLogixStorageAccountName$${vDeploymentLocation.location}'
    properties: {
      value: vDeploymentLocation.fslogixStorageAccountName
      tags: pTags
    }
  }
]

resource rAppConfigurationStoreKeyValueSessionHostNamePrefix 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01' = [
  for vDeploymentLocation in pDeploymentLocations: {
    parent: rAppConfigurationStore
    name: 'SessionHostNamePrefix$${vDeploymentLocation.location}'
    properties: {
      value: vDeploymentLocation.sessionHostNamePrefix
      tags: pTags
    }
  }
]

resource rAppConfigurationStoreKeyValueSubnetId 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01' = [
  for vDeploymentLocation in pDeploymentLocations: {
    parent: rAppConfigurationStore
    name: 'SubnetId$${vDeploymentLocation.location}'
    properties: {
      value: rVirtualNetworkSubnet[indexOf(pDeploymentLocations, vDeploymentLocation)].id
      tags: pTags
    }
  }
]

// Non-region specific app config keys
var vAppConfigurationStoreKeyValues = {
  AssetStorageAccountId: rStorageAccountAsset.id
  AuthKeyVaultId: rKeyVaultAuth.id
  BakeScalingPlanId: rScalingPlan[0].id // To Do: Don't rely on index order to get correct scaling plan
  ChangesAllowed: string(true)
  CleanupScalingPlanId: rScalingPlan[2].id // To Do: Don't rely on index order to get correct scaling plan
  CompliantScalingPlanId: rScalingPlan[1].id // To Do: Don't rely on index order to get correct scaling plan
  DeploymentLocationModel: 'Centralize'
  DisconnectUsersOnlyOnDrainedSessionHosts: string(true)
  EntraIdSecurityDeviceGroupJoinEnabled: string(false)
  EntraIdSecurityDeviceGroupName: pEntraIdSecurityDeviceGroupName
  Environment: pTags.environment
  FunctionAppName: pFunctionAppName
  FunctionAppResourceGroupName: pFunctionAppResourceGroupName
  GalleryImageDefinitionId: rGallery::rImage.id
  GalleryImageDefinitionVersionName: rGallery::rImage::rVersion.name
  HostPoolId: rHostPool.id
  MaxAllowedSessionsPerHost: string(pMaxAllowedSessionsPerHost)
  ReplacementMethod: 'Tags'
  ScalingPlanMode: 'Bake'
  SessionHostBuffer: json(pSessionHostBuffer)
  TargetSessionHostCount: string(pTargetSessionHostCount)
  VirtualMachineSKUSize: pVirtualMachineSKU
  WorkspaceId: rLogAnalyticsWorkspace.id
  WorkspaceIdentifier: pLogAnalyticsWorkspace.workspaceId
}

resource rAppConfigStoreKeyValue 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01' = [
  for vAppConfigurationStoreKey in objectKeys(vAppConfigurationStoreKeyValues): {
    parent: rAppConfigurationStore
    name: vAppConfigurationStoreKey
    properties: {
      value: vAppConfigurationStoreKeyValues[vAppConfigurationStoreKey]
      tags: pTags
    }
  }
]

resource rApplicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: pApplicationInsightsName
  location: pLocation
  kind: 'web'
  properties: {
    Application_Type: 'web'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    WorkspaceResourceId: rLogAnalyticsWorkspace.id
  }
  tags: pTags
}

resource rApplicationServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: pApplicationServicePlan.name
  location: pLocation
  kind: pApplicationServicePlan.kind
  properties: pApplicationServicePlan.properties
  sku: pApplicationServicePlan.sku
  tags: pTags
}

resource rStorageAccountAsset 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: pAssetStorageAccount.name
  kind: 'BlobStorage'
  sku: {
    name: 'Standard_GRS'
  }
  location: resourceGroup().location
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    encryption: {
      requireInfrastructureEncryption: true
    }
  }
  resource rBlobService 'blobServices@2023-05-01' = {
    name: 'default'

    resource rContainerrdagents 'containers@2023-05-01' = {
      name: 'rdagent-installers'
    }

    resource rContainerRunCmdLogs 'containers@2023-05-01' = {
      name: 'run-cmd-logs'
    }
  }
}

resource rStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: pStorageAccountName
  location: pLocation
  kind: pStorageAccountKind
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    encryption: {
      requireInfrastructureEncryption: true
    }
  }
  sku: {
    name: pStorageAccountSkuName
  }
  tags: pTags
}

resource rStorageAccountData 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: pStorageAccountDataName
  location: pLocation
  kind: pStorageAccountKind
  properties: {
    allowBlobPublicAccess: false
    encryption: {
      requireInfrastructureEncryption: true
    }
  }
  sku: {
    name: pStorageAccountSkuName
  }
  tags: pTags

  resource rBlobService 'blobServices@2023-01-01' = {
    name: 'default'

    resource rContainerAssets 'containers@2023-01-01' = {
      name: 'assets'
      properties: {
        publicAccess: 'None'
      }
    }
  }

  resource rQueueService 'queueServices@2023-05-01' = {
    name: 'default'

    resource rQueueCleanup 'queues@2023-05-01' = {
      name: 'virtual-machine-cleanup'
    }

    resource rQueueCreation 'queues@2023-05-01' = {
      name: 'virtual-machine-creation'
    }

    resource rQueueRegistration 'queues@2023-05-01' = {
      name: 'virtual-machine-registration'
    }
  }
}

resource rFunctionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: pFunctionAppName
  location: pLocation
  kind: 'functionApp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    httpsOnly: true
    serverFarmId: rApplicationServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: '_AppConfigURI'
          value: 'https://${rAppConfigurationStore.name}.azconfig.azure.us'
        }
        {
          name: '_FunctionAppSubscriptionId'
          value: split(subscription().id, '/')[2]
        }
        {
          name: '_ServicePrincipalClientId'
          value: '@Microsoft.KeyVault(SecretUri=${rKeyVaultAuth::rSecretServicePrincipalClientId.properties.secretUri})'
        }
        {
          name: '_ServicePrincipalClientSecret'
          value: '@Microsoft.KeyVault(SecretUri=${rKeyVaultAuth::rSecretServicePrincipalClientSecret.properties.secretUri})'
        }
        {
          name: '_TenantId'
          value: tenant().tenantId
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: rApplicationInsights.properties.ConnectionString
        }
        {
          name: 'AzureWebJobs.TimerDynamicTargetHostCount.Disabled'
          value: 'true'
        }
        {
          name: 'AzureWebJobs.TimerMinimumTargetHostCount.Disabled'
          value: 'true'
        }
        {
          name: 'AzureWebJobs.TimerDisconnectedUsersCleanup.Disabled'
          value: 'true'
        }
        {
          name: 'AzureWebJobs.QueueRegistration.Disabled'
          value: 'false'
        }
        {
          name: 'AzureWebJobs.TimerScheduler.Disabled'
          value: 'false'
        }
        {
          name: 'AzureWebJobs.QueueCreation.Disabled'
          value: 'false'
        }
        {
          name: 'AzureWebJobs.QueueCleanup.Disabled'
          value: 'false'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${rStorageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${rStorageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'AzureDataStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${rStorageAccountData.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${rStorageAccountData.listKeys().keys[0].value}'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME_VERSION'
          value: '7.4'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${rStorageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${rStorageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(pFunctionAppName)
        }
        {
          name: 'WEBSITE_LOAD_USER_PROFILE'
          value: '1'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
      cors: {
        allowedOrigins: [environment().portal]
      }
      ftpsState: 'Disabled'
      minTlsVersion: '1.3'
      netFrameworkVersion: 'v8.0'
      powerShellVersion: '7.4'
      use32BitWorkerProcess: false
    }
  }
  tags: pTags
}

/////////////
//  Alerts //
/////////////

resource rHttpServerAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Http 5xx Error Alert'
  location: pGlobalLocation
  properties: {
    description: 'Alert for http 5xx on ${pFunctionAppName}'
    severity: 2
    enabled: true
    evaluationFrequency: pEvaluationTime
    windowSize: pEvaluationTime
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Http Server Errors above 2'
          metricName: 'Http5xx'
          metricNamespace: 'Microsoft.Web/sites'
          operator: 'GreaterThan'
          timeAggregation: 'Maximum'
          threshold: 2
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    scopes: [
      rFunctionApp.id
    ]
  }
}

resource rHighCPUAlerts 'Microsoft.Insights/metricalerts@2018-03-01' = {
  name: 'High CPU Usage Alert'
  location: pGlobalLocation
  properties: {
    description: '${pApplicationServicePlan.name} CPU percentage is above the 80% threshold'
    severity: 2
    enabled: true
    evaluationFrequency: pEvaluationTime
    windowSize: pEvaluationTime
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'High CPU Percentage'
          metricName: 'CpuPercentage'
          metricNamespace: 'Microsoft.Web/serverFarms'
          operator: 'GreaterThan'
          timeAggregation: 'Maximum'
          threshold: 80
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    scopes: [
      rApplicationServicePlan.id
    ]
  }
}

resource rHighMemoryUsage 'Microsoft.Insights/metricalerts@2018-03-01' = {
  name: 'High Memory Percentage Alert'
  location: pGlobalLocation
  properties: {
    description: '${pApplicationServicePlan.name} Memory percentage is above the 85% threshold'
    severity: 2
    enabled: true
    evaluationFrequency: pEvaluationTime
    windowSize: pEvaluationTime
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'High Memory Percentage'
          metricName: 'MemoryPercentage'
          metricNamespace: 'Microsoft.Web/serverFarms'
          operator: 'GreaterThan'
          timeAggregation: 'Maximum'
          threshold: 85
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    scopes: [
      rApplicationServicePlan.id
    ]
  }
}

// resource rActivityLogAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
//   name: 'Resource Health Alerts'
//   location: pGlobalLocation
//   properties: {
//     description: '${pApplicationServicePlan.name} resource health alert'
//     enabled: true
//     condition: {
//       allOf: [
//         {
//           field: 'category'
//           equals: 'ResourceHealth'
//         }
//         {
//           anyOf: [
//             {
//               field: 'status'
//               equals: 'In Progress'
//             }
//             {
//               field: 'status'
//               equals: 'Active'
//             }
//             {
//               field: 'properties.previousHealthStatus'
//               equals: 'Available'
//             }
//             {
//               field: 'properties.previousHealthStatus'
//               equals: 'Unavailable'
//             }
//           ]
//         }
//       ]
//     }
//     scopes: [
//       rApplicationServicePlan.id
//     ]
//   }
// }

resource rFailedRequestsAlert 'Microsoft.Insights/metricalerts@2018-03-01' = {
  name: 'Failed Function Request Alert'
  location: pGlobalLocation
  properties: {
    description: 'A function in ${pApplicationServicePlan.name} failed'
    severity: 2
    enabled: true
    evaluationFrequency: pEvaluationTime
    windowSize: pEvaluationTime
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Failed Requests'
          metricName: 'requests/failed'
          metricNamespace: 'microsoft.insights/components'
          operator: 'GreaterThan'
          timeAggregation: 'Count'
          threshold: 0
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    scopes: [
      rApplicationInsights.id
    ]
  }
}

//////////////////////
// Role Definitions //
//////////////////////

var vRoleDefinitionId = {
  AppConfigDataOwner: '5ae67dd6-50cb-40e7-96ff-dc2bfa4b606b'
  KeyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
}

module mRoleAssignmentFunctionAppKeyVaultSecretsUser 'role-assignment-resource-group.module.bicep' = {
  name: 'function-app-rbac-key-vault-secrets-user'
  scope: resourceGroup(pAuthKeyVault.subscriptionId, pAuthKeyVault.resourceGroupName)
  params: {
    pPrincipalId: rFunctionApp.identity.principalId
    pRoleDefinitionId: vRoleDefinitionId.KeyVaultSecretsUser
  }
}

//TODO: Add storage blob data contributor & reader and data access for sp on sa for assets

// var servicePrincipalAppConfigOwnerAssignment tRoleDefinition = {
//     name: 'AppConfigurationDataOwner'
//     guid: '5ae67dd6-50cb-40e7-96ff-dc2bfa4b606b'
//   }

//TODO: Make this actually work
// module mRoleAssignmentSPAC 'role-assignment-resource-group.module.bicep' = {
//   name: 'service-principal-app-config-data-owner'
//   scope: resourceGroup(pAuthKeyVault.subscriptionId, pAuthKeyVault.resourceGroupName)
//   params: {
//     pPrincipalId: pServicePrincipalObjectId
//     pRoleDefinitionId: vRoleDefinitionId.AppConfigDataOwner
//   }
// }
