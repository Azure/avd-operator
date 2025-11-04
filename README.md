# AVD Operator

## Description
AVD Operator is a tool made of first-party tools that is intended to manage the operations of host management in Azure Virtual Desktop (AVD) environments. It is not intended to be a tool to deploy AVD core resources; it is intended to maintain the lifecycle of the AVD session hosts to ensure hosts are up to date with patches, applications, etc.

The core Azure resources making up AVD Operator are Function Apps, App Configurations, Storage Queues, Key Vaults, & Storage Accounts.

# Deployment Instructions

## Prerequisites
1. Azure tenant with Contributor and User Access Administrator roles on the environment.
1. Service Principal with the following configuration:
   1. Requires Contributor and User Access Administrator on the environment
      1. User Access Administrator roles can be limited to:
         1. `App Configuration Data Owner` for the Service Principal to allow it to read the App Configuration for the host pool.
         1. `Key Vault Secrets User` for the function app to allow it to read Key Vault secrets to authenticate with the Service Principal.
   1. `Cloud Device Administrator` role assigned to Entra ID to manage device registrations. Can be constrained by putting devices in a dynamic group that populates an Entra Administrative Unit.
   1. Client/App ID and Secret stored in a Key Vault (defined in `pAuthKeyVault`) to allow the function app to authenticate to Azure and Entra.
      1. Name of Service Principal Client ID: `avd-operator-client-id`
      1. Name of Service Principal Secret: `avd-operator-client-secret`
1. `Desktop Virtualization Power On Off Contributor` for the first-party `Azure Virtual Desktop` App Registration set on the session hosts' subscription. [For more information](https://learn.microsoft.com/en-us/azure/virtual-desktop/autoscale-create-assign-scaling-plan?tabs=portal%2Cintune&pivots=power-management#assign-permissions-to-the-azure-virtual-desktop-service-principal).
1. FSLogix `Storage Account` that has been configured for the correct identity solution.
   1. Defined in the `DEPLOYMENT_LOCATIONS` parameter within the `fslogixStorageAccountName` property.
   1. Existing Log Analytics Workspace information is contained in the `LOG_ANALYTICS_WORKSPACE` parameter.
1. `Disk Encryption Set` used to encrypt session host disks (OS and Data).
   1. Defined in the `DEPLOYMENT_LOCATIONS` parameter within the `diskEncryptionSet` property.
1. `Dynamic Entra Device Security Group` *(Intune only)
   1. Used when Intune compliance is required.
1. `Azure Gallery Image` to build the session hosts.
   1. Defined in the `GALLERY_IMAGE_DEFINITION` parameter.
1. `AVD Host Pool` and associated dependencies (application group, workspace, etc).
   1. Defined in the `HOST_POOL` parameter.
1. `Log Analytics Workspace` to send AVD Insights data and logs.
   1. Defined in the `LOG_ANALYTICS_WORKSPACE` parameter.

## 1. Deploy Bicep
1. After fulfilling the prerequisites, populate the `./bicep/main.template.bicepparam` parameter file. Make sure to rename the file to match the appropriate environment. Parameter descriptions are found in the parameter file.
1. Once the parameter file is populated with appropriate values, Run the `Invoke-BicepDeployment.ps1` script with appropriate deployment settings. Those settings/parameters are found in the comment-based help of the script, along with an example. See Notes section below for troubleshooting.

## 2. Deploy Function App
1. Once the Bicep template is deployed successfully, the contents of the function app need to be deployed. Run the `Invoke-FunctionAppDeployment.ps1` script to do so. Parameter descriptions and an example can be found in the comment-based help of the script.

## 3. Stage Remote Desktop Agents
1. Finally, run the `Invoke-RdAgentDownload.ps1` script to stage the required binaries for the Remote Desktop agents to be installed during host deployment and configuration. Parameter descriptions and an example can be found in the comment-based help of the script.

## Notes
- `maxDequeueCount` for the functions should be set to 5, but for testing, set to 1, in file `function-app\host.json::extensions\maxDequeueCount`
- Ensure `pServicePrincipalObjectId` value is the object ID from the Service Principal.
- It is assumed a user account is deploying the bicep template. See Bicep resource `rRoleAssignmentDeployer` for details or to make changes to allow for a service principal deployment.
- Error `[Error]   EXCEPTION: Value cannot be null. (Parameter 'key')` means one of the `subscriptionId` properties in the bicepparam file is incorrect.
- Sometimes Storage Account authorization seems to get stuck. If that happens, reauthenticate the storage account:
   ```PowerShell
   Set-AzStorageAccount `
      -ResourceGroupName "<RG_NAME>" `
      -Name "<SA_NAME>" `
      -EnableActiveDirectoryDomainServicesForFile $true `
      -ActiveDirectoryDomainName "<DOMAIN.NAME>" `
      -ActiveDirectoryNetBiosDomainName "<DOMAIN>" `
      -ActiveDirectoryForestName "<FOREST.NAME>" `
      -ActiveDirectoryDomainGuid "<GUID>" `
      -ActiveDirectoryDomainsid "<SID>" `
      -ActiveDirectoryAzureStorageSid "<STORAGE_SID>" `
      -ActiveDirectorySamAccountName "<SA_NAME>" `
      -ActiveDirectoryAccountType "Computer"
   ```
- TODO: Add documentation for host file entries and pass in via param.

## Known Issues
- If run in Windows PowerShell 5, the Bicep deployment will fail due to missing permissions on the App Configuration resource.
- On first deployment, the app configuration key values might respond with a 'forbidden' message. If this occurs, wait 5-15 minutes and redeploy. This is due to the assigned RBAC role taking a while to replicate. If the issue persists, reauthenticate with `az login`.
