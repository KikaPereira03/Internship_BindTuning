. .\_Configs\scrappingsettings.ps1
. .\Login_Linked-In.ps1

#---------------------------------------------
# PROFILE NAVIGATION
#---------------------------------------------

try {
    Write-Host "Navigating to profile page..."
    $global:driver.Navigate().GoToUrl($global:socialNetwork.Name.Profile)

    Write-Host "Waiting for profile to load..."
    $retryCount = 0
    $isProfileLoaded = $false
    

    while ($retryCount -lt $global:maxRetries) {
        try {
            # Wait for profile name (h1) to be visible
            $profileNameElement = $global:driver.FindElementByXPath("//h1[contains(@class, 'inline') and contains(@class, 't-24') and contains(@class, 'v-align-middle')]")

            if ($profileNameElement.Displayed) {
                $profileName = $profileNameElement.Text.Trim()
                Write-Host "Profile loaded successfully: $profileName"
                $isProfileLoaded = $true
                break
            }
        }
        catch {
            Write-Host ("Retry {0}: Profile page not fully loaded yet..." -f $retryCount)
        }

        # Wait before retrying
        Start-Sleep -Seconds 2
        $retryCount++
    }

    if (-not $isProfileLoaded) {
        throw "Profile page did not load after $global:maxRetries retries!"
    }
}
catch {
    Write-Host "Failed to load profile page: $_" -ForegroundColor Red
    $global:driver.Quit()
    Exit 1
}

#---------------------------------------------
# HTML EXTRACTION
#---------------------------------------------

try {
    Write-Host "Extracting page content..."
    $htmlContent = $global:driver.PageSource

    # Create profile folder
    $profileFolderPath = Join-Path (Get-Location) $profileName
    if (-not (Test-Path $profileFolderPath)) {
        New-Item -Path $profileFolderPath -ItemType Directory | Out-Null
        Write-Host "Created folder: $profileFolderPath"
    }

    # Create date-time folder
    $currentDate = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $dateFolderPath = Join-Path $profileFolderPath $currentDate
    if (-not (Test-Path $dateFolderPath)) {
        New-Item -Path $dateFolderPath -ItemType Directory | Out-Null
        Write-Host "Created date folder: $dateFolderPath"
    }

    # Save HTML
    $outputPath = Join-Path $dateFolderPath "Full_HTML.html"
    $htmlContent | Out-File $outputPath
    Write-Host "Profile data saved to: $outputPath" -ForegroundColor Green
}
catch {
    Write-Host "Failed to extract and save HTML: $_" -ForegroundColor Red
}

. .\Create_Sections.ps1