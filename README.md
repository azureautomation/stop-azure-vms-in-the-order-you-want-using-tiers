Stop Azure VMs in the order you want using tiers.
=================================================

            

 

This runbook stops all VM's in a subscription and allows you to specify the preferred order to stop Azure Virtual Machines.

This script uses either certificate-based authentication to connect to Azure, which could be considered 'depricated',

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


 



 




        
    
TechNet gallery is retiring! This script was migrated from TechNet script center to GitHub by Microsoft Azure Automation product group. All the Script Center fields like Rating, RatingCount and DownloadCount have been carried over to Github as-is for the migrated scripts only. Note : The Script Center fields will not be applicable for the new repositories created in Github & hence those fields will not show up for new Github repositories.
