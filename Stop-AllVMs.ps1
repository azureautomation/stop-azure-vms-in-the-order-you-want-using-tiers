<#

# THIS CODE AND ANY ASSOCIATED INFORMATION ARE PROVIDED “AS IS” WITHOUT
# WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT
# LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS
# FOR A PARTICULAR PURPOSE. THE ENTIRE RISK OF USE, INABILITY TO USE, OR 
# RESULTS FROM THE USE OF THIS CODE REMAINS WITH THE USER.

.SYNOPSIS 
	Stops all VM's in a subscription.

.DESCRIPTION
	This runbook stops all VM's in a subscription. 
    This script uses either certificate-based authentication to connect to Azure, which could be considered "depricated", 
    using the $AzureConnectionName parameter, or authentication using an Organizational ID, using the $AzureCredentials 
    and $AzureSubscriptionName parameters.
    
    You need to specify either $AzureConnectionName or $AzureCredentials and $AzureSubscriptionName.
    If all are specified, the script will use $AzureConnectionName
    
    Servers that you do not want to stop, can be specified in the $DontStop parameter. Wildcards are supported.
    Servers that you want to stop first, can be specified in the $FirstStopServersByTier parameter. Wildcards are supported.
    Servers that you want to stop last, can be specified in the $LastStopServersByTier parameter. Wildcards are supported.

    Known limitations
    If you use the $AzureCredentials and $AzureSubscriptionName to connect to you Azure subscription,
    and you have two subscriptions with the same name, the output is unpredictable or the script might fail.
    If you have servers with the same name in different Cloud Services, you cannot handle these servers differently. 
    E.g. if you tell the script not to stop a server called 'DC1', and this server exists in two different Cloud Services, 
    none of the servers called 'DC1' will be stopped.
    PaaS Virtual Machines will be treated as IaaS virtual machines. It's not possible to shut down specific instances of a PaaS role.

.PARAMETER AzureConnectionName
	String name of the Azure connection asset. If this parameter is specified, you do not need to specify AzureCredentials 
    and AzureSubscriptionName

.PARAMETER AzureCredentials
	String name of the Azure credential asset. If this parameter is specified, you also need to specify AzureSubscriptionName, 
    but you do not need to specify AzureConnectionName

.PARAMETER AzureSubscriptionName
	String name of the Azure Subscription. If this parameter is specified, you also need to specify AzureCredentials, 
    but you do not need to specify AzureConnectionName

.PARAMETER DontStop
    Use this optional parameter to specify Virtual Machine Names for machines that you do not want to stop.
    Separate names with a comma (,). No not put server names in quotes. Wildcards (? and *) are supported.
    Example:
    DC*,ADFS?,WEBSRV

.PARAMETER FirstStopServersByTier
	Use this optional parameter to specify Virtual Machine Names for machines that need to be shut down first.
    Separate machine names with a comma (,) and group them in 'tiers'. Machines in the first tier will be stopped first, then machines
    in the second tier, and so on. If machines are not listed in a tier, they will be shut down last. 
    Wildcards (? and *) are supported.
    Example:
    ['WAP?,ADFS*','EXCH1','DC1,DC2']
    This will first stop all machines with names like WAP? and ADFS* (for example WAP1, WAP2, ADFSSRV1 and ADFSSRV2), then all machines
    called EXCH1, then all machines called DC1 and DC2.

.PARAMETER LastStopServersByTier
	Use this optional parameter to specify Virtual Machine Names for machines that need to be shut down last.
    Separate machine names with a comma (,) and group them in 'tiers'. Machines in the first tier will be stopped first after all other
    machine, then machines in the second tier, and so on. Machines in the last tier will be shut down last.
    If machines are not listed in DontStop or FirstStopServersByTier tier, they will be shut down before these machines. 
    Wildcards (? and *) are supported.
    Example:
    ['WAP?,ADFS*','EXCH1','DC1,DC2']
    This will first stop all machines with names not matching machine names in this list, and then stop all machines with names like WAP?
    and ADFS* (for example WAP1, WAP2, ADFSSRV1 and ADFSSRV2), then all machines called EXCH1, then all machines called DC1 and DC2.

.NOTES
	Author: Tino Donderwinkel (tinodo@microsoft.com)
	Last Updated: 02-04-2015   
#>


