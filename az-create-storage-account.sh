#!/bin/bash

# Purpose: create a reusable storage + networking + managed identity to support CycleCloud/Lustre/AKS workloads.
#
# Main actions (in order):
# 1) Parse parameters: --location, --name, --resource-group (positional allowed).
# 2) Ensure Azure login and subscription context.
# 3) Generate/ensure a custom role from local role.json (creates it if missing).
# 4) Ensure a user-assigned managed identity exists (create if missing) and read its principalId.
# 5) Create the resource group if absent.
# 6) Create a VNet named vnet-<name> with three subnets:
#      - default: 10.0.0.0/24
#      - lustre: 10.1.0.0/22
#      - aks:   10.2.0.0/22
#    plus a dedicated private-endpoint subnet priv-endpoint: 10.0.255.0/27
# 7) Normalize and create a storage account (3–24 lowercase alphanumeric).
# 8) Assign the custom role to the managed identity scoped to the storage account.
# 9) Create a Private Endpoint for the storage account in the PE subnet and wire up:
#      - private DNS zone privatelink.blob.core.windows.net
#      - private DNS link between that zone and the VNet (uses VNet resource id)
#      - DNS zone group on the private endpoint
# 10) Lock down storage account network access (default-action: Deny).
# 11) Print/inspect private endpoint connections for verification.
#
# Usage examples:
#   bash az-create-storage-account.sh --name alice --location "eastus" --resource-group rg-alice
#   bash az-create-storage-account.sh eastus alice rg-alice
#
# Notes/Prereqs:
# - Run with Bash (not sh). Requires Azure CLI signed in (az login) and role.json file in the script directory.
# - This script is idempotent for most operations and applies standard tags to created resources.
#
# End of header

# Change to the directory where this script is located
cd "$(dirname "$0")" || { echo "ERROR: Failed to change directory to script location."; exit 1; }

unset NAME

# Fail fast and safe defaults
set -euo pipefail
IFS=$'\n\t'

# Standard tags for all created resources
CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Allow LOCATION, NAME, RESOURCE_GROUP as named or positional parameters
DEFAULT_LOCATION="East US" # West US
DEFAULT_NAME="Jacomini"    # Set Name to identify your User here
DEFAULT_RESOURCE_GROUP="HPC-AI-$DEFAULT_NAME"  # Set RESOURCE GROUP name here

# Parse named parameters (e.g., --location "West US" --name "Alice" --resource-group "HPC-CC-Alice")

REMOVE_MODE=0
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --location)
      LOCATION="$2"; shift 2;;
    --name)
      NAME="$2"; shift 2;;
    --resource-group)
      RESOURCE_GROUP="$2"; shift 2;;
    --remove)
      REMOVE_MODE=1; shift;;
    --help|-h)
      echo "Usage: $0 [--location <LOCATION>] [--name <NAME>] [--resource-group <RESOURCE_GROUP>] [--remove]"
      echo "   or: $0 <LOCATION> <NAME> <RESOURCE_GROUP> [--remove]"
      echo "   --remove: Remove storage account, managed identity and associated private DNS resources."
      exit 0;;
    *)
      POSITIONAL+=("$1"); shift;;
  esac
done

# Fallback to positional if not set by named

LOCATION="${LOCATION:-${POSITIONAL[0]:-$DEFAULT_LOCATION}}"
NAME="${NAME:-${POSITIONAL[1]:-$DEFAULT_NAME}}"
RESOURCE_GROUP="${RESOURCE_GROUP:-${POSITIONAL[2]:-HPC-CC-$NAME}}"

# Standard tags for all created resources (requires NAME to be set)
COMMON_TAGS=("owner=${NAME}" "purpose=HPC-AI-storage-network-identity" "createdBy=az-create-storage-account" "createdAt=${CREATED_AT}")

# Ensure a VNet name is defined (used later for DNS link creation and VNet creation)
VNET_NAME="${VNET_NAME:-vnet-$NAME}"

