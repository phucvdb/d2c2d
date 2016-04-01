﻿<#
.Synopsis 
    This PowerShell script deploys the ProvisionM Microservice
.Description 
    This PowerShell script deploys the ProvisionM Microservice
    You must provide the connection strings from your DocumentDb and Redis Cache instances for this script to function
.Notes 
    File Name  : Deploy-ProvisionM.ps1
    Author     : Bob Familiar
    Requires   : PowerShell V4 or above, PowerShell / ISE Elevated

    Please do not forget to ensure you have the proper local PowerShell Execution Policy set:

        Example:  Set-ExecutionPolicy Unrestricted 

    NEED HELP?

    Get-Help .\Deploy-ProvisionM.ps1 [Null], [-Full], [-Detailed], [-Examples]

.Parameter Repo
    Example:  c:\users\bob\source\repos\looksfamiliar
.Parameter Subscription
    Example:  MySubscription
.Parameter AzureLocation
    Example:  East US
.Parameter Prefix
    Example:  looksfamiliar
.Parameter Suffix
    Example:  test
.Inputs
    The [Repo] parameter is the path to the Git Repo
    The [Subscription] parameter is the name of the client Azure subscription.
    The [AzureLocation] parameter is the name of the Azure Region/Location to host the Virtual Machines for this subscription.
    The [Prefix] parameter is the common prefix that will be used to name resources
    The [Suffix] parameter is one of 'dev', 'test' or 'prod'
.Outputs
    Console
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True, Position=0, HelpMessage="The path to the Git Repo.")]
    [string]$Repo,
    [Parameter(Mandatory=$True, Position=1, HelpMessage="The name of the Azure Subscription.")]
    [string]$Subscription,
    [Parameter(Mandatory=$True, Position=2, HelpMessage="The Resource Group.")]
    [string]$ResourceGroup,
    [Parameter(Mandatory=$True, Position=3, HelpMessage="The name of the Azure Region/Location: East US, Central US, West US.")]
    [string]$AzureLocation,
    [Parameter(Mandatory=$True, Position=4, HelpMessage="The common prefix for resource naming")]
    [string]$Prefix,
    [Parameter(Mandatory=$True, Position=5, HelpMessage="The suffix for resource naming: 'dev, 'test' or 'prod'")]
    [string]$Suffix,
    [switch]$DeployData
)

#######################################################################################
# V A R I A B L E S
#######################################################################################

$includePath = $Repo + "\Automation\Include-ConnectionStrings.ps1"
."$includePath"

# names for app service plans
$ProvisionM_SP = "ProvisionM_SP" 
$ProvisionAPI= $Prefix + "ProvisionAPI" + $Suffix

# document db names
$DocDbName = "Device"
$DocDbCollectionName = "Registry"

##########################################################################################
# F U N C T I O N S
##########################################################################################

Function Select-Subscription()
{
    Param([String] $Subscription)

    Try
    {
        Set-AzureRmContext -SubscriptionName $Subscription
        Write-Verbose -Message "Currently selected Azure subscription is: $Subscription."
    }
    Catch
    {
        Write-Verbose -Message $Error[0].Exception.Message
        Write-Verbose -Message "Exiting due to exception: Subscription Not Selected."
    }
}
##########################################################################################
# M A I N
##########################################################################################

$Error.Clear()

# Mark the start time.
$StartTime = Get-Date

# Select Subscription
Select-Subscription $Subscription 

# Load DocumentDb with the device registry
if ($DeployData)
{
    $connStr = $docdbconnstr + "Database=" + $DocDbName
    $command = $repo + "\Automation\Common\Load-DocDb.ps1"
    &$command -Repo $Repo -Subscription $Subscription -DocDbConnStr $connStr -CollectionName $DocDbCollectionName
}

# Package the APIs
$command = $repo + "\microservices\provision\automation\Package-ProvisionM.ps1"
&$command -repo $Repo

# Deploy the API and update the app settings for documentdb
$command = $repo + "\Automation\Common\Publish-WebSite.ps1"
&$command -Repo $Repo -ResourceGroupName $ResourceGroup -DeploymentName ProvisionAPI -Location $AzureLocation -SiteName $ProvisionAPI -ServicePlan $ProvisionM_SP 

$Properties = @{
    "docdburi" = "$docdburi";
    "docdbkey" = "$docdbkey";
    "apiss" = "$sharedsecret";
    "iothubconnstr" = "$iothubconnstr";
}

# Publish the app settings
$command = $repo + "\Automation\Common\Publish-AppSettings.ps1"
&$command -AzureLocation $AzureLocation -ResourceGroupName $ResourceGroup -SiteName $ProvisionAPI -Settings appsettings -Properties $Properties

# Mark the finish time.
$FinishTime = Get-Date

# Console output
$TotalTime = ($FinishTime - $StartTime).TotalSeconds
Write-Verbose -Message "Elapse Time (Seconds): $TotalTime"