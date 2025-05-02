Clear-Host

#Imports
. .\_Configs\scrappingsettings.ps1
. .\Services\Selenium.ps1
. .\Services\Login.ps1
. .\Factory\ScrappingSections.ps1
. .\Factory\ConstructPath.ps1

# Start Scrapping
$loggedIn = Login-Network -network $global:socialNetwork.Name

if($loggedIn) {
    Write-Host "I'm in..." -ForegroundColor Green

    foreach ($profile in $networkProfiles) {
        Get-Posts -Profile $profile
        Start-Sleep -Seconds 10
    }
} else {
    Write-Host "Something went wrong..." -ForegroundColor Red
}

# Close the browser when finished
if ($global:driver) {
    Write-Host "Closing browser..." -ForegroundColor Cyan
    $global:driver.Quit()
    Write-Host "Browser closed successfully." -ForegroundColor Green
}