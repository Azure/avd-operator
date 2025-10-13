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

type tResource = {
  name: string
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

///////////////////////////
// Parameters - Required //
///////////////////////////

param pAppConfigurationStoreName string
param pAuthKeyVault tResource
param pFunctionAppName string
param pLocation string
param pLogAnalyticsWorkspace tResource
param pTags tTags

///////////////////////////
// Parameters - Optional //
///////////////////////////

param pGlobalLocation string = 'global'
param pEvaluationTime string = 'PT5M'
param pApplicationInsightsName string = pFunctionAppName
param pStorageAccountDataName string = '${toLower(replace(replace(pFunctionAppName, '-', ''), '_', ''))}d'
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

param pStorageAccountKind string = 'StorageV2'
param pStorageAccountName string = toLower(replace(replace(pFunctionAppName, '-', ''), '_', ''))
param pStorageAccountSkuName string = 'Standard_LRS'

// //////////////////////////
// // Resources - Existing //
// //////////////////////////

resource rKeyVaultAuth 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: pAuthKeyVault.name
  scope: resourceGroup(pAuthKeyVault.subscriptionId, pAuthKeyVault.resourceGroupName)

  resource rSecretServicePrincipalClientId 'secrets@2023-07-01' existing = {
    name: 'avd-automation-client-id'
  }

  resource rSecretServicePrincipalClientSecret 'secrets@2023-07-01' existing = {
    name: 'avd-automation-client-secret'
  }
}

resource rLogAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: pLogAnalyticsWorkspace.name
  scope: resourceGroup(pLogAnalyticsWorkspace.subscriptionId, pLogAnalyticsWorkspace.resourceGroupName)
}

/////////////////////
// Resources - New //
/////////////////////

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

resource rStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: pStorageAccountName
  location: pLocation
  kind: pStorageAccountKind
  tags: pTags
  sku: {
    name: pStorageAccountSkuName
  }
}

resource rStorageAccountData 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: pStorageAccountDataName
  location: pLocation
  kind: pStorageAccountKind
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
          value: 'https://${pAppConfigurationStoreName}.azconfig.azure.us'
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
      minTlsVersion: '1.2'
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

resource rActivityLogAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'Resource Health Alerts'
  location: pGlobalLocation
  properties: {
    description: '${pApplicationServicePlan.name} resource health alert'
    enabled: true
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ResourceHealth'
        }
        {
          anyOf: [
            {
              field: 'status'
              equals: 'In Progress'
            }
            {
              field: 'status'
              equals: 'Active'
            }
            {
              field: 'properties.previousHealthStatus'
              equals: 'Available'
            }
            {
              field: 'properties.previousHealthStatus'
              equals: 'Unavailable'
            }
          ]
        }
      ]
    }
    scopes: [
      rApplicationServicePlan.id
    ]
  }
}

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

/////////////
// Modules //
/////////////

var vRoleDefinitionId = {
  KeyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
}

module mRoleAssignmentFunctionAppKeyVaultSecretsUser 'role-assignment-resource-group.module.bicep' = {
  name: 'geekly-rbac-key-vault-secrets-user'
  scope: resourceGroup(pAuthKeyVault.subscriptionId, pAuthKeyVault.resourceGroupName)
  params: {
    pPrincipalId: rFunctionApp.identity.principalId
    pRoleDefinitionId: vRoleDefinitionId.KeyVaultSecretsUser
  }
}
