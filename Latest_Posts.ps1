. .\Login_Linked-In.ps1
. .\_Configs\scrappingsettings.ps1

#---------------------------------------------
# SHOW ALL POSTS / EXTRACT HTML
#---------------------------------------------

# Navigate to latest activity/posts
$postsUrl = $profileUrl + "recent-activity/all/"
Write-Host "Navigating to posts page: $postsUrl"
$driver.Navigate().GoToUrl($postsUrl)

$retryCount = 0
$pageLoaded = $false
$maxRetries = 10

Start-Sleep -Seconds 2

while ($retryCount -lt $maxRetries) {
    try {
        $allActivityHeader = $driver.FindElementsByXPath("//div[contains(@class, 'scaffold-finite-scroll__content')]/ul/li
        ")
        if ($allActivityHeader.Count -gt 0) {
            $pageLoaded = $true
            break
        } else {
            Write-Host "Retry $($retryCount + 1): Posts page not loaded yet..."
        }
    } catch {
        Write-Host "Retry $($retryCount + 1): Posts page not loaded yet..."
    }
    Start-Sleep -Seconds 3
    $retryCount++
}

if (-not $pageLoaded) {
    Write-Host "Could not confirm that the posts page loaded."
    return
}

Write-Host "Posts page loaded."


# After navigating to the posts page
Write-Host "Attempting to find posts by 'Feed post number' headers..."


try {
    # First try with exact class and content
    $feedPostHeaders = $driver.FindElementsByXPath("//h2[@class='visually-hidden' and contains(text(), 'Feed post number')]")
    Write-Host "Found $($feedPostHeaders.Count) feed post headers with class and content match"
    
    # If that fails, try a broader approach
    if ($feedPostHeaders.Count -eq 0) {
        # Try with just the content
        $feedPostHeaders = $driver.FindElementsByXPath("//h2[contains(text(), 'Feed post number')]")
        Write-Host "Found $($feedPostHeaders.Count) feed post headers with just content match"
        
        # If still no results, do a more exhaustive search
        if ($feedPostHeaders.Count -eq 0) {
            # Try searching the entire DOM
            $allHeaders = $driver.FindElementsByTagName("h2")
            Write-Host "Found $($allHeaders.Count) total h2 elements on page"
            
            # Examine each one
            foreach ($header in $allHeaders) {
                try {
                    $text = $header.Text
                    if ($text -match "Feed post number") {
                        Write-Host "Found a matching header with text: $text"
                        # Do a direct JavaScript check
                        $isVisible = $driver.ExecuteScript("return arguments[0].offsetParent !== null;", $header)
                        Write-Host "Is this element visible? $isVisible"
                    }
                } catch {
                    Write-Host "Error examining header: $_"
                }
            }
        }
    }
    
    if ($feedPostHeaders.Count -gt 0) {
        # If headers found, get the post elements from there
        $postElements = @()
        foreach ($header in $feedPostHeaders) {
            try {
                # Try different ancestry paths
                $paths = @(
                    "./ancestor::div[contains(@class, 'feed-shared-update-v2')]",
                    "./ancestor::div[@role='article']",
                    "./ancestor::div[contains(@class, 'relative') and contains(@class, 'artdeco-card')]"
                )
                
                foreach ($path in $paths) {
                    try {
                        $postElement = $header.FindElementByXPath($path)
                        if ($postElement) {
                            $postElements += $postElement
                            Write-Host "Found post container using path: $path"
                            break
                        }
                    } catch {
                        # Continue to next path
                    }
                }
            } catch {
                Write-Host "Failed to find post container for a header: $_"
            }
        }
        
        if ($postElements.Count -gt 0) {
            Write-Host "Successfully found $($postElements.Count) complete posts!"
            
            # Save these posts
            $limit = [Math]::Min(10, $postElements.Count)
            $htmlOutput = "<html><head><meta charset='UTF-8'><title>Posts By Headers</title></head><body>"
            
            for ($i = 0; $i -lt $limit; $i++) {
                try {
                    $html = $postElements[$i].GetAttribute("outerHTML")
                    if ($html) {
                        $htmlOutput += $html
                        Write-Host "Added complete post $($i+1) to output"
                    }
                } catch {
                    Write-Host "Error reading post $($i+1): $_"
                }
            }
            
            $htmlOutput += "</body></html>"
            $postsPath = Join-Path $dateFolderPath "Posts_By_Headers.html"
            $htmlOutput | Out-File $postsPath -Encoding UTF8
            Write-Host "Saved $limit posts to: $postsPath"
        } else {
            Write-Host "Could not find post containers from headers"
        }
    }
} catch {
    Write-Host "Error trying to find posts by headers: $_"
}