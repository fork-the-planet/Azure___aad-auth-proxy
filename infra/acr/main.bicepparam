using './main.bicep'

param location = 'westus'
param resourceGroupName = 'rg-aad-auth-proxy-acr'
param acrName = 'aadauthproxyacr'
param tags = {
  workload: 'aad-auth-proxy'
}