workflow Stop-AllVMs
{

    Param
    (   
        [Parameter(Mandatory=$false)]
        [String]
        $AzureConnectionName,

        [Parameter(Mandatory=$false)]
        [String]
        $AzureCredentials,

        [parameter(Mandatory=$false)]
        [String]
        $AzureSubscriptionName,
        
        [Parameter(Mandatory=$false)]
        [String]
        $DontStop,
        
        [parameter(Mandatory=$false)]
		[String[]]
        $FirstStopServersByTier,
        
        [parameter(Mandatory=$false)]
		[String[]]
        $LastStopServersByTier  
    )

    if ($AzureConnectionName)
    {

        # Get the Azure connection asset that is stored in the Automation service based on the name that was passed into the runbook 
        $AzureConnection = Get-AutomationConnection -Name $AzureConnectionName
        if ($AzureConnection -eq $null)
        {
            throw "Could not retrieve '$AzureConnectionName' connection asset. Check that you created this first in the Automation service."
        }

        # Get the Azure management certificate that is used to connect to this subscription
        $Certificate = Get-AutomationCertificate -Name $AzureConnection.AutomationCertificateName
        if ($Certificate -eq $null)
        {
            throw "Could not retrieve '$AzureConnection.AutomationCertificateName' certificate asset. Check that you created this first in the Automation service."
        }

        # Set the Azure subscription configuration
        Set-AzureSubscription -SubscriptionName $AzureConnectionName -SubscriptionId $AzureConnection.SubscriptionID -Certificate $Certificate

        # Select the Azure subscription
        Select-AzureSubscription -SubscriptionId $AzureConnection.SubscriptionID
    }
    elseif ($AzureCredentials -And $AzureSubscriptionName)
    {
        # Get the Azure credential asset that is stored in the Automation service based on the name that was passed into the runbook 
        $credentials = Get-AutomationPSCredential -Name $AzureCredentials
        if ($credentials -eq $null)
        {
            throw "Could not retrieve '$AzureCredentials' credetials asset. Check that you created this first in the Automation service."
        }

        # Add the Azure account
        Add-AzureAccount -Credential $credentials

        # Select the Azure subscription
        Select-AzureSubscription -SubscriptionName $AzureSubscriptionName
    }
    else
    {
        throw "Either specify AzureConnectionName or AzureCredentials and AzureSubscriptionName."
    }

    # Get all Azure Virtual Machines
    $vms = Get-AzureVm | Where-Object -FilterScript {$_.Status -eq "ReadyRole"}
    
    # Remove virtual machines that we don't want to stop from the list of all virtual machines.
    if ($DontStop -ne $null)
    {
        $servers = ServersInTier -VMs $vms -Tier $DontStop
        $vms = $vms | Where-Object -FilterScript {$servers -notcontains $_}
    }    

    $stopFirst = @()
    $stopMiddle = $vms
    $stopLast = @()

    # Build the list of virtual machines that we want to stop first from the $FirstStopServersByTier parameter, if any
    If ($FirstStopServersByTier -ne $null)
    {
        $stopFirst = ServersInTiers -VMs $vms -Tiers $FirstStopServersByTier
        $stopFirstNames = $stopFirst | ForEach-Object {$_.Name}
        $stopMiddle = $stopMiddle | Where-Object -FilterScript {$stopFirstNames -notcontains $_.Name}
    }

    # Build the list of virtual machines that we want to stop last from the $LastStopServersByTier parameter, if any
    If ($LastStopServersByTier -ne $null)
    {
        $stopLast = ServersInTiers -VMs $vms -Tiers $LastStopServersByTier
        $stopLastNames = $stopLast | ForEach-Object {$_.Name}
        $stopMiddle = $stopMiddle | Where-Object -FilterScript {$stopLastNames -notcontains $_.Name}
    }

    # Build the list of virtual machines that will be stopped, in the correct order.
    $orderedVMs = @()
    $orderedVMs += $stopFirst
    $orderedVMs += ,$stopMiddle
    $orderedVMs += $stopLast

    # Stop all virtual machines that need to be stopped.
    $t = 0;
    foreach ($tier in $orderedVMs)
    {
        $t++
        foreach ($server in $tier)
        {
            Write-Output "Tier $t - Stopping $($server.Name) in Cloud Service $($server.ServiceName)"
            $server | Stop-AzureVM -Force
        }
    }

    
    Function ServersInTier
    {
        Param
        (
            [Parameter(Mandatory=$true)]
            [Array]$VMs,

            [Parameter(Mandatory=$true)]
            [String[]]$Tier
        )
        $result = @()
        $names = $tier.Split(',')
        ForEach ($name in $names)
        {
            $result += $VMs | Where-Object -FilterScript {$_.Name -like $name}
        }
        Return $result
    }

    Function ServersInTiers
    {
        Param
        (
            [Parameter(Mandatory=$true)]
            [Array]$VMs,

            [Parameter(Mandatory=$true)]
            [String[]]$Tiers
        )

        $result = @()
        ForEach ($tier in $Tiers)
        {
            $result += ,(ServersInTier -VMs $VMs -Tier $tier)
        }
        Return $result
    }
}