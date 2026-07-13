# ACR onboarding notes

This repo has two distinct Azure Container Registry roles in the existing build and release flow:

| Registry | Registry name | Login server | Role |
| --- | --- | --- | --- |
| Build/dev ACR | `aadproxydev` | `aadproxydev.azurecr.io` | Build pipeline output location for images and Helm charts. |
| Team/release ACR | `aadauthproxyacr` | `aadauthproxyacr.azurecr.io` | Team-owned registry intended to be onboarded to MAR/MCR. |

## Relationship between the registries

The current repo flow is:

```text
Pipeline build
  -> pushes image/chart to aadproxydev.azurecr.io
  -> Ev2 release imports/pushes from aadproxydev into aadauthproxyacr
  -> MAR/MCR webhook on aadauthproxyacr ingests artifacts
  -> consumers pull from mcr.microsoft.com/...
```

`aadproxydev` is the internal build/staging registry used by the Azure Pipeline. `aadauthproxyacr` is the curated team registry that MAR/MCR should use as its source after onboarding.

## How this ties to the Bicep configuration

The Bicep in this folder currently creates the team/release ACR:

- Subscription: `ccb26e1b-bda3-40b0-83ea-1e68b37f2dbb`
- Location: `westus`
- Resource group: `rg-aad-auth-proxy-acr`
- ACR name: `aadauthproxyacr`
- SKU: `Premium`
- AVM modules:
  - `br/public:avm/res/resources/resource-group:0.4.3`
  - `br/public:avm/res/container-registry/registry:0.12.1`

Azure Container Registry names cannot contain hyphens, so the requested name `aad-auth-proxy-acr` is represented as `aadauthproxyacr`.

If the existing build pipeline needs to run unchanged in a new environment, `aadproxydev` also needs to exist because `.pipelines/azure-pipeline-build.yml` logs into and pushes to `aadproxydev.azurecr.io`.

## Existing repo dependencies

The ACR dependencies are pipeline and release dependencies, not application runtime code dependencies.

| File | Dependency |
| --- | --- |
| `.pipelines/azure-pipeline-build.yml` | Defines `ACR_REGISTRY: aadproxydev.azurecr.io`, image repo, Helm repo, and pushes build outputs to the dev ACR. |
| `.pipelines/deployment/ServiceGroupRoot/Scripts/pushAgentToAcr.sh` | Imports the built image from `BUILD_ACR` into `DESTINATION_ACR_NAME` using `az acr import`. |
| `.pipelines/deployment/ServiceGroupRoot/Scripts/pushChartToAcr.sh` | Logs into `DESTINATION_ACR_NAME` and pushes the Helm chart with `helm push`. |
| `.pipelines/deployment/ServiceGroupRoot/ScopeBindings/ScopeBindings.json` | Maps release variables such as `DestinationACRName`, `BuildACR`, `BuildRepoName`, and tags. |
| `.pipelines/deployment/ServiceGroupRoot/Parameters/Parameters.json` | Passes image publishing variables into `PushAgentToACR`. |
| `.pipelines/deployment/ServiceGroupRoot/Parameters/ChartParameters.json` | Passes chart publishing variables into `PushChartToACR`. |
| `deploy/chart/aad-auth-proxy/values-template.yaml` | Uses `MCR_REGISTRY` and `MCR_REPOSITORY` for runtime image references. |

## MAR/MCR onboarding tie-in

The "Onboarding the Team ACR" guidance treats the team ACR as the authoritative source registry for MAR/MCR. After the ACR exists, the MAR/MCR onboarding script must be run to install the `MCROnboard` webhook.

Expected onboarding command shape:

```powershell
pwsh -ExecutionPolicy Bypass -File .\mcronboard.ps1 `
  -SubscriptionId "ccb26e1b-bda3-40b0-83ea-1e68b37f2dbb" `
  -resourceGroup "rg-aad-auth-proxy-acr" `
  -registry "aadauthproxyacr"
