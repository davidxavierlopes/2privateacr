. ./properties

createACR() {
	# Create ACR Resource Group
	echo "### Creating Resource Group"
	az group create --name $1 --location $LOCATION > /dev/null
	echo "------------------------------------------------------"

	# Create ACR with Public Access for now
	echo "### Creating ACR"
	az acr create --resource-group $1 --name $2 --sku $SKU > /dev/null
	echo "------------------------------------------------------"

	# Create VNet for the private endpoint
	echo "### Creating VNet for Private Endpoint"
	az network vnet create --name $VNET --resource-group $1 --address-prefix $3/16 --subnet-name $SUBNET --subnet-prefix $3/24 > /dev/null
	echo "------------------------------------------------------"
	
	# Disable network policies in subnet
	echo "### Disabling networking policies in the subnet"
	az network vnet subnet update --name $SUBNET --vnet-name $VNET --resource-group $1 --disable-private-endpoint-network-policies > /dev/null
	echo "------------------------------------------------------"

	# Configure private DNS Zone
	echo "### Configuring private DNS Zone"
	az network private-dns zone create --resource-group $1 --name $DNSZONE > /dev/null
	echo "------------------------------------------------------"

	# Create DNS Association Link
	echo "### Creating private DNS Association link"
	az network private-dns link vnet create --resource-group $1 --zone-name $DNSZONE --name $DNSLINK --virtual-network $VNET --registration-enabled false > /dev/null
	echo "------------------------------------------------------"

	# Create private registry endpoint
	echo "### Creating Private Endpoint for Registry"
	local REGISTRY_ID=$(az acr show --name $2 --query 'id' --output tsv)
	az network private-endpoint create --name $PVTEPNAME --resource-group $1 --vnet-name $VNET --subnet $SUBNET --private-connection-resource-id $REGISTRY_ID --group-id registry --connection-name $CONNNAME > /dev/null
	echo "------------------------------------------------------"

	# Get endpoint IP config
	echo "### Getting endpoint IP Configuration"
	local NETWORK_INTERFACE_ID=$(az network private-endpoint show --name $PVTEPNAME --resource-group $1 --query 'networkInterfaces[0].id' --output tsv)
	echo "------------------------------------------------------"

	# Get ACR and data private ip's
	echo "### Getting ACR and data private ip's"
	local REGISTRY_PRIVATE_IP=$(az network nic show --ids $NETWORK_INTERFACE_ID --query "ipConfigurations[?privateLinkConnectionProperties.requiredMemberName=='registry'].privateIpAddress" --output tsv)
	local DATA_ENDPOINT_PRIVATE_IP=$(az network nic show --ids $NETWORK_INTERFACE_ID --query "ipConfigurations[?privateLinkConnectionProperties.requiredMemberName=='registry_data_$LOCATION'].privateIpAddress" --output tsv)
	echo "------------------------------------------------------"

	# An FQDN is associated with each IP address in the IP Configurations
	echo "### Associating FQDN to each IP"
	local REGISTRY_FQDN=$(az network nic show --ids $NETWORK_INTERFACE_ID --query "ipConfigurations[?privateLinkConnectionProperties.requiredMemberName=='registry'].privateLinkConnectionProperties.fqdns" --output tsv)
	local DATA_ENDPOINT_FQDN=$(az network nic show --ids $NETWORK_INTERFACE_ID --query "ipConfigurations[?privateLinkConnectionProperties.requiredMemberName=='registry_data_$LOCATION'].privateLinkConnectionProperties.fqdns" --output tsv)
	echo "------------------------------------------------------"

	# Create empty DNS Records on Private DNS Zone
	echo "### Creating empty DNS Records on the private DNS Zone"
	az network private-dns record-set a create --name $2 --zone-name $DNSZONE --resource-group $1 > /dev/null
	echo "------------------------------------------------------"

	# Specify registry region in data endpoint name
	echo "### Specifying region in data endpoint name"
	az network private-dns record-set a create --name $2.$LOCATION.data --zone-name $DNSZONE --resource-group $1 > /dev/null
	echo "------------------------------------------------------"

	# Create A-Records for the endpoints
	echo "### Creating A-Records for the endpoints"
	az network private-dns record-set a add-record --record-set-name $2 --zone-name $DNSZONE --resource-group $1 --ipv4-address $REGISTRY_PRIVATE_IP > /dev/null
	echo "------------------------------------------------------"

	# Specify registry region in data endpoint name
	echo "### Specifying registry's region in data endpoint name"
	az network private-dns record-set a add-record --record-set-name $2.$LOCATION.data --zone-name $DNSZONE --resource-group $1 --ipv4-address $DATA_ENDPOINT_PRIVATE_IP > /dev/null
	echo "------------------------------------------------------"

	# Disable Public Access
	echo "### Disabling public access to ACR"
	az acr update --name $2 --public-network-enabled false > /dev/null
	echo "------------------------------------------------------"

}

createVM() {
	# Create VM on RG1
	echo "### Creating VM on $1"
	az vm create --resource-group $1 --name $VMNAME --image UbuntuLTS --admin-username azureuser --generate-ssh-keys > /dev/null
	echo "------------------------------------------------------"

	# Install Docker on VM
	echo "### Installing Docker on VM"
	local IP=$(az vm show -d -g $1 -n $VMNAME --query publicIps -o tsv)
	scp installDocker.sh azureuser@$IP:~
	ssh azureuser@$IP 'bash installDocker.sh' > /dev/null
	ssh azureuser@$IP 'curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash' > /dev/null
	echo "------------------------------------------------------"

}

vnetPeering() {
	# Get the id for VNet from RG1
	echo "### Getting the id from the $VNET from $1"
	local VNET1ID=$(az network vnet show --resource-group $1 --name $VNET --query id --out tsv)
	echo "------------------------------------------------------"

	# Get the id for VNet from RG2
	echo "### Getting the id from the $VNET from $2"
	local VNET2ID=$(az network vnet show --resource-group $2 --name $VNET --query id --out tsv)
	echo "------------------------------------------------------"

	# Peering VNets
	echo "### Peering VNets"
	az network vnet peering create --name acr1-2-acr2 --resource-group $1 --vnet-name $VNET --remote-vnet $VNET2ID --allow-vnet-access --allow-gateway-transit > /dev/null
	az network vnet peering create --name acr2-2-acr1 --resource-group $2 --vnet-name $VNET --remote-vnet $VNET1ID --allow-vnet-access --allow-gateway-transit > /dev/null
	echo "------------------------------------------------------"
}

main(){
	createACR $RESOURCEGROUP1 $ACR1NAME $ADDRESSPREFIX1
	createACR $RESOURCEGROUP2 $ACR2NAME $ADDRESSPREFIX2
	createVM $RESOURCEGROUP1
	vnetPeering $RESOURCEGROUP1 $RESOURCEGROUP2

}

main
