<#
.SYNOPSIS
  This script is used to prepare, configure, and onboard Azure subscriptions in the Prisma cloud security tool. 
.DESCRIPTION
  The script's main function [Set-AzPrismaConfig] accepts a single Azure Subscription ID and completes the required Prisma prerequisite
  infrastructure configurations (refer to the link below) as well as creates an Azure Application and Service Principal for the Prisma app.
  The last section of the function will POST the Azure Application and Service Principal properties to the Prisma Cloud via HTTPS POST using
  the functions provided in the Prisma.WebAPI.ps1 module. 
.INPUTS
  None
.OUTPUTS
  Log File
  .\LOG\PrismaAzConfigLog.csv
.EXAMPLE
  .\Set-PrismaAzConfig.ps1 
.LINK
Azure PowerShell AzModule - https://docs.microsoft.com/en-us/powershell/azure/new-azureps-module-az?view=azps-3.1.0
PowerShell Core 6.x - https://docs.microsoft.com/en-us/powershell/scripting/overview?view=powershell-6
Prisma Cloud Account Requirements - https://docs.paloaltonetworks.com/prisma/prisma-cloud/prisma-cloud-admin/connect-your-cloud-platform-to-prisma-cloud/onboard-your-azure-account/azure-onboarding-checklist.html
#>
#---------------------------------------------------------[Initializations]--------------------------------------------------------
Import-Module $PSScriptRoot/Modules/Prisma.WebAPI/Prisma.WebAPI.psm1
Import-Module $PSScriptRoot/Modules/Sn.NewKey/Sn.NewKey.psm1
#----------------------------------------------------------[Declarations]----------------------------------------------------------
#-----------------------------------------------------------[Functions]------------------------------------------------------------
function Write-Log {
    <#
  .SYNOPSIS
    Logger function used for tracking script progress and errors.  
  .DESCRIPTION
    This function is used throughout the script to log each activity and capture any errors. 
    Output of the function is displayed in the shell console when the script runs in addition
    to be the \LOG\PrismaAzConfigLog.csv log file.  
  .PARAMETER message
    Message to log describing the success, failures, or warning information. Will include the error variable output
    terminating errors.  
  .PARAMETER severity
    Classification of the message, information (success), warning (pending task), error (terminating script error, unable to
    complete task)
  .PARAMETER subscription
    The current Azure Subscription ID the script is configuring. 
  .OUTPUTS
    Log entries written to console as well as .\LOG\PrismaAConfigLog.csv
  .EXAMPLE
    Write-Log -Severity "Information" -Subscription $subID -Message "Successfully created storage account"
  .NOTES
    None
    #>
    [CmdletBinding()]
    param(
        [parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$Message,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Information','Warning','Error')]
        [string]$Severity = 'Information',

        [parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Subscription
    )
    Begin {
        #Create custom log entry object
        $logentry = [pscustomobject]@{
            Time = (Get-Date -f g)
            Subscription = $Subscription
            Severity = $Severity
            Message = $Message
        }
        $logfolder = Get-ChildItem "$PSScriptRoot\LOG\" -ErrorAction SilentlyContinue
        if(!$logfolder) {
            $logfolder = New-Item "$PSScriptRoot\LOG\" -ItemType "Directory" -ErrorAction SilentlyContinue
        } 
    }
    Process {
        #Change foreground color based on log classification - for console output.
        switch ($Severity){
            Information {
                $foregroundcolor = "Green"; break
            }
            Warning {
                $foregroundcolor = "Yellow"; break
            }
            Error {
                $foregroundcolor = "Red"; break
            }
        }
    }
    End {
        #$logentry | Out-File ($logfolder.FullName+"\Output.csv") -Append
        Write-Host ($logentry | Out-String) -ForegroundColor $foregroundcolor | Format-Table  -AutoSize
    }
}
function Set-PrismaAzConfig {
    <#
  .SYNOPSIS
    Main script function that prepares Azure Subscriptions for Prisma Cloud. 
  .DESCRIPTION
    Configures an Azure Subscription with all of the necessary perquisites for enrollment in the
    Prisma Cloud app. All configurable Az subscriptions will loop through this function. 
  .PARAMETER subscription
    The Azure Subscription ID to be configured for Prisma. 
  .OUTPUTS
    Script status is output to Console and Log via Write-Log function. 
  .EXAMPLE
    .\Set-PrismaAzConfig -Subscription $SubscriptionID
  .NOTES
    None
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,HelpMessage="Accepts Azure Subscription ID string.")]
        [string]$subID,
        [Parameter(Mandatory=$true,HelpMessage="Accepts Azure Subscription name string.")]
        [string]$subname,
        [Parameter(Mandatory=$false,HelpMessage="Prisma group ID as a string.")]
        [string]$groupId
    )
    Begin {
        try {
            Write-Log -Severity "Information" -Subscription $subid -Message "Start"
            #Retrieve Azure Service Principal credentials from Environment Variables and connect
            $appid = $Env:AzProdPrismaSP_USR
            $pass = ConvertTo-SecureString -String $Env:AzPRodPrismaSP_PSW -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential ($appid, $pass)
            Connect-AzAccount -ServicePrincipal -Credential $cred -Tenant $Env:AzProdTenantID
            try {
                #Make the Service Principal an Owner of the target subscription, sleep for 90 seconds for permissions to apply
                $RoleAssignment = New-AzRoleAssignment -ApplicationId $appid -RoleDefinitionName "Owner"  -scope ("/subscriptions/$subid/") -ErrorAction "SilentlyContinue" 
                Write-Log -Severity "Information" -Subscription $subID -Message "Sleeping for 90 seconds to allow Owner permissions to be applied"
                Clear-AzContext -Scope CurrentUser -Force
                Start-Sleep 90
            } catch {
                Write-Log -Severity "Error" -Subscription $subID -Message ("New-AzRoleAssignment: "+$Error[0])
                break
            }    
        } catch {
            Write-Log -Severity "Error" -Subscription $subID -Message ("Connect-AzAccount: "+$Error[0])
            break
        }
        try {
            
            #Reconnect to Azure so the new permissions are applied to the account
            Connect-AzAccount -ServicePrincipal -Credential $cred -Tenant $Env:AzProdTenantID
            $subscription = Set-AzContext $subID -ErrorAction "Stop"
            Write-Log -Severity "Information" -Subscription $subID   -Message "Set Azure context to subscription" 
            $vms = Get-AzVM -ErrorAction "SilentlyContinue"
            if(!$vms){
                #If the subscription does not contain any virtual machines it is skipped. 
                Write-Log -Severity "Information" -Subscription $subID -Message "No Virtual Machines found"
                Continue
            }
        } catch {
            Write-Log  -Severity "Error" -Subscription $subID -Message ("Set-AzContext:"+$Error[0] | Out-String)
            break
        }                
    }
    Process {
        <#----------------------------------------------------
        Setup Network Security Groups (NSG) and prerequisites. 
        ----------------------------------------------------#>
        $insights = (Get-AzResourceProvider -ProviderNamespace 'Microsoft.Insights').RegistrationState | Select-Object -First 1 -ErrorAction "SilentlyContinue"
        if($insights -eq "NotRegistered"){
            Write-Log  -Severity "Warning" -Subscription $subID -Message "Registering Microsoft.Insights Provider"
            try {
                Register-AzResourceProvider -ProviderNamespace Microsoft.Insights -ErrorAction "Stop"
                Write-Log -Severity "Information" -Subscription $subID -Message "Microsoft.Insights Provider registered"
            } catch {
                Write-Log -Severity "Error" -Subscription $subID -Message ("Register-AzResourceProvider:"+$Error[0] | Out-String)
                break
            }   
        } else {
            Write-Log -Severity "Information" -Subscription $subID -Message "Microsoft.Insights Provider already registered"
        }
        #A Prisma Resource Group will be created in West US 2 location for each subscription. Used to store the required resources NSGs, Storage Accounts, etc.        
        $prismarg = Get-AzResourceGroup -Name "prisma-rg" -Location "West US 2" -ErrorAction "SilentlyContinue"
        if(!$prismarg){
            Write-Log -Severity "Warning" -Subscription $subID -Message "Prisma Resource Group not found and will be created"
            try {
                $prismarg = New-AzResourceGroup -Name "prisma-rg" -Location "West US 2" -ErrorAction "Stop"
                Write-Log -Severity "Information" -Subscription $subID -Message "Prisma Resource Group created"

            } catch {
                Write-Log -Severity "Error" -Subscription $subID -Message ("New-AzResourceGroup:"+$Error[0] | Out-String)
                break
            }
        } else {
            Write-Log -Severity "Information" -Subscription $subID -Message "Prisma Resource Group found"
        }
        #NSG Flow Logs must be configured for each virtual machine location. 
        $vm_locations = $vms | Select-Object -ExpandProperty  Location | Sort | Get-Unique
        ForEach($location in $vm_locations){
            Write-Log -Severity "Information" -Subscription $subID -Message "Virtual machines in $location found"
            $netwatcher = Get-AzNetworkWatcher -Name ("NetworkWatcher_"+$location) -ResourceGroupName "NetworkWatcherRG" -ErrorAction "SilentlyContinue"
            if(!$netwatcher){
                Write-Log -Severity "Warning" -Subscription $subID -Message "No Network Watcher instance for $location"
                try {
                    New-AzResourceGroup -Name "NetworkWatcherRG" -Location $location 
                    $netwatcher = New-AzNetworkWatcher -Name ("NetworkWatcher_"+$location) -location $location -ResourceGroupName "NetworkWatcherRG"
                    Write-Log -Severity "Information" -Subscription $subID -Message "Network Watcher instance created for $location"
                } catch {
                    Write-Log -Severity "Error" -Subscription $subID -Message ("New-AzNetworkWatcher:"+$Error[0] | Out-String)
                    break
                }
            } else {
                Write-Log -Severity "Information" -Subscription $subID -Message "Network Watcher instance for $location found"
            }
            #Collect all NSGs in this location, including existing (non-Prisma) NSGs, to enable flow logging for each. 
            $nsgs = Get-AzNetWorkSecurityGroup | Where-Object {$_.Location -eq $location} -ErrorAction "SilentlyContinue"
            ForEach ($nsg in $nsgs){
                $flowlogstatus = Get-AzNetworkWatcherFlowLogStatus -NetworkWatcher $netwatcher -TargetResourceId $nsg.id | Select-Object Enabled -ErrorAction "SilentlyContinue"
                if($flowlogstatus.Enabled -ne $True){
                    Write-Log -Severity "Warning" -Subscription $subID -Message ("NSG Flow Logs not enabled for " + $nsg.Name | Out-String)
                    #Storage account must be created to store NSG flow logs.
                    $saloc = ($location.substring(0,4)).ToLower()
                    $saname = ("pris"+$saloc+$subid.substring(0,3))
                    $storageAccount = Get-AzStorageAccount -ResourceGroupName "prisma-rg" -Name $saname -ErrorAction "SilentlyContinue"
                    if(!$storageAccount){
                        Write-Log -Severity "Warning" -Subscription $subID -Message "Storage Account not created in $location for NSG Flow Logs."
                        try {
                            #Storage Account name must be no more than 24 characters all lowercase. 
                            $storageAccount = New-AzStorageAccount -ResourceGroupName "prisma-rg" -Location $location -Name $saname -SkuName "Standard_GRS"
                            Write-Log -Severity "Information" -Subscription $subID -Message "Storage Account created for $location."
                        } catch {
                            Write-Log -Severity "Error" -Subscription $subID -Message ("New-AzStorageAccount:"+$Error[0])
                            break
                        }
                    } else {
                        Write-Log -Severity "Information" -Subscription $subID -Message "Storage Account found for NSG Flow Logs in $location."
                    }
                    try {
                        Set-AzNetworkWatcherConfigFlowLog -NetworkWatcher $netwatcher -TargetResourceId $nsg.Id -StorageAccountId `
                        $storageAccount.Id -EnableFlowLog $True -FormatType Json -FormatVersion 1 | Out-Null
                        Write-Log -Severity "Information" -Subscription $subID -Message ("Prisma Network Security Group Flow Logs successfully enabled for " + $nsg.Name | Out-String)
                    } catch {
                        Write-Log -Severity "Warning" -Subscription $subID -Message "Set-AzNetworkWatcherConfigFlowLogs:"+$Error[0]
                        break
                    }
                } else {
                    Write-Log -Severity "Information" -Subscription $subID -Message ("Network Security Group Flow Logs already enabled for " + $nsg.Name | Out-String)
                }
            }
        }
        <#-----------------------------------------------------------------------------
        Setup Prisma App & Service Principal in Azure and store the required properties
        ------------------------------------------------------------------------------#>
        #Create a dictionary to store the Prisma Azure App & Service Principal properties. 
        $azPrismaAppParams = @{
            "AppHomePageUrl" = "https://www.redlock.io"
            "AppName" = ("sp-prisma-" + ($subscription.Subscription.Id).Split("-")[0])  #App Name ends with the first 8 characters of the subscription id
            "AppUri" = ("https://saprisma" + ($subscription.Subscription.Id).Split("-")[0])
            "TenantID" = $subscription.Tenant.Id
        }
        $azPrismaApp = Get-AzADApplication -DisplayName $azPrismaAppParams["AppName"] -ErrorAction "SilentlyContinue"
        if(!$azPrismaApp){
            Write-Log -Severity "Warning" -Subscription $subID -Message "No Prisma application found for this subscription"
            try {
                Write-Log -Severity "Information" -Subscription $subID -Message "Creating Prisma application"
                #Set Start and End for credential expiration
                $start = Get-Date
                $end = $start.AddYears(99)
                #Using New-key function imported from Sn.NewKey.ps1
                $key = New-Key A16
                #Store arguments for New-AzAdApplication in a hash for splatting 
                $azPrismaAppFuncArgs = @{
                    DisplayName = $azPrismaAppParams["AppName"]
                    IdentifierUris = $azPrismaAppParams["AppURI"]
                    Homepage = $azPrismaAppParams["AppHomePageUrl"]
                    ReplyUrls = @($azPrismaAppParams["AppUri"], $azPrismaAppParams["AppHomePageUrl"])
                    Password = $key
                    StartDate = $start
                    EndDate = $end
                }
                $azPrismaApp = New-AzADApplication @azPrismaAppFuncArgs
                #Sleep 15 seconds to allow the app to be fully created
                Start-Sleep -s 15
                $AzPrismaSP = New-AzADServicePrincipal -ApplicationId $azPrismaApp.ApplicationId -Role "Reader" -ErrorAction "Stop" 
                #Sleep 1 minute to allow the service principal to be created
                Start-Sleep -s 60
                #Update the existing dictionary with the properties returned after the app and service principal are created 
                $azPrismaAppParams.Add("ServicePrincipal",$AzPrismaSP.Id)
                $azPrismaAppParams.Add("ClientID", $azPrismaApp.ApplicationId)
                $azPrismaAppParams.Add("key", $key)
                Write-Log -Severity "Information" -Subscription $subID -Message "Successfully created Prisma application"
            } catch {
                Write-Log -Severity "Error" -Subscription $subID -Message ("Create New-AzApplication/New-AzAdServicePrincipal: "+ $Error[0] | Out-String)
                break 
            }
        } else {
            Write-Log -Severity "Information" -Subscription $subID -Message ("Found " + $azPrismaApp.DisplayName)
        }
        #Get Azure App Roles applied to newly created Prisma App
        $azPrismaAppRoles = Get-AzRoleAssignment | Where-Object {$_.DisplayName -eq $azPrismaAppParams["AppName"] } | Select-Object RoleDefinitionName -ErrorAction "SilentlyContinue"
        try {
            if($azPrismaAppRoles.RoleDefinitionName -notcontains "Reader and Data Access"){
                Write-Log -Severity "Warning" -Subscription $subID -Message ("Reader and Data Access role not assigned to " + $azPrismaAppParams["AppName"])
                New-AzRoleAssignment -RoleDefinitionName "Reader and Data Access" -ApplicationId $azPrismaApp.ApplicationId -ErrorAction "Stop" | Out-Null
                Write-Log -Severity "Information" -Subscription $subID -Message ("Reader and Data Access role successfully assigned to " + $azPrismaAppParams["AppName"])
            } else {
                Write-Log -Severity "Information" -Subscription $subID -Message ("Reader and Data Access role already assigned to " + $azPrismaAppParams["AppName"])
            }
            
            if($azPrismaAppRoles.RoleDefinitionName -notcontains "Network Contributor"){
                Write-Log -Severity "Warning" -Subscription $subID -Message ("Network Contributor role not assigned to " + $azPrismaAppParams["AppName"])
                New-AzRoleAssignment -RoleDefinitionName "Network Contributor" -ApplicationId $azPrismaApp.ApplicationId -ErrorAction "Stop" | Out-Null
                Write-Log -Severity "Information" -Subscription $subID -Message ("Network Contributor role successfully assigned to " + $azPrismaAppParams["AppName"])
            } else {
                Write-Log -Severity "Information" -Subscription $subID -Message ("Network Contributor role already assigned to " + $azPrismaAppParams["AppName"])
            }
            if($azPrismaAppRoles.RoleDefinitionName -notcontains "Security Reader"){
                Write-Log -Severity "Warning" -Subscription $subID -Message ("Security Reader role not assigned to " + $azPrismaAppParams["AppName"])
                New-AzRoleAssignment -RoleDefinitionName "Security Reader" -ApplicationId $azPrismaApp.ApplicationId -ErrorAction "Stop" | Out-Null
                Write-Log -Severity "Information" -Subscription $subID -Message ("Security Reader role successfully assigned to " + $azPrismaAppParams["AppName"])
            } else {
                Write-Log -Severity "Information" -Subscription $subID -Message ("Security Reader role already assigned to " + $azPrismaAppParams["AppName"])
            }
        } catch {
            Write-Log -Severity "Error" -Subscription $subID -Message ("New-AzRoleAssignment: " + $Error[0] | Out-String)
            break 
        }
        <#-------------------------------------------------------------------------------------------------------------
        Send Azure App and Service Principal information to Prisma Cloud via HTTPS using functions in Prisma.WebAPI.ps1
        -------------------------------------------------------------------------------------------------------------#>
        $token = Set-PrismaLogin -username $Env:PrismaCorpAPI_USR -pass $Env:Prisma_CorpAPI_PSW
        $prismaAccountStatus = Get-PrismaCloudAccount -token $token -accountid $subid
        if($prismaAccountStatus.CloudAccount.Enabled -eq $true){
            $addPrismaCloudAccountFuncArgs = @{
                token = $token 
                accountid = $subID
                groupid = $groupid
                name = $subname 
                clientid = $azPrismaAppParams["ClientID"] 
                key = $key 
                tenantid = $azPrismaAppParams["TenantID"] 
                serviceprincipalid = $azPrismaAppParams["ServicePrincipal"]
            }
        } else {
            try {
                #Retrieve access token from Prisma API
                if(!$token){
                    Write-Log -Severity 'Error' -Subscription $subID -Message 'Unable to retrieve Prisma API token'
                } else {
                    Write-Log -Severity "Information" -Subscription $subID -Message "Successfully logged into Prisma"
                    #Check if Azure Subscription is already configured in Prisma Cloud app
                    $prismaAccountStatus = Get-PrismaCloudAccount -token $token -accountid $subID -ErrorAction "SilentlyContinue"
                    if($prismaAccountStatus.CloudAccount.Enabled -eq $true){
                        Write-Log -Severity "Information" -Subscription $subID -Message "Subscription already exists in Prisma"
                    } else {
                        #Check if the Azure App key is Null - not created in this iteration
                        if (!$azPrismaAppParams["key"]){
                            Write-Log -Severity "Error" -Subscription $subID -Message `
                            "Prisma Azure App key value is NULL. Retrieve app info from Azure portal
                            and configure manually in Prisma Cloud"
                        } else {
                            Write-Log -Severity "Warning" -Subscription $subID -Message "Subscription not found in Prisma - creating cloud account"
                            #Convert secure key before sending payload
                            $btsr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($azPrismaAppParams["key"])
                            $key = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($btsr)
                            $addPrismaCloudAccountFuncArgs = @{
                                token = $token 
                                accountid = $subID
                                groupid = $groupid
                                name = $subname 
                                clientid = $azPrismaAppParams["ClientID"] 
                                key = $key 
                                tenantid = $azPrismaAppParams["TenantID"] 
                                serviceprincipalid = $azPrismaAppParams["ServicePrincipal"]
                            }
                            Add-PrismaCloudAccount @addPrismaCloudAccountFuncArgs
                            Start-Sleep -s 5
                            $prismaAccountStatus = Get-PrismaCloudAccount -token $token -accountid $subid
                            if($prismaAccountStatus.CloudAccount.Enabled -eq $true){
                                Write-Log -Severity "Information" -Subscription $subID -Message "Subscription successfully added as Prisma Cloud Account"
                            } else {
                                Write-Log -Severity "Error" -Subscription $subID -Message "Unable to verify subscription was successfully added to Prisma"
                            }
                        }                      
                    }
                }
            } catch {
                Write-Log -Severity "Error" -Subscription $subID -Message ("Unable to send app configuration to Prisma Cloud App: "+ $Error[0])
                $Error[0]
            }
        }
    }
    End {
        Sleep 30
        $RoleAssignment | Remove-AzRoleAssignment | Out-Null
        #Get-AzRoleAssignment -ObjectID $objectid -RoleDefinitionName "Owner" -scope ("/subscriptions/$subid/") | Remove-AzRoleAssignment
        Write-Log -Severity "Information" -Subscription $subID -Message ("End: " + $subID)
    }
}
$Subs = Import-Csv .\accounts.csv
ForEach ($sub in $subs) {
    Set-PrismaAzConfig -subid $sub.id -subname $sub.name -groupId $sub.group
}