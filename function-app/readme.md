# AVD Operator Deployment

1. Prerequisites
   1. Azure tenant with Contributor and User Access Administrator roles on the environment.
   1. Service Principal with the following configuration:
      1. Requires Contributor and User Access Administrator on the environment
         1. User Access Administrator roles can be limited to:
            1. `App Configuration Data Owner` for the Service Principal to allow it to read the App Configuration for the host pool.
            1. `Key Vault Secrets User` for the function app to allow it to read Key Vault secrets to authenticate with the Service Principal.
      1. `Cloud Device Administrator` role assigned to Entra ID to manage device registrations. Can be constrained by putting devices in a dynamic group that populates an Entra Administrative Unit.
      1. Client/App ID and Secret stored in Key Vault to allow the function app to authenticate to Azure and Entra.
         1. Name of Service Principal Client ID: `avd-operator-client-id`
         1. Name of Service Principal Secret: `avd-operator-client-secret`
   1. `Desktop Virtualization Power On Off Contributor` for the first-party Azure Virtual Desktop App Registration set on the session hosts' subscription.
   1. FSLogix `Storage Account` that has been configured for the correct identity solution.
      1. Defined in the `DEPLOYMENT_LOCATIONS` parameter within the `fslogixStorageAccountName` property.
      1. Existing Log Analytics Workspace information is contained in the `LOG_ANALYTICS_WORKSPACE` parameter.
   1. `Disk Encryption Set` used to encypt session host disks (OS and Data).
      1. Defined in the `DEPLOYMENT_LOCATIONS` parameter within the `diskEncryptionSet` property.
   1. `Dynamic Entra Device Security Group` *(Intune only)
      1. Used when Intune compliance is required.
   1. `Azure Gallery Image` to build the session hosts.
      1. Defined in the `GALLERY_IMAGE_DEFINITION` parameter.
   1. `AVD Host Pool` and associated dependencies (application group, workspace, etc).
      1. Defined in the `HOST_POOL` parameter.
      1. Ensure the [proper permissions are in place](https://learn.microsoft.com/en-us/azure/virtual-desktop/autoscale-create-assign-scaling-plan?tabs=portal%2Cintune&pivots=power-management#assign-permissions-to-the-azure-virtual-desktop-service-principal) for the AVD service principal to manage host pools' scaling plans.
   1. `Log Analytics Workspace` to send AVD Insights data and logs.
      1. Defined in the `LOG_ANALYTICS_WORKSPACE` parameter.
   

# Notes
maxDequeueCount should be set to 5, but for testing, set to 1. In file `function-app\host.json::extensions\maxDequeueCount`
