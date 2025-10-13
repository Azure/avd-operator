targetScope = 'resourceGroup'

///////////////////////////
// Parameters - Required //
///////////////////////////

param pPrincipalId string
param pRoleDefinitionId string

///////////////////////////
// Parameters - Optional //
///////////////////////////

param proleAssignmentName string = guid(pPrincipalId, pRoleDefinitionId, resourceGroup().id)
param pprincipalType string = 'ServicePrincipal'

/////////////////////
// Resources - New //
/////////////////////

resource rRoleAssignmentResourceGroup 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: proleAssignmentName
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', pRoleDefinitionId)
    principalId: pPrincipalId
    principalType: pprincipalType
  }
}

/////////////
// Outputs //
/////////////

// output id string = rRoleAssignmentResourceGroup.id
