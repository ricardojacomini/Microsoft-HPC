configuration CreateADPDC 
{
   param 
   ( 
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Int]$RetryCount=20,
        [Int]$RetryIntervalSec=30
    ) 
    
    Import-DscResource -ModuleName xActiveDirectory, xStorage, xNetworking, PSDesiredStateConfiguration
    [System.Management.Automation.PSCredential ]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)
    $Interface = Get-NetAdapter | Where-Object Name -Like "Ethernet*" | Where-Object Status -EQ "Up" | Select-Object -First 1
    $InterfaceName = $($Interface.Name)

    Node localhost
    {
        LocalConfigurationManager            
        {            
            ActionAfterReboot = 'ContinueConfiguration'            
            ConfigurationMode = 'ApplyOnly'            
            RebootNodeIfNeeded = $true            
        }

        File ADFiles            
        {            
            DestinationPath = 'C:\NTDS'            
            Type = 'Directory'            
            Ensure = 'Present'            
        }

        WindowsFeature ADDSInstall             
        {             
            Ensure = "Present"             
            Name = "AD-Domain-Services"             
        }

        WindowsFeature ADDSTools            
        {            
            Ensure = "Present"            
            Name = "RSAT-ADDS-Tools"            
            DependsOn = "[WindowsFeature]ADDSInstall"            
        }

        WindowsFeature ADAdminCenter            
        {            
            Ensure = "Present"            
            Name = "RSAT-AD-AdminCenter"            
            DependsOn = "[WindowsFeature]ADDSInstall"            
        }
         
        WindowsFeature ADLDSTools            
        {            
            Ensure = "Present"            
            Name = "RSAT-ADLDS"            
            DependsOn = "[WindowsFeature]ADDSInstall"            
        }

        WindowsFeature GPMCInstall            
        {            
            Ensure = "Present"            
            Name = "GPMC"            
            DependsOn = "[WindowsFeature]ADDSInstall"            
        }

        WindowsFeature DNSServerFeature            
        {            
            Ensure = "Present"            
            Name = "DNS"            
        }

        WindowsFeature DNSServerTools            
        {            
            Ensure = "Present"            
            Name = "RSAT-DNS-Server"            
        }

        xWaitforDisk Disk1
        {
            DiskNumber = 1
            RetryIntervalSec =$RetryIntervalSec
            RetryCount = $RetryCount
        }

        xDisk ADDataDisk {
            DiskNumber = 1
            DriveLetter = "F"
            DependsOn = "[xWaitForDisk]Disk1"
        }

        xDnsServerAddress DnsServerAddress 
        { 
            Address        = '127.0.0.1' 
            InterfaceAlias = $InterfaceName
            AddressFamily  = 'IPv4'
            DependsOn = "[WindowsFeature]DNSServerFeature"
        }

        xADDomain FirstDS 
        {
            DomainName = $DomainName
            DomainAdministratorCredential = $DomainCreds
            SafemodeAdministratorPassword = $DomainCreds
            DatabasePath = "F:\NTDS"
            LogPath = "F:\NTDS"
            SysvolPath = "F:\SYSVOL"
            DependsOn = @("[xDisk]ADDataDisk", "[File]ADFiles")
        }

   }
} 
