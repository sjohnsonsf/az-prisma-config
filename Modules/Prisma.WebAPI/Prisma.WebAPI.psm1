<#
.SYNOPSIS
  Provides functions for calling the Prisma Cloud API. 
.DESCRIPTION
  Uses the .Net HTTP Client to make GET and POST RESTful API calls via the included functions to the Prisma Cloud API.
#>
#---------------------------------------------------------[Initialisations]--------------------------------------------------------
  #None
#----------------------------------------------------------[Declarations]----------------------------------------------------------
  #None
#-----------------------------------------------------------[Functions]------------------------------------------------------------
function Set-PrismaLogin {
  <#
  .SYNOPSIS
    Used to request an access token from the Prisma Cloud API. 
  .DESCRIPTION
    Before making any subsequent calls to the Prisma Cloud API, an access token must be available. This function retrieves the required access
    token after POSTing the username and password. 
  .PARAMETER username
    The "Access Key ID" provided by the Prisma Cloud App. 
  .PARAMETER pass
    The "Secret key" provided by the Prisma Cloud App. 
  .EXAMPLE
    Set-PrismaLogin -username "xxxx-xxxx-xxxx-xxxx" -pass "XXXXXXXXX"
  .NOTES
    This function is consumed in the Set-PrismaAzConfig.ps1 script.
  #>
  [CmdletBinding()]
	Param(
    [Parameter(Mandatory=$true)]
    [string]$username, 
    [Parameter(Mandatory=$true)]
    [string]$pass
  )
  process {
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $accept = New-Object System.Net.Http.Headers.MediaTypeWithQualityHeaderValue -ArgumentList "application/json" -Property @{
      CharSet = "UTF-8"
    }
    $client.DefaultRequestHeaders.Accept.Add($accept)
    $client.DefaultRequestHeaders.CacheControl = New-Object System.Net.Http.Headers.CacheControlHeaderValue -Property @{
      NoCache = $true
    }
    $body = @{
      username = $username
      password = $pass
    } | ConvertTo-Json
    $stringContent = New-Object System.Net.Http.StringContent -ArgumentList $body, ([System.Text.Encoding]::UTF8), "application/json"
    $result = $client.PostAsync("https://api2.prismacloud.io/login", $stringContent).GetAwaiter().GetResult()
    if ($result.IsSuccessStatusCode)
    {
      ($result.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json).Token
      $Client.Dispose()
    } else {
      $result
      $client.Dispose()
    }
  }
}

function Get-PrismaNewToken {
    <#
  .SYNOPSIS
    Returns the Prisma Cloud Account Groups from the Prisma Cloud app
  .DESCRIPTION
    Account Groups are a feature of the Prisma Cloud for organizing Cloud Accounts (Azure Subscriptions).
    This functions retrieves all Account Groups and their properties from the Prisma Cloud app. 
  .PARAMETER token
    API credential - returned from the Set-PrismaLogin function. 
  .OUTPUTS
    Prisma Cloud Account Group objects.
  .EXAMPLE
    Get-PrismaAccountGroups -token xxxxxxxxxxxxx
  .NOTES
    This function is consumed in the Set-PrismaAzConfig.ps1 script. 
#>
[CmdletBinding()]
Param(
  [Parameter(Mandatory=$true)]
  [string]$token
)
process {
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $accept = New-Object System.Net.Http.Headers.MediaTypeWithQualityHeaderValue -ArgumentList "application/json" -Property @{
      CharSet = "UTF-8"
    }
    $client.DefaultRequestHeaders.Accept.Add($accept)
    $client.DefaultRequestHeaders.CacheControl = New-Object System.Net.Http.Headers.CacheControlHeaderValue -Property @{
      NoCache = $true
    }
    $client.DefaultRequestHeaders.TryAddWithoutValidation("x-redlock-auth",$token)
    $result = $client.GetAsync("https://api2.prismacloud.io/auth_token/extend").GetAwaiter().GetResult()
    if ($result.IsSuccessStatusCode) {
      $result.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
      $client.Dispose()
    } else {
      $result
      $client.Dispose()
    }
  }
}