# Normalize and validate storage account name (must be 3-24 lowercase letters/numbers)
RAW_NAME=$(echo "${NAME:-$DEFAULT_NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
BASE_PREFIX="storageaccount"
MAXLEN=24
STORAGE_ACCOUNT="${BASE_PREFIX}${RAW_NAME}"
# Trim to maximum allowed length
STORAGE_ACCOUNT=$(echo "$STORAGE_ACCOUNT" | cut -c1-$MAXLEN)
# Ensure at least 3 characters; fallback to a safe generated name if needed
if [ ${#STORAGE_ACCOUNT} -lt 3 ]; then
  STORAGE_ACCOUNT="stac$(date +%s | tr -dc '0-9' | tail -c 6)"
fi
DNS_ZONE="privatelink.blob.core.windows.net"
DNS_LINK_NAME="${VNET_NAME}-dns-link"

# No need to change after this point
ID="identity$NAME"

# Function to remove storage account, DNS resources, and managed identity
remove_resources() {
  # Get current subscription info
  CURR_SUB_NAME=$(az account show --query name -o tsv)
  CURR_SUB_ID=$(az account show --query id -o tsv)
  echo -e "\nYou are about to REMOVE resources in subscription: $CURR_SUB_NAME ($CURR_SUB_ID) \n"
  echo "  Resource Group: $RESOURCE_GROUP"
  echo "  Storage Account: $STORAGE_ACCOUNT"
  echo "  Managed Identity: $ID"
  echo "  Private DNS Zone: $DNS_ZONE"
  echo "  Private DNS Link: $DNS_LINK_NAME"
  read -p "Are you sure you want to proceed? (Y/N): " CONFIRM_REMOVE
  if [[ ! $CONFIRM_REMOVE =~ ^[Yy]$ ]]; then
    echo "Aborted by user. No resources were deleted."
    exit 1
  fi
  echo "Removing storage account: $STORAGE_ACCOUNT from resource group: $RESOURCE_GROUP"
  az storage account delete --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --yes
  echo "Removing private DNS link: $DNS_LINK_NAME from DNS zone: $DNS_ZONE"
  az network private-dns link vnet delete --resource-group "$RESOURCE_GROUP" --zone-name "$DNS_ZONE" --name "$DNS_LINK_NAME"
  echo "Removing private DNS zone: $DNS_ZONE from resource group: $RESOURCE_GROUP"
  az network private-dns zone delete --resource-group "$RESOURCE_GROUP" --name "$DNS_ZONE"
  echo "Removing managed identity: $ID from resource group: $RESOURCE_GROUP"
  az identity delete --name "$ID" --resource-group "$RESOURCE_GROUP"
  echo "Done."
  exit 0
}

if [[ $REMOVE_MODE -eq 1 ]]; then
  remove_resources
fi

# Ask user to login to Azure if not already logged in
if ! az account show &> /dev/null; then
  echo "You are not logged in to Azure. Please login."
  az login || { echo "ERROR: Azure login failed."; exit 1; }
fi

# Select or confirm subscription interactively
CURRENT_SBC=$(az account show --query id -o tsv)
CURRENT_SBC_NAME=$(az account show --query name -o tsv)
CURRENT_TENANT_ID=$(az account show --query tenantId -o tsv)

echo "Current subscription: $CURRENT_SBC_NAME ($CURRENT_SBC)"
while true; do
  read -p "Enter the Subscription ID to use [Press Enter to keep current, S to show all]: " SBC

  if [ -z "$SBC" ]; then
    SBC="$CURRENT_SBC"
    SBC_NAME="$CURRENT_SBC_NAME"

    echo -e "\nUsing current subscription: $CURRENT_SBC_NAME ($CURRENT_SBC)"
    break
  elif [[ "$SBC" =~ ^[Ss]$ ]]; then
    echo "Available subscriptions:"

    # List all subscriptions and display with index
    mapfile -t subs < <(az account list --query "[].{name:name, id:id}" -o tsv)
    for i in "${!subs[@]}"; do
      name="${subs[$i]%$'\t'*}"
      id="${subs[$i]##*$'\t'}"
      if [[ "$id" == "$CURRENT_SBC" ]]; then
      # Print current subscription in cyan
        printf "\033[36m%-3s: %-55s %s\033[0m\n" "$i" "$name" "($id)"
      else
        printf "%-3s: %-55s %s\n" "$i" "$name" "($id)"
      fi
    done

    # Prompt user to select
    read -p "Enter the number of the subscription you want to use: " choice

    # Set context to selected subscription
    selected_id="${subs[$choice]##*$'\t'}"

    if [ -n "$selected_id" ]; then
      SBC="$selected_id"
      SBC_NAME="${subs[$choice]%$'\t'*}"

      echo -e "\nSetting Subscription Name: $SBC_NAME  ID: $SBC"
      break
    fi
  fi
done

ROLE="$NAME $SBC_NAME"        
ROLE=$(echo "$ROLE" | sed 's/&/and/g')   #  to avoid Invalid

# Print configuration and ask for confirmation
echo -e "\nConfiguration to be used:\n"
echo "  Tenant ID:             $CURRENT_TENANT_ID"
echo "  Subscription Name:     $SBC_NAME"
echo "  Subscription ID:       $SBC"
echo "  Resource Group:        $RESOURCE_GROUP"
echo "  Location:              $LOCATION"
echo "  NAME:                  $NAME"
echo "  Managed Identity ID:   $ID"
echo "  Role Name:             $ROLE"
echo
read -p "Continue with these settings? (Y/N): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
  echo "Aborted by user."
  exit 1
else
  az account set --subscription "$SBC" || echo "ERROR: Failed to set subscription. Try again or enter S to show all."
fi

#  replaces every & in your variable with \&, so sed treats it as a literal character.
JSON=role.json

# Create a temp file
TMPFILE=$(mktemp)

# Check for required tools (only az is mandatory now)
if ! command -v az &> /dev/null; then
  echo "ERROR: Azure CLI (az) is not installed. Exiting."
  rm -f "$TMPFILE"
  exit 1
fi
# jq is optional; role detection uses az query to avoid jq dependency

# Validate role.json existence
if [ ! -f "role.json" ]; then
  echo "ERROR: role.json file not found in current directory. Exiting."
  rm -f "$TMPFILE"
  exit 1
fi

# Ensure temp file is cleaned up on exit
trap 'rm -f "$TMPFILE"' EXIT

sed "s|/subscriptions/\$SBC|/subscriptions/$SBC|g; s|\$ROLE|$ROLE|g; s|\$NAME|$NAME|g" "role.json" > "$TMPFILE"

# Create a custom role definition robustly
# Replace jq-dependent existence check with an `az` query
ROLE_EXISTS=$(az role definition list --custom-role-only true --query "[?roleName=='$ROLE'] | [0].roleName" -o tsv 2>/dev/null || true)
if [ -n "$ROLE_EXISTS" ]; then
  echo "Role '$ROLE' already exists. Skipping creation."
  echo -e "\nTo remove it go to Azure portal: In subscription $(az account show --query name -o tsv) \n Go to Access control (IAM) -> Roles search for $ROLE"
  echo "Then, remove it"
else
  echo "Creating custom role '$ROLE'..."
  if az role definition create --role-definition "$TMPFILE"; then
    echo "Custom role '$ROLE' created successfully."
  else
    echo -e "ERROR: Failed to create custom role '$ROLE'. Exiting. \n"
    rm "$TMPFILE"
    exit 1
  fi
fi

# Remove the strict VM existence requirement - this script will create storage, VNet and managed identity for later use

# Ensure the resource group exists before creating the managed identity
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
  echo "Resource group '$RESOURCE_GROUP' not found. Creating it in location '$LOCATION'..."
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --tags "${COMMON_TAGS[@]}" || { echo "ERROR: Failed to create resource group $RESOURCE_GROUP"; exit 1; }
else
  echo "Resource group '$RESOURCE_GROUP' already exists."
fi

# Ensure managed identity exists (create if missing) but do NOT assign it to a VM here
if az identity show --name "$ID" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
  echo "Managed identity '$ID' already exists in resource group '$RESOURCE_GROUP'."
else
  echo "Creating managed identity '$ID' in resource group '$RESOURCE_GROUP'..."
  az identity create --name "$ID" --resource-group "$RESOURCE_GROUP" --tags "${COMMON_TAGS[@]}" || { echo "ERROR: Failed to create managed identity $ID"; exit 1; }
  # Poll for the principalId to become available instead of a fixed sleep
  i=0
  until IDENTITY_ID=$(az identity show --name "$ID" --resource-group "$RESOURCE_GROUP" --query 'principalId' -o tsv 2>/dev/null) && [[ -n "$IDENTITY_ID" && "$IDENTITY_ID" != "null" ]]; do
    i=$((i+1))
    if [ $i -ge 12 ]; then
      echo "ERROR: Timed out waiting for managed identity principalId."; exit 1;
    fi
    echo "Waiting for managed identity to be provisioned... (attempt: $i)"
    sleep 5
  done
  echo "Managed identity principalId: $IDENTITY_ID"
fi

# Retrieve its Object ID (ensures IDENTITY_ID is set whether pre-existing or newly created)
IDENTITY_ID=$(az identity show \
  --name "$ID" \
  --resource-group "$RESOURCE_GROUP" \
  --query 'principalId' \
  --output tsv)

# NOTE: subscription-level role assignment removed; we will only assign least-privilege role to the storage account below

# Check if resource group exists (idempotent)
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --tags "${COMMON_TAGS[@]}" || { echo "ERROR: Failed to create resource group $RESOURCE_GROUP"; exit 1; }
else
  echo "Resource group '$RESOURCE_GROUP' already exists."
fi

# Create VNet and subnets for later AKS and Lustre usage
echo "Creating VNet '$VNET_NAME' with address space 10.0.0.0/16 and subnets: default(10.0.0.0/24), lustre(10.1.0.0/22), aks(10.2.0.0/22)"
az network vnet create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VNET_NAME" \
  --location "$LOCATION" \
  --address-prefixes 10.0.0.0/16 \
  --subnet-name default --subnet-prefix 10.0.0.0/24 \
  --tags "${COMMON_TAGS[@]}" || { echo "ERROR: VNet create failed"; exit 1; }

# Create additional subnets (idempotent)
if ! az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name lustre &> /dev/null; then
  az network vnet subnet create \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name lustre \
    --address-prefixes 10.0.4.0/22 || { echo "ERROR: Failed to create subnet 'lustre'"; exit 1; }
else
  echo "Subnet 'lustre' already exists."
fi

if ! az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name aks &> /dev/null; then
  az network vnet subnet create \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name aks \
    --address-prefixes 10.0.8.0/22 || { echo "ERROR: Failed to create subnet 'aks'"; exit 1; }
else
  echo "Subnet 'aks' already exists."
fi

# Create a dedicated subnet for private endpoints (recommended)
PE_SUBNET_NAME="priv-endpoint"
PE_SUBNET_PREFIX="10.0.255.0/27"
if ! az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$PE_SUBNET_NAME" &> /dev/null; then
  az network vnet subnet create \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$PE_SUBNET_NAME" \
    --address-prefixes "$PE_SUBNET_PREFIX" || { echo "ERROR: Failed to create subnet '$PE_SUBNET_NAME'"; exit 1; }
else
  echo "Subnet '$PE_SUBNET_NAME' already exists."
fi

# Refresh VNET_ID for DNS link operations
VNET_ID=$(az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" --query id -o tsv)
if [ -z "$VNET_ID" ]; then
  echo "ERROR: Unable to determine VNet ID for $VNET_NAME"; exit 1;
fi

# Create storage account
# STORAGE_ACCOUNT variable already normalized at top
az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-shared-key-access true \
  --tags "${COMMON_TAGS[@]}" || { echo "ERROR: Failed to create storage account $STORAGE_ACCOUNT"; exit 1; }

# Get storage account resource ID
STORAGE_ID=$(az storage account show \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query id \
  --output tsv)

# Assign custom role to managed identity on storage account (least privilege for storage operations)
# Retry role assignment a few times to account for propagation delays
attempt=0
until az role assignment create \
  --role "$ROLE" \
  --assignee-object-id "$IDENTITY_ID" \
  --assignee-principal-type ServicePrincipal \
  --scope "$STORAGE_ID" &> /dev/null; do
  attempt=$((attempt+1))
  if [ $attempt -ge 5 ]; then
    echo "ERROR: Failed to create role assignment after multiple attempts"; exit 1;
  fi
  echo "Role assignment failed, retrying (attempt: $attempt)..."
  sleep $((attempt * 3))
done

PE_NAME="pe-$STORAGE_ACCOUNT"

# Create Private Endpoint for the storage account and wire up Private DNS (use dedicated PE subnet)
echo "Creating Private Endpoint '$PE_NAME' for storage account '$STORAGE_ACCOUNT' in VNet '$VNET_NAME' (subnet: $PE_SUBNET_NAME)..."
if az network private-endpoint show --name "$PE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
  echo "Private Endpoint '$PE_NAME' already exists. Skipping creation."
else
  az network private-endpoint create \
    --name "$PE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --subnet "$PE_SUBNET_NAME" \
    --private-connection-resource-id "$STORAGE_ID" \
    --group-id "blob" \
    --connection-name "${PE_NAME}-conn" || { echo "ERROR: Failed to create private endpoint"; exit 1; }
fi

# Create Private DNS zone and link to the VNet (idempotent)
if az network private-dns zone show --name "$DNS_ZONE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
  echo "Private DNS zone '$DNS_ZONE' already exists."
else
  az network private-dns zone create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DNS_ZONE" || { echo "ERROR: Failed to create private DNS zone $DNS_ZONE"; exit 1; }
fi

# Create DNS link (idempotent) using VNet ID
if az network private-dns link vnet show --resource-group "$RESOURCE_GROUP" --zone-name "$DNS_ZONE" --name "$DNS_LINK_NAME" &> /dev/null; then
  echo "Private DNS link '$DNS_LINK_NAME' already exists."
else
  az network private-dns link vnet create \
    --resource-group "$RESOURCE_GROUP" \
    --zone-name "$DNS_ZONE" \
    --name "$DNS_LINK_NAME" \
    --virtual-network "$VNET_ID" \
    --registration-enabled false || { echo "ERROR: Failed to create private DNS link"; exit 1; }
fi

# Create DNS zone group for the private endpoint (idempotent)
if az network private-endpoint dns-zone-group show --resource-group "$RESOURCE_GROUP" --endpoint-name "$PE_NAME" --name default &> /dev/null; then
  echo "DNS zone group for endpoint '$PE_NAME' already exists."
else
  az network private-endpoint dns-zone-group create \
    --resource-group "$RESOURCE_GROUP" \
    --endpoint-name "$PE_NAME" \
    --name "default" \
    --private-dns-zone "$DNS_ZONE" \
    --zone-name "$DNS_ZONE" || { echo "ERROR: Failed to create dns zone group"; exit 1; }
fi

# Restrict public access to the storage account (allow only via private endpoint)
echo "Updating storage account '$STORAGE_ACCOUNT' to block public access (default-action: Deny)."
az storage account update \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --default-action Deny || { echo "ERROR: Failed to update storage account network rules"; exit 1; }

# Show resulting private endpoint connections for the storage account
echo "Private endpoint connections for storage account:$STORAGE_ACCOUNT"
az network private-endpoint-connection list --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --type Microsoft.Storage/storageAccounts -o table || true
