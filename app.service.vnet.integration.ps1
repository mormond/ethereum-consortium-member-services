# Parameter help description
param(
[parameter(Mandatory = $true)]
[String]
$rgName,
[parameter(Mandatory = $true)]
[String]
$appName
)

function ReadHostWithDefault($message, $default)
{
    $result = Read-Host "$message [$default]"
    if($result -eq "")
    {
        $result = $default
    }
        return $result
    }

function PromptCustom($title, $optionValues, $optionDescriptions)
{
    Write-Host $title
    Write-Host
    $a = @()
    for($i = 0; $i -lt $optionValues.Length; $i++){
        Write-Host "$($i+1))" $optionDescriptions[$i]
    }
    Write-Host

    while($true)
    {
        Write-Host "Choose an option: "
        $option = Read-Host
        $option = $option -as [int]

        if($option -ge 1 -and $option -le $optionValues.Length)
        {
            return $optionValues[$option-1]
        }
    }
}

function PromptYesNo($title, $message, $default = 0)
{
    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", ""
    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", ""
    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
    $result = $host.ui.PromptForChoice($title, $message, $options, $default)
    return $result
}

function CreateVnet($resourceGroupName, $vnetName, $vnetAddressSpace, $vnetGatewayAddressSpace, $location)
{
    Write-Host "Creating a new VNET"
    $gatewaySubnet = New-AzureRmVirtualNetworkSubnetConfig -Name "GatewaySubnet" -AddressPrefix $vnetGatewayAddressSpace
    New-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressSpace -Subnet $gatewaySubnet
}

function CreateVnetGateway($resourceGroupName, $vnetName, $vnetIpName, $location, $vnetIpConfigName, $vnetGatewayName, $certificateData, $vnetPointToSiteAddressSpace)
{
    $vnet = Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroupName
    $subnet=Get-AzureRmVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnet

    Write-Host "Creating a public IP address for this VNET"
    $pip = New-AzureRmPublicIpAddress -Name $vnetIpName -ResourceGroupName $resourceGroupName -Location $location -AllocationMethod Dynamic
    $ipconf = New-AzureRmVirtualNetworkGatewayIpConfig -Name $vnetIpConfigName -Subnet $subnet -PublicIpAddress $pip

    Write-Host "Adding a root certificate to this VNET"
    $root = New-AzureRmVpnClientRootCertificate -Name "AppServiceCertificate.cer" -PublicCertData $certificateData

    Write-Host "Creating Azure VNET Gateway. This may take up to an hour."
    New-AzureRmVirtualNetworkGateway -Name $vnetGatewayName -ResourceGroupName $resourceGroupName -Location $location -IpConfigurations $ipconf -GatewayType Vpn -VpnType RouteBased -EnableBgp $false -GatewaySku Basic -VpnClientAddressPool $vnetPointToSiteAddressSpace -VpnClientRootCertificates $root
}