function Get-PrismaAccountGroups {
    <#
  .SYNOPSIS
    Returns the Prisma Cloud Account Groups from the Prisma Cloud app
  .DESCRIPTION
    Account Groups are a feature of the Prisma Cloud for organizing Cloud Accounts (Azure Subscriptions).
    This functions retrieves all Account Groups and their properties from the Prisma Cloud app. 
  .PARAMETER token
    API credential - returned from the Set-PrismaLogin function. 
  .OUTPUTS
    Prisma Cloud Account Group objects.
  .EXAMPLE
    Get-PrismaAccountGroups -token xxxxxxxxxxxxx
  .NOTES
    This function is consumed in the Set-PrismaAzConfig.ps1 script. 
  #>
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory=$true)]
    [string]$token
  )
  process {
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $accept = New-Object System.Net.Http.Headers.MediaTypeWithQualityHeaderValue -ArgumentList "application/json" -Property @{
      CharSet = "UTF-8"
    }
    $client.DefaultRequestHeaders.Accept.Add($accept)
    $client.DefaultRequestHeaders.CacheControl = New-Object System.Net.Http.Headers.CacheControlHeaderValue -Property @{
      NoCache = $true
    }
    $client.DefaultRequestHeaders.TryAddWithoutValidation("x-redlock-auth",$token)
    $result = $client.GetAsync("https://api2.prismacloud.io/cloud/group").GetAwaiter().GetResult()
    if ($result.IsSuccessStatusCode) {
      $result.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
      $client.Dispose()
    } else {
      $result
      $client.Dispose()
    }
  }
}
function Get-PrismaCloudAccount {
  <#
  .SYNOPSIS
    Retrieves an existing Cloud Account (Azure Subscription) from the Prisma Cloud app.
  .DESCRIPTION
    Azure Subscriptions are listed in the Prisma Cloud console as Cloud Accounts. 
    The Azure Subscription ID is used as the Cloud Account ID. This function allows
    scripts to confirm the that an existing Azure Subscription is configured in
    the Prisma Cloud app.
  .PARAMETER token
    API credential - returned from the Set-PrismaLogin function. 
  .PARAMETER accountid
    Azure Subscription ID.
  .OUTPUTS
    Returns Cloud Account object. 
  .EXAMPLE
    Get-PrismaCloudAccount -token xxxxxxxxxx -accountid xxxxxxxxxxx
  .NOTES
    This function is consumed in the Set-PrismaAzConfig.ps1 script. 
    "Enabled" property of Cloud Account object is used to confirm it is active. 
  #>
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory=$true)]
    [string]$token,
    [Parameter(Mandatory=$true)]
    [string]$accountid
  )
  process {
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $accept = New-Object System.Net.Http.Headers.MediaTypeWithQualityHeaderValue -ArgumentList "application/json" -Property @{
      CharSet = "UTF-8"
    }
    $client.DefaultRequestHeaders.Accept.Add($accept)
    $client.DefaultRequestHeaders.CacheControl = New-Object System.Net.Http.Headers.CacheControlHeaderValue -Property @{
      NoCache = $true
    }
    $client.DefaultRequestHeaders.TryAddWithoutValidation("x-redlock-auth",$token)
    $result = $client.GetAsync("https://api2.prismacloud.io/cloud/azure/$accountid").GetAwaiter().GetResult()
    if ($result.IsSuccessStatusCode) {
      $result.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
      $client.Dispose()
    } else {
      $result
      $client.Dispose()
    }
  }
}
function Add-PrismaCloudAccount {
   <#
  .SYNOPSIS
    Adds Azure Subscription to Prisma Cloud app via App and Service Principal properties. 
  .DESCRIPTION
    Sends the required App and Service Principal credentials and subscription
    properties to a Prisma Cloud Account. 
  .PARAMETER token
    API credential - returned from the Set-PrismaLogin function. 
  .PARAMETER accountid
    Azure Subscription ID.
  .PARAMETER groupid
    Group ID(s) for organizing the Cloud Accounts in the Prisma Cloud app. 
  .PARAMETER name
    A unique name for the account in the Prisma Cloud app. 
  .PARAMETER clientid
    The Client ID of the Azure App that is created for the subscription.  
  .PARAMETER key
    The secret key of the Azure app that is created for the subscription. 
  .PARAMETER tenantid
    Azure Active Directory (AAD) Tenant (Directory) ID. 
  .PARAMETER serviceprincipalid
    The ID of the Azure Service Principal created for the subscription. 
  .OUTPUTS
    None if successfully. API response on failures. 
  .EXAMPLE
    Add-PrismaCloudAccount `
      -token "xxxxxxxxxxx" `
      -accountid "xxxx-xxxxx-xxxxx-xxxxx" `
      -groupid "xx1234-6789xxx-9123xxxx-123456" `
      -name "sp-prisma-acbc12345"`
      -clientid "xxxxxxxxxxxxxxx" `
      -key "xxxxxxxxxxxxxx" `
      -tenantid "123456xxxxxxxxxxx" `
      -serviceprincipalid "xxxxxxxxxxxxxxxxxxxxxxxx"
  .NOTES
    This function is consumed in the Set-PrismaAzConfig.ps1 script. 
  #>
  [CmdletBinding()]
	Param(
    [parameter(Mandatory=$true)]
    [string]$token,
    [Parameter(Mandatory=$true)]
    [string]$accountId,
    [Parameter(Mandatory=$true)]
    [string]$name,
    [parameter(Mandatory=$true)]
    [string]$clientid,
    [parameter(Mandatory=$false)]
    [string]$groupid,
    [parameter(Mandatory=$true)]
    [string]$key,
    [parameter(Mandatory=$true)]
    [string]$tenantid, 
    [parameter(Mandatory=$true)]
    [string]$serviceprincipalid
  )
  process {
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $accept = New-Object System.Net.Http.Headers.MediaTypeWithQualityHeaderValue -ArgumentList "application/json" -Property @{
      CharSet = "UTF-8"
    }
    $client.DefaultRequestHeaders.Accept.Add($accept)
    $client.DefaultRequestHeaders.CacheControl = New-Object System.Net.Http.Headers.CacheControlHeaderValue -Property @{
      NoCache = $true
    }
    $client.DefaultRequestHeaders.TryAddWithoutValidation("x-redlock-auth",$token)
    $body = [ordered]@{
      cloudAccount = [ordered]@{
        accountId = $accountId
        enabled = $true
        groupIds = @(,"ba7f305e-815a-473b-990d-95ad4cfb63e4")
        name = $name
        accountType = "Account"
        protectionMode = "MONITOR"
      }
      clientId = $clientid
      key = $key
      monitorFlowLogs = $true
      tenantId = $tenantid
      servicePrincipalId = $serviceprincipalid
      } | ConvertTo-Json -EscapeHandling EscapeHtml
    Write-Host $body
    $stringContent = New-Object System.Net.Http.StringContent -ArgumentList $body, ([System.Text.Encoding]::UTF8), "application/json"
    $result = $client.PostAsync("https://api2.prismacloud.io/cloud/azure", $stringContent).GetAwaiter().GetResult()
    if ($result.IsSuccessStatusCode) {
      $result.Content.ReadAsStringAsync().GetAwaiter().GetResult()
      $client.Dispose()
    } else {
      $result

      $client.Dispose()
    }
  }
}

#Make the functions available on module import 
Export-ModuleMember -Function Set-PrismaLogin, Get-PrismaNewToken, Get-PrismaAccountGroups, Get-PrismaCloudAccount, Add-PrismaCloudAccount