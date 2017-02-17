#
# Deploy the app service components in the member node and SQL, Vnet integration etc
#

# Parameters
# rgName - The resource group into which to deploy
# sqlAdminLogin
# sqlAdminPassword
# databaseName
# hostingPlanName
# skuName
Param(
    [Parameter(Mandatory=$True)]
    [string]$rgName,
    [Parameter(Mandatory=$True)]   
    [string]$sqlAdminLogin,
    [Parameter(Mandatory=$True)]
    [string]$databaseName,
    [Parameter(Mandatory=$True)]
    [securestring]$sqlAdminPassword,
    [Parameter(Mandatory=$True)]
    [string]$hostingPlanName,
    [Parameter(Mandatory=$True)]
    [string]$skuName
)

#
# Add the App Service components (web site + SQL Server)
#
#

$webOutputs = New-AzureRmResourceGroupDeployment -TemplateFile ".\template.web.components.json" `
  -ResourceGroupName $rgName `
  -hostingPlanName $hostingPlanName `
  -skuName $skuName `
  -administratorLogin $sqlAdminLogin `
  -administratorLoginPassword $sqlAdminPassword `
  -databaseName $databaseName 

return $webOutputs
