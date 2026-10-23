# Azure Databricks Private Workspace Deployment

Part of **DBX Architect Lab**, an enterprise Databricks platform built in public:
[YouTube](https://www.youtube.com/@DBxArchitectLab) ·
[LinkedIn](https://www.linkedin.com/in/DBxArchitectLab) ·
[GitHub](https://github.com/DBxArchitectLab)

This repository provisions three Azure Databricks workspaces (dev, uat and prod, in `centralus`) that share one
Unity Catalog metastore. Each workspace gets:

- an existing resource group per environment
- a new VNet created from a given name and CIDR
- a new Databricks public/host subnet created from a given CIDR
- a new Databricks private/container subnet created from a given CIDR
- a new private endpoint subnet created from a given CIDR
- Secure Cluster Connectivity (no public IPs on cluster nodes)
- NSG rules set to `NoAzureDatabricksRules` (no Databricks-managed NSG rules; Private Link is used instead)
- 3 private endpoints
- workspace public network access, controlled by config (on in dev, uat and prod, so the workspace is reachable both
  publicly and through its private endpoints)
- Unity Catalog metastore assignment (the metastore is managed by a dedicated stack)
- workspace admin assignment for an account-level group
- workspace bootstrap (ADLS storage, access connector, storage credential, external location, catalog, default
  catalog, cluster policies, secret scope, validation notebook)

## Deployment pattern

- Terraform modules contain provisioning logic
- Terragrunt orchestrates deployments
- `live/root.hcl` holds the remote state (Azure Storage, Entra ID auth) and generates the providers for every stack
- `live/metastore/config.yaml` and `live/<env>/config.yaml` store each stack's inputs; `live/<env>/env.hcl` loads
  `config.yaml` and reads the subscription and Databricks account IDs from environment variables
- `live/<env>/workspace-bootstrap/*-config.yaml` describe the bootstrap objects (storage, external location,
  catalog, cluster policies, secret scope)

## What this creates

- **Metastore layer (`metastore` stack)**
  - Databricks Unity Catalog metastore (account-level, one per region), owned by `DBX_Architect_Lab_Admin`. This
    repository adopts the metastore Databricks created automatically in `centralus` (`metastore.import_id` in
    `live/metastore/config.yaml`), so the stack imports it instead of creating a second one
  - Optional default metastore data access using an Azure Databricks Access Connector (when configured)

- **Workspace layer (`workspace` stack)**
  - VNet, the three subnets (public and private delegated to `Microsoft.Databricks/workspaces`) and one NSG shared
    by them
  - Azure Databricks workspace (Premium)
  - Private DNS zone or reuse of an existing one, and its VNet link
  - 3 private endpoints in the private endpoint subnet: `databricks_ui_api` (ui), `browser_authentication` (auth),
    and a second `databricks_ui_api` (backend)
  - Databricks Unity Catalog metastore assignment
  - Databricks workspace admin assignment for an account-level group

- **Workspace bootstrap layer (`workspace-bootstrap` stack)**
  - ADLS Gen2 storage account and container (from `adls-storage-config.yaml`)
  - Azure Databricks Access Connector (system-assigned managed identity), with Storage Blob Data Contributor on that
    storage account when `manage_access_connector_storage_rbac` is `true` (the default)
  - Unity Catalog storage credential and external location, with grants (from `external-location-config.yaml`)
  - Unity Catalog catalog, with grants (from `catalog-config.yaml`). It's isolated and bound to this
    environment's workspace only, so `dbxarchitectlab_dev` is visible in dev but not in uat or prod. The storage
    credential and external location are not isolated: any workspace on the metastore can use them, subject to
    grants.
  - Workspace default catalog set to that catalog
  - Databricks cluster policies (from `cluster-policy-config.yaml`)
  - Databricks secret scope (from `secret-scope-config.yaml`)
  - Validation notebook `/Shared/platform/workspace-bootstrap-validation`, with this environment's expected values
    in `/Shared/platform/workspace-bootstrap-validation.json`
    (`modules/workspace_bootstrap/notebooks/workspace-bootstrap-validation.py`; see
    [DEPLOYMENT.md section 7](DEPLOYMENT.md#7-verify))
  - Clusters and SQL warehouses (`cluster-config.yaml`, `sql-warehouse-config.yaml`) are defined but currently
    disabled: their modules are commented out in `modules/workspace_bootstrap/main.tf`. Keep the files; the
    module still reads them.

## What this does not create

- Resource groups
- Terraform state storage account
- NAT Gateway: classic clusters have no outbound internet access, so the validation notebook's internet check warns
- UC schemas

It also doesn't remove the workspace catalog (`dbw_dbx_architect_lab_<env>`) that Databricks creates
automatically for each workspace. Drop it by hand; see
[DEPLOYMENT.md](DEPLOYMENT.md#drop-the-automatic-workspace-catalog-once-per-workspace).

## Prerequisites

See [DEPLOYMENT.md](DEPLOYMENT.md) for the full setup and deployment steps.
[`scripts/setup-azure-prerequisites.sh`](scripts/setup-azure-prerequisites.sh) creates the Azure parts, and
[`scripts/preflight-check.sh`](scripts/preflight-check.sh) checks everything before a deployment (both are Bash
scripts). In short, the following must already exist:

- Azure resource groups for each environment and for the Terraform state
- Registered resource providers (Terraform doesn't register them)
- ADLS Gen2 storage account with `tfstate` and metastore root containers
- Service principal with a client secret and GitHub federated credentials, and these Azure roles: Contributor on the
  subscription, User Access Administrator on each environment's resource group (prod too), and Storage Blob Data
  Contributor on the state storage account
- Databricks account with the service principal as account admin
- Databricks account group `DBX_Architect_Lab_Admin` containing the service principal (as the metastore owner, the
  group makes the service principal a metastore admin, which bootstrap needs)
- (Optional) Databricks Access Connector resource (if enabling default metastore data access)

If Databricks already created a metastore in the region, adopt it with `metastore.import_id`, or the metastore
stack fails trying to create a second one; see DEPLOYMENT.md step 3.

Tools: Azure CLI, Terraform >= 1.8 and Terragrunt (CI uses Terraform 1.14.6 and Terragrunt 0.99.4). Providers:
`azurerm` ~> 4.0; `databricks` >= 1.105.0; `time` ~> 0.12.

## Authentication

### AzureRM
Use Azure CLI, service principal, or managed identity.

### Databricks account-level provider
Use account-level authentication against:

https://accounts.azuredatabricks.net

The execution identity must be able to:
- create the Unity Catalog metastore
- read account groups
- assign a workspace to a metastore
- assign workspace admin permissions

### Databricks workspace-level provider (workspace bootstrap)

For the `workspace-bootstrap` stack, the Databricks provider is configured with:

- `host` = workspace URL (from the `workspace` stack output)
- `azure_workspace_resource_id` = Azure resource ID of the workspace
- `auth_type = "azure-cli"`: it always uses the Azure CLI's signed-in identity, never `ARM_CLIENT_SECRET`

So the identity depends on where it runs:

- **Locally:** whoever ran `az login`. That user needs access to the workspace and the same Unity Catalog
  permissions as the service principal.
- **GitHub Actions:** the service principal, signed in to the CLI by the `azure/login` step with GitHub OIDC.
  That step needs a federated credential for the GitHub environment
  ([DEPLOYMENT.md step 2.4](DEPLOYMENT.md#24-service-principal-for-github-actions)).

The other providers (azurerm, the state backend and the account-level Databricks provider) read the `ARM_*`
variables in GitHub Actions, which the workflow sets from the `SP_CLIENT_ID`, `SP_CLIENT_SECRET` and
`AZURE_TENANT_ID` secrets. Locally they use your `az login`.

## Run

The environment is split into Terragrunt stacks, deployed in this order:

1. `live/metastore` (Unity Catalog metastore, once per region)
2. `live/<env>/workspace` (workspace + networking + UC metastore assignment)
3. `live/<env>/workspace-bootstrap` (storage, access connector, catalog, external location, policies, secret scope,
   validation notebook)

Deploy dev first, then uat and prod (same layout under `live/uat` and `live/prod`).

### Required environment variables

The Azure subscription ID and Databricks account ID are not stored in the repo. Terragrunt reads them from
environment variables and fails if they are missing:

| Variable | Used for |
| --- | --- |
| `ARM_SUBSCRIPTION_ID` | Target subscription for resources and the Terraform state backend |
| `DATABRICKS_ACCOUNT_ID` | Databricks account-level provider |
| `DATABRICKS_METASTORE_ID` | Unity Catalog metastore assigned to the workspace (required by the `*/workspace` stacks; optional in workspace-bootstrap, where it only feeds the validation notebook) |
| `DEPLOY_SP_APPLICATION_ID` | Application ID of the deployment service principal, granted on the catalog and external location (`*/workspace-bootstrap` stacks). In GitHub Actions it comes from `SP_CLIENT_ID`. |

For local runs, sign in and export them before calling `terragrunt` (see
[DEPLOYMENT.md, Running locally instead](DEPLOYMENT.md#running-locally-instead)). The state backend uses Entra ID
auth, so your user needs Storage Blob Data Contributor on the state storage account, and your IP must be allowed
on its firewall.

```bash
az login
az account set --subscription "<subscription-id>"

export ARM_SUBSCRIPTION_ID="<subscription-id>"
export DATABRICKS_ACCOUNT_ID="<databricks-account-id>"
export DATABRICKS_METASTORE_ID="<metastore-id>"
export DEPLOY_SP_APPLICATION_ID="<service-principal-application-id>"
```

### Local run - metastore layer

From `live/metastore`:

```bash
terragrunt init
terragrunt validate
terragrunt plan
terragrunt apply
```

After applying the metastore stack, set the `DATABRICKS_METASTORE_ID` environment variable (or GitHub environment
secret) to the metastore ID it outputs; the workspace stacks read it from there.

### Local run - workspace layer

From `live/dev/workspace`:

```bash
terragrunt init
terragrunt validate
terragrunt plan
terragrunt apply
```

### Local run - workspace bootstrap layer

Prerequisite: the workspace stack has been applied successfully.

From `live/dev/workspace-bootstrap`:

```bash
terragrunt init
terragrunt validate
terragrunt plan
terragrunt apply
```

The apply pauses for 120 seconds after the access connector's role assignment, so the permission reaches Azure
Storage before Unity Catalog validates the external location.

### GitHub Actions

The **Terragrunt Deploy Stacks** workflow (`.github/workflows/terragrunt-deploy.yml`) is run manually (Actions →
Terragrunt Deploy Stacks → Run workflow). Pick a stack (`metastore`, or `<env>-dbxarchitectlab-workspace` /
`<env>-dbxarchitectlab-workspace-bootstrap` for `dev`, `uat` or `prod`) and an action (`validate`, `plan` (the
default), `apply` or `destroy`). The job runs in the matching GitHub environment (`prod-*` → `prod`, `uat-*` →
`uat`, everything else, including `metastore` → `dev`) and reads its secrets from there.

Each of the `dev`, `uat` and `prod` environments needs these secrets:

| Secret | Value |
| --- | --- |
| `SP_CLIENT_ID` | Service principal application (client) ID |
| `SP_CLIENT_SECRET` | Service principal client secret |
| `AZURE_TENANT_ID` | Entra ID tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID |
| `DATABRICKS_ACCOUNT_ID` | Databricks account ID |
| `DATABRICKS_METASTORE_ID` | The metastore stack's metastore ID output; a placeholder until the metastore exists |

The job temporarily allow-lists the runner's egress IP on the Terraform state storage account firewall
before running Terragrunt, and removes it again when the job finishes (even on failure). The state storage
account and resource group are set as `TF_STATE_*` variables at the top of the workflow and must match
`remote_state` in `live/root.hcl`.

`apply` and `destroy` run with `-auto-approve`; add required reviewers to the `prod` environment if you want a
manual gate.

### Destroy

Destroy in reverse order: `<env>-dbxarchitectlab-workspace-bootstrap`, then `<env>-dbxarchitectlab-workspace` for
each environment, then `metastore` once no environment uses it.

`force_destroy` is on for the catalog and external location in every environment
(`storage_account.force_destroy` in `adls-storage-config.yaml`), so destroy deletes their contents too,
including the dropped test table the validation notebook leaves behind (restorable for 7 days). It is off for
the shared metastore: destroying the `metastore` stack fails while the metastore still has catalogs.

## DBX Architect Lab

This repository is part of **DBX Architect Lab**: one enterprise Databricks platform on Azure, AWS and Google
Cloud, built in public. The videos walk through the architecture and the deployment step by step.

- YouTube: [youtube.com/@DBxArchitectLab](https://www.youtube.com/@DBxArchitectLab)
- LinkedIn: [linkedin.com/in/DBxArchitectLab](https://www.linkedin.com/in/DBxArchitectLab)
- GitHub: [github.com/DBxArchitectLab](https://github.com/DBxArchitectLab)

## Contributing and license

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under the
[Apache License 2.0](LICENSE); see also [NOTICE](NOTICE).
