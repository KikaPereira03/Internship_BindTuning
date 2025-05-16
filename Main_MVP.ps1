Clear-Host

. .\Services\Selenium.ps1

$attemptCount = 0
$maxRetries = 10

Write-Host "Navigating to MVP page"
$global:driver.Navigate().GoToUrl("https://mvp.microsoft.com/en-US/search?target=Profile&program=MVP")

do {
    $attemptCount += 1
    
    Write-Host "LOOP ITERATION: Attempt $attemptCount of $maxRetries" -ForegroundColor Magenta

    # Check if the MVP list container is present
    try {
        $mvpPageContainer = $global:driver.FindElementByXPath("//div[@class='sc-eFubAy enAppf']")

        # Check if the MVP list container is displayed
        if ($mvpPageContainer.Displayed) {
            Write-Host "Found mvp list container." -ForegroundColor Green
            $attemptCount = $maxRetries

            # Click to filter the MVP list container and click on the 'Technology Area' (the last div)
            $filterList = $global:driver.FindElementsByXPath("//*[contains(@class, 'container-')]/div/div[2]/div[last()]")
            $filterList.Click()
            Start-Sleep -Seconds 1
            
            # Filter the MVP list container
            $filterMatchedProceeded = $false
            $filterToClick = @("M365 Development", "Microsoft 365", "SharePoint")
            $tecListItems = $filterList[0].FindElementsByXPath("//li")
            
            foreach ($tecItem in $tecListItems) {
                # Check if the text of the item is in the filter list
                if($filterToClick -contains $tecItem.Text) {
                    $filterMatchedProceeded = $true
                    Write-Host "Clicking filter: $($tecItem.Text)" -ForegroundColor Green

                    $tecItem.FindElementByClassName("ms-Checkbox-text").Click()
                    Start-Sleep -Seconds 2
                }
            }

            # Check if the filter was applied successfully
            if($filterMatchedProceeded) {
                Write-Host "Filter applied successfully." -ForegroundColor Green

                $mvpList = $mvpPageContainer.FindElementsByClassName("ms-Card")
                $indexMvp = 0
                
                #foreach ($mvpItem in $mvpList) {
                # iterate through the MVP list items
                while ($indexMvp -lt $mvpList.Count) {
                    $mvpItem = $mvpList[$indexMvp]

                    if($null -eq $mvpItem.TagName) {
                        Start-Sleep -Seconds 3

                        # When '$global:driver.Navigate().Back()' to the MVP list, the MVP item is not found. Assign the MVP item again
                        $mvpPageContainer = $global:driver.FindElementByXPath("//div[@class='sc-eFubAy enAppf']")
                        $mvpList1 = $mvpPageContainer.FindElementsByClassName("ms-Card")
                        $mvpItem = $mvpList1[$indexMvp]
                    } 

                    $indexMvp++
                    $attemptLinkedIn = 0
                    $attemptLinkedInRetries = 10
                    
                    Write-Host "Processing MVP item..." -ForegroundColor Green
                    $mvpItem.Click()
                    Start-Sleep -Seconds 3

                    do {
                        $attemptLinkedIn += 1

                        try {
                            # Check if the single page for MVP is available
                            $linkedInProfile = $global:driver.FindElementByXPath("//img[@alt='LinkedIn']")

                            if($linkedInProfile.Displayed) {
                                # Get the LinkedIn profile URL
                                $linkedInProfileUrl = ($linkedInProfile.GetAttribute("Title") -split '\|')[1].Trim()
                                $linkedInProfileUrl = ($linkedInProfileUrl.TrimEnd('/') -split '/')[-1]
                                Write-Host "LinkedIn profile found: $linkedInProfileUrl" -ForegroundColor Green
                                
                                # Appended the LinkedIn profile URL to the file users.txt
                                if (-not (Test-Path -Path ".\users.txt")) {
                                    New-Item -Path ".\users.txt" -ItemType File
                                } else {
                                    Add-Content -Path ".\users.txt" -Value $linkedInProfileUrl
                                    $attemptLinkedIn = $attemptLinkedInRetries
                                    $global:driver.Navigate().Back()
                                }                                
                            }
                        } catch {
                            # Handle the case when the LinkedIn profile is not found
                            Write-Host "LinkedIn profile not found." -ForegroundColor Red
                            $attemptLinkedIn = $attemptLinkedInRetries
                            $global:driver.Navigate().Back()
                            continue
                        }
                    } while ($attemptLinkedIn -lt $attemptLinkedInRetries)


                    # End of MVP items processing
                    if($indexMvp -eq $mvpList.Count) {
                        Write-Host "Validation if they're more page to processing..." -ForegroundColor Yellow
                        Start-Sleep -Seconds 5

                        # Validate if are more pages to process
                        $nextPage = $global:driver.FindElementsByXPath("//*[contains(@class, 'pagination')]/li[last()]")
                        
                        if($nextPage.GetAttribute("class") -eq "page-item disabled") {
                            # No more pages to process
                            Write-Host "No more pages to process." -ForegroundColor Orange
                            $attemptCount = $maxRetries
                        } else {
                            # There are more pages to process
                            Write-Host "Next page found. Proceeding to next page." -ForegroundColor Yellow
                            $nextPage.Click()
                            Start-Sleep -Seconds 5
                            
                            # Reinitialize the MVP list
                            $indexMvp = 0
                            $mvpPageContainer = $global:driver.FindElementByXPath("//div[@class='sc-eFubAy enAppf']")
                            $mvpList = $mvpPageContainer.FindElementsByClassName("ms-Card")
                        }
                    }
                }

            } else {
                Write-Host "No matching filter found." -ForegroundColor Red
            }
        }
    }
    catch {
        write-host "Someting happen durint the MVP list generation." -ForegroundColor Red
    }
    
    # Add an explicit wait before next iteration
    if ($attemptCount -lt $maxRetries) {
        Write-Host "Waiting 3 seconds before next attempt..." -ForegroundColor Gray
        Start-Sleep -Seconds 3
    }
} while ($attemptCount -lt $maxRetries)

write-host "MVP list generated." -ForegroundColor Green