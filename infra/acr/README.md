# Azure Container Registry

This template creates a new resource group and a Premium Azure Container Registry for `aad-auth-proxy` by using Azure Verified Modules.

## Deploy

```bash
az account set --subscription ccb26e1b-bda3-40b0-83ea-1e68b37f2dbb

az deployment sub what-if \
  --location westus \
  --template-file infra/acr/main.bicep \
  --parameters infra/acr/main.bicepparam

az deployment sub create \
  --location westus \
  --template-file infra/acr/main.bicep \
  --parameters infra/acr/main.bicepparam
```

The requested ACR display name `aad-auth-proxy-acr` is represented as `aadauthproxyacr` because Azure Container Registry names must be globally unique and contain only alphanumeric characters.
