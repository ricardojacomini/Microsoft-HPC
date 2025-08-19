# Upload the fixed DSC script to a temporary location accessible by Azure
# For now, let's create a simpler approach by directly configuring the disk

# First, let's use a custom DSC configuration that works with Disk 1
$customDscScript = @"
configuration CreateADPDC 
{ 
   param 
   ( 
        [Parameter(Mandatory)]
        [String]`$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]`$Admincreds
    ) 
    
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    [System.Management.Automation.PSCredential]`$DomainCreds = New-Object System.Management.Automation.PSCredential ("`${DomainName}\`$(`$Admincreds.UserName)", `$Admincreds.Password)

    Node localhost
    {
        LocalConfigurationManager
        {
            ActionAfterReboot = 'ContinueConfiguration'
            ConfigurationMode = 'ApplyOnly'
            RebootNodeIfNeeded = `$true
        }
        
        WindowsFeature ADDSInstall
        {
            Ensure = "Present"
            Name = "AD-Domain-Services"
        }
        
        WindowsFeature ADDSTools
        {
            Ensure = "Present"
            Name = "RSAT-ADDS"
        }
    }
} 
"@

# Save the custom DSC script
`$customDscScript | Out-File -FilePath "CustomCreateADPDC.ps1" -Encoding UTF8

# Define the DSC settings using inline script
$settings = @{
    configuration = @{
        url = 'https://raw.githubusercontent.com/Azure/hpcpack-template/master/SharedResources/Generated/CreateADPDC.ps1.zip'
        script = 'CreateADPDC.ps1'
        function = 'CreateADPDC'
    }
    configurationArguments = @{
        DomainName = 'hpc.cluster'
    }
}

$protectedSettings = @{
    configurationArguments = @{
        AdminCreds = @{
            UserName = 'hpcadmin'
            Password = 'P@ssw0rd123!'
        }
    }
}

Get-AzVMExtensionImage -Location "eastus" -PublisherName "Microsoft.Powershell" -Type "DSC" | Select-Object Version | Sort-Object Version -Descending | Select-Object -First 10

# Deploy the DSC extension with the standard version
Set-AzVMExtension `
  -ResourceGroupName "jacomini-hpcpack-hseries-ib-eastus" `
  -VMName "headnodedc" `
  -Location "eastus" `
  -Publisher "Microsoft.Powershell" `
  -ExtensionType "DSC" `
  -TypeHandlerVersion "2.80" `
  -Settings $settings `
  -ProtectedSettings $protectedSettings `
  -Name "promoteDomainController"
