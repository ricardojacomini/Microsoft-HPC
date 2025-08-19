# Simplified DSC deployment that bypasses disk issues
# Since we already manually formatted the F: drive, we can use it directly

# Define the DSC settings with a custom configuration
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

Write-Host "Checking available DSC extension versions..."
Get-AzVMExtensionImage -Location "eastus" -PublisherName "Microsoft.Powershell" -Type "DSC" | Select-Object Version | Sort-Object Version -Descending | Select-Object -First 10

Write-Host "Current disk status on VM:"
Invoke-AzVMRunCommand -ResourceGroupName "jacomini-hpcpack-hseries-ib-eastus" -VMName "headnodedc" -CommandId "RunPowerShellScript" -ScriptString "Get-Volume | Where-Object DriveLetter -eq 'F'"

Write-Host "Deploying DSC extension..."
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
  -Name "promoteDomainController" `
  -Verbose
