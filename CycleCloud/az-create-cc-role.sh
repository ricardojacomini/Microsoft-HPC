
#!/bin/bash

echo "Deployment required CycleCloud and Storage Account"

# Change to the directory where this script is located
cd "$(dirname "$0")" || { echo "ERROR: Failed to change directory to script location."; exit 1; }

unset NAME

# Allow LOCATION, NAME, RESOURCE_GROUP as named or positional parameters
DEFAULT_LOCATION="canadacentral" # West US
DEFAULT_NAME="Jacomini"    # Set Name to identify your User here
DEFAULT_RESOURCE_GROUP="HPC-CC-$DEFAULT_LOCATION-$DEFAULT_NAME"  # Set RESOURCE GROUP name here

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
RESOURCE_GROUP="${RESOURCE_GROUP:-${POSITIONAL[2]:-$DEFAULT_RESOURCE_GROUP}}"

# Normalize and validate storage account name (must be 3-24 lowercase letters/numbers)
MAXLEN=24
STORAGE_ACCOUNT="stacct${NAME,,}$(date +%d%m%Y)"

# Trim to maximum allowed length
STORAGE_ACCOUNT=$(echo "$STORAGE_ACCOUNT" | cut -c1-$MAXLEN)
# Ensure at least 3 characters; fallback to a safe generated name if needed
if [ ${#STORAGE_ACCOUNT} -lt 3 ]; then
  STORAGE_ACCOUNT="stac$(date +%s | tr -dc '0-9' | tail -c 6)"
fi

DNS_ZONE="privatelink.blob.core.windows.net"
DNS_LINK_NAME="${VNET_NAME:-virtualNetworks}-dns-link"

# No need to change after this point
ID="identity$NAME"
VM_NAME="ccVM-$NAME"  # Set your VM name here

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

ROLE="CycleCloud $SBC_NAME $NAME"        
ROLE=$(echo "$ROLE" | sed 's/&/and/g')   #  to avoid Invalid

# Print configuration and ask for confirmation
echo -e "\nConfiguration to be used:\n"
echo "  Tenant ID:             $CURRENT_TENANT_ID"
echo "  Subscription Name:     $SBC_NAME"
echo "  Subscription ID:       $SBC"
echo "  Resource Group:        $RESOURCE_GROUP"
echo "  Location:              $LOCATION"
echo "  VM Name:               $VM_NAME"
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

# Check for required tools
if ! command -v az &> /dev/null; then
  echo "ERROR: Azure CLI (az) is not installed. Exiting."
  rm -f "$TMPFILE"
  exit 1
fi
if ! command -v jq &> /dev/null; then
  echo "ERROR: jq is not installed. Exiting."
  rm -f "$TMPFILE"
  exit 1
fi

# Validate role.json existence
if [ ! -f "role.json" ]; then
  echo "ERROR: role.json file not found in current directory. Exiting."
  rm -f "$TMPFILE"
  exit 1
fi

# Ensure temp file is cleaned up on exit
trap 'rm -f "$TMPFILE"' EXIT

sed "s|/subscriptions/\$SBC|/subscriptions/$SBC|g; s|\$ROLE|$ROLE|g" "role.json" > "$TMPFILE"

# Create a custom role definition robustly
ROLE_EXISTS=$(az role definition list --custom-role-only true | jq -e ".[] | select(.roleName==\"$ROLE\")")
if [ $? -eq 0 ]; then
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

if ! az vm show --name "$VM_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
    echo -e "\nERROR: VM '$VM_NAME' does not exist in resource group '$RESOURCE_GROUP'."
    echo "Please deploy your VM using CycleCloud ARM templates first:"
    echo "https://github.com/CycleCloudCommunity/cyclecloud_arm"
    echo "" 
    echo "Please deploy your VM using CycleCloud Marketplace templates first:"
    echo "https://ms.portal.azure.com/#create/azurecyclecloud.azure-cyclecloudcyclecloud8"
    exit 1
fi

# Check if managed identity exists
if az identity show --name "$ID" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
    echo "Managed identity '$ID' already exists in resource group '$RESOURCE_GROUP'. Skipping creation."
    exit 1
fi

az identity create --name "$ID" --resource-group "$RESOURCE_GROUP"
sleep 30

# Assign the managed identity to the VM
az vm identity assign \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --identities "$ID"

# Retrieve its Object ID
IDENTITY_ID=$(az identity show \
  --name $ID \
  --resource-group $RESOURCE_GROUP \
  --query 'principalId' \
  --output tsv)

# Assign the custom role to the identity with proper scope
az role assignment create \
  --role "$ROLE" \
  --assignee-object-id $IDENTITY_ID \
  --assignee-principal-type ServicePrincipal \
  --scope /subscriptions/$SBC

# Get the Network Interface ID of the VM
NIC_ID=$(az vm show \
  --name "$VM_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "networkProfile.networkInterfaces[0].id" \
  --output tsv)

# Get the Subnet and VNet Name from the NIC
SUBNET_ID=$(az network nic show \
  --ids "$NIC_ID" \
  --query "ipConfigurations[0].subnet.id" \
  --output tsv)

# extract the VNet and subnet names from the subnet ID:
VNET_NAME=$(echo "$SUBNET_ID" | awk -F'/' '{print $(NF-2)}')
SUBNET_NAME=$(echo "$SUBNET_ID" | awk -F'/' '{print $NF}')

# Debug output and error handling for VNET_NAME and SUBNET_NAME
echo "Extracted VNET_NAME: $VNET_NAME"
echo "Extracted SUBNET_NAME: $SUBNET_NAME"

if [[ -z "$VNET_NAME" || "$VNET_NAME" == "virtualNetworks" ]]; then
  echo "ERROR: Could not extract a valid VNET_NAME from the subnet ID. Please check your VM and NIC configuration."
  exit 1
fi
if [[ -z "$SUBNET_NAME" ]]; then
  echo "ERROR: Could not extract a valid SUBNET_NAME from the subnet ID. Please check your VM and NIC configuration."
  exit 1
fi

# Check if resource group exists
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
# Create storage account

az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-shared-key-access true

# Get storage account resource ID
STORAGE_ID=$(az storage account show \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query id \
  --output tsv)

# Assign custom role to managed identity on storage account
az role assignment create \
  --role "$ROLE" \
  --assignee-object-id "$IDENTITY_ID" \
  --assignee-principal-type ServicePrincipal \
  --scope "$STORAGE_ID"

PE_NAME="pe-$STORAGE_ACCOUNT"

STORAGE_ID=$(az storage account show \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query id \
  --output tsv)

# Use These Variables to Create the Private Endpoint
az network private-endpoint create \
  --name "$PE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --subnet "$SUBNET_NAME" \
  --private-connection-resource-id "$STORAGE_ID" \
  --group-id "blob" \
  --connection-name "${PE_NAME}-conn"

DNS_ZONE="privatelink.blob.core.windows.net"
az network private-dns zone create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DNS_ZONE"

az network private-dns link vnet create \
  --resource-group "$RESOURCE_GROUP" \
  --zone-name "$DNS_ZONE" \
  --name "${VNET_NAME}-dns-link" \
  --virtual-network "$VNET_NAME" \
  --registration-enabled false

az network private-endpoint dns-zone-group create \
  --resource-group "$RESOURCE_GROUP" \
  --endpoint-name "$PE_NAME" \
  --name "default" \
  --private-dns-zone "$DNS_ZONE" \
  --zone-name "$DNS_ZONE"

# blocks public access; only traffic via the private endpoint is allowed
az storage account update \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --default-action Deny

# Remove the temp file
rm "$TMPFILE"