```

The onboarding process requires the MAR/MCR webhook code from the documented Key Vault and an account with permissions to manage the ACR. After onboarding, verify that the `MCROnboard` webhook exists on `aadauthproxyacr` and that its ping succeeded.

MAR/MCR does not ingest images already present before onboarding. Existing images must be pushed or re-imported after the webhook is installed.

## Repository path implications

The existing pipeline already uses repository paths under the supported `public/` prefix:

- Image build repository: `/public/azuremonitor/auth-proxy/dev/aad-auth-proxy/images`
- Helm chart build repository: `/public/azuremonitor/auth-proxy/dev`

If `aadauthproxyacr` becomes the MAR/MCR source registry, the release configuration should set `DestinationACRName` to `aadauthproxyacr`, and the release should push or import artifacts after MAR/MCR onboarding is complete.

## Proposed simplification: direct push to team ACR

This is a proposed future implementation. The current build and Ev2 implementation described above remains unchanged for now.

The simplification under discussion is to create a new pipeline that pushes directly to `aadauthproxyacr`, which would avoid both `aadproxydev` and the Ev2 ACR-to-ACR import pipeline:

```text
New pipeline
  -> authenticates with Azure through FIC service connection
  -> logs into aadauthproxyacr.azurecr.io
  -> builds and pushes image/chart directly into aadauthproxyacr
  -> MAR/MCR webhook on aadauthproxyacr ingests artifacts
  -> consumers pull from mcr.microsoft.com/...
```

### FIC service connection

The available Azure DevOps service connection is:

- Project: `Xbox.Services`
- Service connection resource ID: `79f5e9cb-7ef2-4545-a468-bbdf2e85feba`
- URL: `https://microsoft.visualstudio.com/Xbox.Services/_settings/adminservices?resourceId=79f5e9cb-7ef2-4545-a468-bbdf2e85feba`
- Auth model: Federated identity credential (FIC)

The new pipeline should use an Azure task, such as `AzureCLI@2`, with this service connection. The service connection's managed identity or service principal needs `AcrPush` on `aadauthproxyacr`.

Even though `aad-auth-proxy` is hosted in GitHub, Azure DevOps can run a YAML pipeline from a GitHub repository and still use Azure DevOps service connections. The service connection is resolved by the Azure DevOps project running the pipeline, not by GitHub.

### Proposed implementation changes

No application code changes appear necessary for this direct-push model. The required changes should be limited to pipeline and infrastructure/RBAC wiring:

1. Add a new Azure Pipelines YAML that builds the existing Go binary and Docker image, similar to the current `Build` job. Initial draft: `.pipelines/azure-pipeline-acr-direct.yml`.
2. Push the image directly to `aadauthproxyacr.azurecr.io` instead of `aadproxydev.azurecr.io`.
3. Package and push the Helm chart directly to `aadauthproxyacr.azurecr.io` as an OCI artifact.
4. Grant the FIC service connection identity `AcrPush` on `aadauthproxyacr`.
5. Run the pipeline only after `aadauthproxyacr` has been onboarded to MAR/MCR so the `MCROnboard` webhook can ingest newly pushed artifacts.

The pipeline should avoid `ACR_USERNAME` and `ACR_PASSWORD`; the AVM ACR module leaves the admin user disabled by default, which is preferred. Instead, authenticate through the service connection and then run:

```bash
az acr login --name aadauthproxyacr
docker buildx build ... --tag aadauthproxyacr.azurecr.io/public/azuremonitor/auth-proxy/prod/aad-auth-proxy/images/aad-auth-proxy:${IMAGE_TAG} --push
```

For Helm OCI pushes, use an ACR access token from the same service connection context:

```bash
ACCESS_TOKEN=$(az acr login --name aadauthproxyacr --expose-token --output tsv --query accessToken)
echo "$ACCESS_TOKEN" | helm registry login aadauthproxyacr.azurecr.io \
  -u 00000000-0000-0000-0000-000000000000 \
  --password-stdin
helm push aad-auth-proxy-${HELM_SEMVER}.tgz oci://aadauthproxyacr.azurecr.io/public/azuremonitor/auth-proxy/prod/aad-auth-proxy/helmchart
```
