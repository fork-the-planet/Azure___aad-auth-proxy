targetScope = 'subscription'

@description('Azure region where the resource group and Azure Container Registry will be deployed.')
param location string = 'westus'

@description('Name of the resource group to create for the Azure Container Registry.')
param resourceGroupName string = 'rg-aad-auth-proxy-acr'

@description('Name of the Azure Container Registry. Must be globally unique and contain only alphanumeric characters.')
@minLength(5)
@maxLength(50)
param acrName string = 'aadauthproxyacr'

@description('Tags to apply to deployed resources.')
param tags object = {
  workload: 'aad-auth-proxy'
}

module acrResourceGroup 'br/public:avm/res/resources/resource-group:0.4.3' = {
  name: 'acr-resource-group'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module acr 'br/public:avm/res/container-registry/registry:0.12.1' = {
  name: 'acr'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: acrName
    location: location
    acrSku: 'Premium'
    publicNetworkAccess: 'Disabled'
    tags: tags
  }
  dependsOn: [
    acrResourceGroup
  ]
}

output resourceGroupName string = acrResourceGroup.outputs.name
output resourceGroupResourceId string = acrResourceGroup.outputs.resourceId
output acrName string = acr.outputs.name
output acrResourceId string = acr.outputs.resourceId
output acrLoginServer string = acr.outputs.loginServer
