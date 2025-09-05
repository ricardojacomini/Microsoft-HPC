# CycleCloud Custom Role and Identity Script

This repository contains a Bash script to automate the creation of a custom Azure role, managed identity, and related resources for Microsoft CycleCloud deployments.

## Features
- Interactive Azure subscription selection (with current subscription highlighted in cyan)
- Custom role creation from a `role.json` template
- Managed identity creation and assignment of custom role
- Storage account and private endpoint provisioning

## Prerequisites
- Azure CLI (`az`)
- `jq` (for JSON parsing)
- Sufficient Azure permissions to create roles, identities, and resources
- You must have a VM deployed with CycleCloud before running the script

## Quick Setup: What to Change
At the top of `az-create-cc-role.sh`, you only need to edit these variables:

- `LOCATION` — Set your Azure region (e.g., `"East US"`, `"West US"`, etc.)
- `NAME` — Set a unique name to identify your user or project
- `RESOURCE_GROUP` — Uses the `NAME` variable by default, change only if you want a different pattern

**Example:**
```bash
LOCATION="West US"
NAME="Alice"
RESOURCE_GROUP="HPC-CC-$NAME"
```

You do not need to change anything else unless you want to further customize resource names or logic.

## Usage
1. Place your `role.json` file in the same directory as the script.
2. You can pass `LOCATION`, `NAME`, and `RESOURCE_GROUP` as parameters, or let the script use the defaults set at the top. You may use either named or positional parameters:
   
   **Named parameters (recommended):**
   ```bash
   ./az-create-cc-role.sh --location "West US" --name "Alice" --resource-group "HPC-CC-Alice"
   ```
   **Positional parameters (legacy):**
   ```bash
   ./az-create-cc-role.sh "West US" "Alice" "HPC-CC-Alice"
   ```
   If you omit parameters, the script uses the default values in the script.
   
   For help, run:
   ```bash
   ./az-create-cc-role.sh --help
   ```
3. Follow the interactive prompts to select your subscription and confirm settings.


## Notes
- **Please deploy your VM using CycleCloud Marketplace templates first:**
   https://ms.portal.azure.com/#create/azurecyclecloud.azure-cyclecloudcyclecloud8
- For official Microsoft documentation on creating a custom role and managed identity for CycleCloud, see: [Create a custom role and managed identity for CycleCloud](https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/managed-identities?view=cyclecloud-8)
- For VM deployment, see [CycleCloud ARM templates](https://github.com/CycleCloudCommunity/cyclecloud_arm).

## License
GPL License
