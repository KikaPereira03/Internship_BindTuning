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

    Get-ScrappedSection -section "posts" -network $global:socialNetwork.Name
} else {
    Write-Host "Something went wrong..." -ForegroundColor Red
}