function AddExistingVnet($subscriptionId, $resourceGroupName, $webAppName)
{
    $ErrorActionPreference = "Stop";

    # At this point, the gateway should be able to be joined to an App, but may require some minor tweaking. We will declare to the App now to use this VNET
    Write-Host "Getting App information"
    $webApp = Get-AzureRmResource -ResourceName $webAppName -ResourceType "Microsoft.Web/sites" -ApiVersion 2015-08-01 -ResourceGroupName $resourceGroupName
    $location = $webApp.Location

    $webAppConfig = Get-AzureRmResource -ResourceName "$($webAppName)/web" -ResourceType "Microsoft.Web/sites/config" -ApiVersion 2015-08-01 -ResourceGroupName $resourceGroupName
    $currentVnet = $webAppConfig.Properties.VnetName
    if($currentVnet -ne $null -and $currentVnet -ne "")
    {
        Write-Host "Currently connected to VNET $currentVnet"
    }

    # Display existing vnets
    $vnets = Get-AzureRmVirtualNetwork
    $vnetNames = @()
    foreach($vnet in $vnets)
    {
        $vnetNames += $vnet.Name
    }

    Write-Host
    #$vnet = PromptCustom "Select a VNET to integrate with" $vnets $vnetNames
    $vnet = Get-AzureRmVirtualNetwork -Name "dx-founder-vnet" -ResourceGroupName $resourceGroupName

    # We need to check if this VNET is able to be joined to a App, based on following criteria
        # If there is no gateway, we can create one.
        # If there is a gateway:
            # It must be of type Vpn
            # It must be of VpnType RouteBased
            # If it doesn't have the right certificate, we will need to add it.
            # If it doesn't have a point-to-site range, we will need to add it.

    $gatewaySubnet = $vnet.Subnets | Where-Object { $_.Name -eq "GatewaySubnet" }

    if($gatewaySubnet -eq $null -or $gatewaySubnet.IpConfigurations -eq $null -or $gatewaySubnet.IpConfigurations.Count -eq 0)
    {
        $ErrorActionPreference = "Continue";
        # There is no gateway. We need to create one.
        Write-Host "This Virtual Network has no gateway. I will need to create one."

        $vnetName = $vnet.Name
        $vnetGatewayName="$($vnetName)-gateway"
        $vnetIpName="$($vnetName)-ip"
        $vnetIpConfigName="$($vnetName)-ipconf"

        # Virtual Network settings
        $vnetAddressSpace="10.0.0.0/8"
        $vnetGatewayAddressSpace="10.5.0.0/16"
        $vnetPointToSiteAddressSpace="172.16.0.0/16"

        $vnetGatewayAddressSpace = "10.0.2.0/24"

        $ErrorActionPreference = "Stop";

        Write-Host "Creating App association to VNET"
        $propertiesObject = @{
         "vnetResourceId" = "/subscriptions/$($subscriptionId)/resourceGroups/$($vnet.ResourceGroupName)/providers/Microsoft.Network/virtualNetworks/$($vnetName)"
        }

        $virtualNetwork = New-AzureRmResource -Location $location -Properties $PropertiesObject -ResourceName "$($webAppName)/$($vnet.Name)" -ResourceType "Microsoft.Web/sites/virtualNetworkConnections" -ApiVersion 2015-08-01 -ResourceGroupName $resourceGroupName -Force

        # If there is no gateway subnet, we need to create one.
        if($gatewaySubnet -eq $null)
        {
            $gatewaySubnet = New-AzureRmVirtualNetworkSubnetConfig -Name "GatewaySubnet" -AddressPrefix $vnetGatewayAddressSpace
            $vnet.Subnets.Add($gatewaySubnet);
            Set-AzureRmVirtualNetwork -VirtualNetwork $vnet
        }

        CreateVnetGateway $vnet.ResourceGroupName $vnetName $vnetIpName $location $vnetIpConfigName $vnetGatewayName $virtualNetwork.Properties.CertBlob $vnetPointToSiteAddressSpace

        $gateway = Get-AzureRmVirtualNetworkGateway -ResourceGroupName $vnet.ResourceGroupName -Name $vnetGatewayName
    }
    else
    {
        $uriParts = $gatewaySubnet.IpConfigurations[0].Id.Split('/')
        $gatewayResourceGroup = $uriParts[4]
        $gatewayName = $uriParts[8]

        $gateway = Get-AzureRmVirtualNetworkGateway -ResourceGroupName $vnet.ResourceGroupName -Name $gatewayName

        # validate gateway types, etc.
        if($gateway.GatewayType -ne "Vpn")
        {
            Write-Error "This gateway is not of the Vpn type. It cannot be joined to an App."
            return
        }

        if($gateway.VpnType -ne "RouteBased")
        {
            Write-Error "This gateways Vpn type is not RouteBased. It cannot be joined to an App."
            return
        }

        if($gateway.VpnClientConfiguration -eq $null -or $gateway.VpnClientConfiguration.VpnClientAddressPool -eq $null)
        {
            Write-Host "This gateway does not have a Point-to-site Address Range. Please specify one in CIDR notation, e.g. 10.0.0.0/8"
            $pointToSiteAddress = Read-Host "Point-To-Site Address Space"
            Set-AzureRmVirtualNetworkGatewayVpnClientConfig -VirtualNetworkGateway $gateway.Name -VpnClientAddressPool $pointToSiteAddress
        }

        Write-Host "Creating App association to VNET"
        $propertiesObject = @{
         "vnetResourceId" = "/subscriptions/$($subscriptionId)/resourceGroups/$($vnet.ResourceGroupName)/providers/Microsoft.Network/virtualNetworks/$($vnet.Name)"
        }

        $virtualNetwork = New-AzureRmResource -Location $location -Properties $PropertiesObject -ResourceName "$($webAppName)/$($vnet.Name)" -ResourceType "Microsoft.Web/sites/virtualNetworkConnections" -ApiVersion 2015-08-01 -ResourceGroupName $resourceGroupName -Force

        # We need to check if the certificate here exists in the gateway.
        $certificates = $gateway.VpnClientConfiguration.VpnClientRootCertificates

        $certFound = $false
        foreach($certificate in $certificates)
        {
            if($certificate.PublicCertData -eq $virtualNetwork.Properties.CertBlob)
            {
                $certFound = $true
                break
            }
        }

        if(-not $certFound)
        {
            Write-Host "Adding certificate"
            Add-AzureRmVpnClientRootCertificate -VpnClientRootCertificateName "AppServiceCertificate.cer" -PublicCertData $virtualNetwork.Properties.CertBlob -VirtualNetworkGatewayName $gateway.Name
        }
    }

    # Now finish joining by getting the VPN package and giving it to the App
    Write-Host "Retrieving VPN Package and supplying to App"
    $packageUri = Get-AzureRmVpnClientPackage -ResourceGroupName $vnet.ResourceGroupName -VirtualNetworkGatewayName $gateway.Name -ProcessorArchitecture Amd64

    # Put the VPN client configuration package onto the App
    $PropertiesObject = @{
    "vnetName" = $vnet.Name; "vpnPackageUri" = $packageUri
    }

    New-AzureRmResource -Location $location -Properties $PropertiesObject -ResourceName "$($webAppName)/$($vnet.Name)/primary" -ResourceType "Microsoft.Web/sites/virtualNetworkConnections/gateways" -ApiVersion 2015-08-01 -ResourceGroupName $resourceGroupName -Force

    Write-Host "Finished!"
}

function RemoveVnet($subscriptionId, $resourceGroupName, $webAppName)
{
    $webAppConfig = Get-AzureRmResource -ResourceName "$($webAppName)/web" -ResourceType "Microsoft.Web/sites/config" -ApiVersion 2015-08-01 -ResourceGroupName $resourceGroupName
    $currentVnet = $webAppConfig.Properties.VnetName
    if($currentVnet -ne $null -and $currentVnet -ne "")
    {
        Write-Host "Currently connected to VNET $currentVnet"

        Remove-AzureRmResource -ResourceName "$($webAppName)/$($currentVnet)" -ResourceType "Microsoft.Web/sites/virtualNetworkConnections" -ApiVersion 2015-08-01 -ResourceGroupName $resourceGroupName
    }
        else
    {
        Write-Host "Not connected to a VNET."
    }
}

$resourceGroup = "BC_Founder"
$appName = "bcgateway"
$Context = Get-AzureRmContext
$Subscription = $Context.Subscription
$subscriptionId = $Subscription.SubscriptionId

AddExistingVnet $subscriptionId $rgName $appName

