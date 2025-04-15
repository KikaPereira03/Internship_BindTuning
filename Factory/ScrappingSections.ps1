function Get-ScrappedSection {
    param(
        [string]$section,
        [string]$network
    )

    switch ($section) {
        "posts" {
            Get-Posts -network $network;
            break
        }
        "profile" {
            Get-Profile;
            break
        }
    }
}

function Get-Posts {
    param(
        [string]$network
    )
    
    . .\Factory\ConstructPath.ps1

    # Get the paths for saving data
    $paths = Get-LinkedInDataPath -profileUrl $global:socialNetwork.Profile
    $postsHtmlPath = $paths.FilePath

    #---------------------------------------------
    # SHOW ALL POSTS / EXTRACT HTML
    #---------------------------------------------

    # Navigate to latest activity/posts
    $postsUrl = $global:socialNetwork.Profile + "recent-activity/all/"
    Write-Host "Navigating to posts page: $postsUrl"
    $global:driver.Navigate().GoToUrl($postsUrl)

    $retryCount = 0
    $pageLoaded = $false

    Start-Sleep -Seconds 2

    while ($retryCount -lt $global:maxRetries) {
        try {
            $allActivityHeader = $global:driver.FindElementsByXPath("//div[contains(@class, 'scaffold-finite-scroll__content')]/ul/li
        ")
            if ($allActivityHeader.Count -gt 0) {
                $pageLoaded = $true
                break
            }
            else {
                Write-Host "Retry $($retryCount + 1): Posts page not loaded yet..."
            }
        }
        catch {
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
        $feedPostHeaders = $global:driver.FindElementsByXPath("//h2[@class='visually-hidden' and contains(text(), 'Feed post number')]")
        Write-Host "Found $($feedPostHeaders.Count) feed post headers with class and content match"
    
        # If that fails, try a broader approach
        if ($feedPostHeaders.Count -eq 0) {
            # Try with just the content
            $feedPostHeaders = $global:driver.FindElementsByXPath("//h2[contains(text(), 'Feed post number')]")
            Write-Host "Found $($feedPostHeaders.Count) feed post headers with just content match"
        
            # If still no results, do a more exhaustive search
            if ($feedPostHeaders.Count -eq 0) {
                # Try searching the entire DOM
                $allHeaders = $global:driver.FindElementsByTagName("h2")
                Write-Host "Found $($allHeaders.Count) total h2 elements on page"
            
                # Examine each one
                foreach ($header in $allHeaders) {
                    try {
                        $text = $header.Text
                        if ($text -match "Feed post number") {
                            Write-Host "Found a matching header with text: $text"
                            # Do a direct JavaScript check
                            $isVisible = $global:driver.ExecuteScript("window.scrollBy(0, 1000);")
                            Write-Host "Is this element visible? $isVisible"
                        }
                    }
                    catch {
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
                        }
                        catch {
                            # Continue to next path
                        }
                    }
                }
                catch {
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
                    }
                    catch {
                        Write-Host "Error reading post $($i+1): $_"
                    }
                }
            
                $htmlOutput += "</body></html>"
                $htmlOutput | Out-File $postsHtmlPath -Encoding UTF8
                Write-Host "Saved $limit posts to: $postsHtmlPath"
            }
            else {
                Write-Host "Could not find post containers from headers"
            }
        }
    }
    catch {
        Write-Host "Error trying to find posts by headers: $_"
    }

    Write-Host "Beginning scrolling to find post #10..."

    $maxScrollAttempts = 15
    $scrollAttempt = 0
    $targetFound = $false
    $noChangeCount = 0

    # First, check what posts we already have
    $initialPosts = @()
    $highestPostSeen = 0
    
    try {
        $initialPosts = $global:driver.ExecuteScript(@"
const headers = Array.from(document.querySelectorAll('h2'))
              .filter(h => h.textContent.includes('Feed post number'))
              .map(h => h.textContent.trim());
return headers;
"@)
    
        Write-Host "Initial scan found $($initialPosts.Count) posts:"
    
        # Extract post numbers and find the highest one
        foreach ($post in $initialPosts) {
            Write-Host "  - $post"
            if ($post -match "Feed post number (\d+)") {
                $number = [int]$matches[1]
                if ($number -gt $highestPostSeen) {
                    $highestPostSeen = $number
                }
            
                if ($number -eq 10) {
                    $targetFound = $true
                }
            }
        }
    
        Write-Host "Highest post number initially visible: #$highestPostSeen"
    
        if ($targetFound) {
            Write-Host "Post #10 already visible! No need to scroll."
        }
    }
    catch {
        Write-Host "Error during initial post scan: $_"
        $highestPostSeen = 0
    }

    # This code snippet should replace the "Now look for next post in sequence" section
    # Now look for next post in sequence if we haven't already found post #10
    if (-not $targetFound) {
        $targetPostNumber = $highestPostSeen + 1
        $scrollAttempt = 0  # Reset scroll attempt counter
        $postFound = $false
        $noChangeCount = 0  # Reset no change counter
        $maxCheckAttemptsBeforeScroll = 10  # Number of check attempts before scrolling again
    
        Write-Host "Looking for post #$($targetPostNumber)..."
    
        # First, scroll to just below the last visible post
        try {
            # Find position of last visible post
            $lastVisiblePostPosition = $global:driver.ExecuteScript(@"
const headers = Array.from(document.querySelectorAll('h2'))
              .filter(h => h.textContent.includes('Feed post number'))
              .filter(h => h.offsetParent !== null); // Only visible ones
if (headers.length > 0) {
    const lastPost = headers[headers.length - 1];
    return lastPost.getBoundingClientRect().bottom;
} else {
    return 500; // Default if no posts found
}
"@)

            # Scroll to just below last visible post + extra pixels
            $scrollAmount = $lastVisiblePostPosition + 100
            $global:driver.ExecuteScript("window.scrollBy(0, $scrollAmount);")
            Write-Host "Initial scroll: Scrolled down $scrollAmount pixels to position just below the last visible post. Waiting for content to load..."
            Start-Sleep -Seconds 20
        }
        catch {
            # Fallback to a simpler scroll if the position calculation fails
            $global:driver.ExecuteScript("window.scrollBy(0, 1200);")
            Write-Host "Initial scroll: Performed fallback scroll of 1200 pixels. Waiting for content to load..."
            Start-Sleep -Seconds 20
        }
    
        while (($targetPostNumber -le 10) -and ($scrollAttempt -lt $maxScrollAttempts) -and ($noChangeCount -lt 3)) {
            # Try multiple times to find the post before scrolling again
            $checkAttempt = 0
            $found = $false
        
            while (($checkAttempt -lt $maxCheckAttemptsBeforeScroll) -and (-not $found)) {
                # Try to find the target post
                try {
                    # Search using the third strategy
                    $allHeaders = $global:driver.FindElementsByTagName("h2") | Where-Object {
                        $global:driver.ExecuteScript("return arguments[0].offsetParent !== null;", $_)
                    }                    
                
                    foreach ($header in $allHeaders) {
                        try {
                            $text = $header.Text
                            if ($text -match "Feed post number $targetPostNumber") {
                                $visible = $global:driver.ExecuteScript("return arguments[0].offsetParent !== null;", $header)
                                if (-not $visible) {
                                    Write-Host "Found header for post #$targetPostNumber but it is not visible yet."
                                    continue
                                }
                                # Found the target post!
                                $found = $true
                                Write-Host "Found post #$($targetPostNumber) on check attempt $($checkAttempt + 1)!"
                            
                                # Get the container for this post (reusing ancestry paths)
                                $postElement = $null
                                $ancestryPaths = @(
                                    "./ancestor::div[contains(@class, 'feed-shared-update-v2')]",
                                    "./ancestor::div[@role='article']",
                                    "./ancestor::div[contains(@class, 'relative') and contains(@class, 'artdeco-card')]"
                                )
                            
                                foreach ($path in $ancestryPaths) {
                                    try {
                                        $postElement = $header.FindElementByXPath($path)
                                        if ($postElement) {
                                            Write-Host "Found container for post #$($targetPostNumber)"
                                            # Add to your collection if needed
                                            break
                                        }
                                    }
                                    catch {
                                        # Continue to next path
                                    }
                                }
                            
                                # Update target and reset counter
                                $highestPostSeen = $targetPostNumber
                                $targetPostNumber = $highestPostSeen + 1
                                $noChangeCount = 0
                                Write-Host "Now looking for post #$($targetPostNumber)..."
                            
                                if ($highestPostSeen -eq 10) {
                                    $targetFound = $true
                                    Write-Host "Found target post #10!"
                                    break
                                }
                            
                                break
                            }
                        }
                        catch {
                            # Continue checking other headers
                        }
                    }
                
                    if (-not $found) {
                        # Post not found this attempt
                        $checkAttempt++
                        Write-Host "Check attempt $($checkAttempt)/$($maxCheckAttemptsBeforeScroll): Post #$($targetPostNumber) not found yet..."
                        Start-Sleep -Seconds 20
                    }
                }
                catch {
                    Write-Host "Error while checking for post #$($targetPostNumber): $_"
                    $checkAttempt++
                    Start-Sleep -Seconds 20
                }
            }
        
            # If we still haven't found the post after all check attempts, scroll more
            if (-not $found) {
                Write-Host "Post #$($targetPostNumber) not found after $maxCheckAttemptsBeforeScroll check attempts. Scrolling more..."
            
                # Scroll more aggressively each time
                try {
                    $scrollDistance = 1000 + ($scrollAttempt * 300)  # Increase scroll distance each attempt
                    $global:driver.ExecuteScript("window.scrollBy(0, $scrollDistance);")
                    Write-Host "Scrolled down $scrollDistance pixels. Waiting for content to load..."
                    Start-Sleep -Seconds 20
                }
                catch {
                    Write-Host "Error during scroll: $_"
                }
            
                $noChangeCount++
                $scrollAttempt++
            
                if ($noChangeCount -ge 3) {
                    Write-Host "No new posts found after 3 scroll attempts. Stopping search."
                }
            }
        }
    
        if ($highestPostSeen -ge 10) {
            Write-Host "Successfully found at least 10 posts!"
        }
        else {
            Write-Host "Found $highestPostSeen posts before stopping."
        }
    }
    # After either finding post #10 or reaching max scroll attempts, save the full HTML
    Write-Host "Saving full page HTML..."

    $resultMessage = if ($targetFound) {
        "Found_post_10"
    }
    elseif ($noChangeCount -ge 3) {
        "No_new_posts_after_$highestPostSeen"
    }
    else {
        "Reached_max_scrolls_at_$highestPostSeen"
    }

    # Get the entire page source
    $fullHtml = $global:driver.PageSource

    # Save the HTML to file
    $fullHtml | Out-File $postsHtmlPath -Encoding UTF8

    Write-Host "Successfully saved full page HTML to: $postsHtmlPath"
}