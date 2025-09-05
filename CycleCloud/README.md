# CycleCloud Custom Role and Identity Script

This repository contains a Bash script to automate the creation of a custom Azure role, managed identity, and related resources for Microsoft CycleCloud deployments.

## Features
- Interactive Azure subscription selection (with current subscription highlighted in cyan)
- Custom role creation from a `role.json` template
- Managed identity creation and assignment of custom role
- Storage account and private endpoint provisioning
- Resource group and VM validation

## Prerequisites
- Azure CLI (`az`)
- `jq` (for JSON parsing)
- Sufficient Azure permissions to create roles, identities, and resources


## Quick Setup: What to Change
At the top of `az-create-cc-role.sh`, you only need to edit these variables:

- `LOCATION` — Set your Azure region (e.g., `"East US"`, `"West US"`, etc.)
- `NAME` — Set a unique name to identify your user or project
- `RESOURCE_GROUP` — Uses the `NAME` variable by default, change only if you want a different pattern
- `ROLE` — Uses the `NAME` variable by default, change only if you want a different custom role name

**Example:**
```bash
LOCATION="West US"
NAME="Alice"
RESOURCE_GROUP="HPC-CC-$NAME"
ROLE="Shared $NAME"
```

You do not need to change anything else unless you want to further customize resource names or logic.

## Usage
1. Place your `role.json` file in the same directory as the script.
2. Edit the script to set your resource group, location, and VM name as needed (see above).
3. Run the script:
   ```bash
   ./az-create-cc-role.sh
   ```
4. Follow the interactive prompts to select your subscription and confirm settings.

## Notes
- The script will highlight the current Azure subscription in cyan when listing available subscriptions.
- If the required tools or files are missing, the script will exit with an error message.
- For VM deployment, see [CycleCloud ARM templates](https://github.com/CycleCloudCommunity/cyclecloud_arm).

## License
GPL License
