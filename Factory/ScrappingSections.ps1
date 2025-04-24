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

    #Variables
    $postsUrl = $global:socialNetwork.Profile + "recent-activity/all/"

    $pageLoaded = $false
    $postElements = @()
    $limit = 10
    $highestPostSeen = 0
    $targetFound = $false
    $maxScrollAttempts = 10
    $maxCheckAttemptsBeforeScroll = 10
    $found = $false


    Write-Host "Navigating to posts page: $postsUrl"

    try {
        $global:driver.Navigate().GoToUrl($postsUrl)
        Start-Sleep -Seconds 2
    
        $retryCount = 0
        $pageLoaded = $false
        $noPosts = $false
    
        while ($retryCount -lt $global:maxRetries) {
            try {
                # First check if the page has loaded with the empty state message
                try {
                    $emptyContainer = $global:driver.FindElementByXPath("//div[contains(@class, 'scaffold-finite-scroll__empty')]")
                    if ($emptyContainer -and $emptyContainer.Displayed) {
                        $pageLoaded = $true
                        $noPosts = $true
                        Write-Host "Posts page loaded, but no posts are available." -ForegroundColor Yellow
                        break
                    }
                } catch {
                    # No empty state found, continue checking for posts
                }
                
                # Check for posts if no empty state was found
                $postItem = $global:driver.FindElementByXPath("//div[contains(@class, 'scaffold-finite-scroll__content')]//ul/li")
                if ($postItem.Displayed) {
                    $pageLoaded = $true
                    Write-Host "Posts found on the page." -ForegroundColor Green
                    break
                }
            }
            catch {
                Write-Host "Retry $($retryCount + 1): Posts content not yet loaded..."
            }
    
            Start-Sleep -Seconds 2
            $retryCount++
        }
    
        if ($pageLoaded) {
            Write-Host "Posts page loaded successfully." -ForegroundColor Green
            
            # Use the Get-FolderPath function regardless of whether there are posts
            $paths = Get-FolderPath -driver $driver -baseFolder "_logs" -category "Activity"
            $categoryFolderPath = $paths.CategoryPath
            $postsHtmlPath = $paths.FilePath
            
            # If no posts were found, create a file with the empty state message
            if ($noPosts) {
                Write-Host "No posts found for this profile." -ForegroundColor Yellow
                $noPostsHtml = "<html><head><meta charset='UTF-8'><title>No Posts Found</title></head><body><h1>Nothing to see for now</h1><p>This profile has no activity posts.</p></body></html>"
                $noPostsHtml | Out-File $postsHtmlPath -Encoding UTF8
                Write-Host "Created empty posts file at: $postsHtmlPath"
            
                return
            }
        } else {
            Write-Host "Error: Could not confirm that the posts page loaded." -ForegroundColor Red
            return
        }
    } catch {
        Write-Host "Error navigating to the posts page: $_" -ForegroundColor Red
        return
    }

    # Use the Get-FolderPath function
    $paths = Get-FolderPath -driver $driver -baseFolder "_logs" -category "Activity"
    $categoryFolderPath = $paths.CategoryPath
    $postsHtmlPath = $paths.FilePath

    #Find Post Elements by Headers
    Write-Host "Attempting to find posts by 'Feed post number' headers..."
    try {
        # Try finding headers with exact class and content
        $feedPostHeaders = $global:driver.FindElementsByXPath("//h2[@class='visually-hidden' and contains(text(), 'Feed post number')]")
        Write-Host "Found $($feedPostHeaders.Count) feed post headers (class and content match)."

        # If no exact matches, try with just the content
        if ($feedPostHeaders.Count -eq 0) {
            $feedPostHeaders = $global:driver.FindElementsByXPath("//h2[contains(text(), 'Feed post number')]")
            Write-Host "Found $($feedPostHeaders.Count) feed post headers (content match only)."

            # If still no results, perform a more exhaustive search
            if ($feedPostHeaders.Count -eq 0) {
                $allHeaders = $global:driver.FindElementsByTagName("h2")
                Write-Host "Found $($allHeaders.Count) total h2 elements on the page. Examining each..."
                foreach ($header in $allHeaders) {
                    try {
                        $text = $header.Text
                        if ($text -match "Feed post number") {
                            # Check if the element is visible
                            $isVisible = $global:driver.ExecuteScript("return arguments[0].offsetParent !== null;", $header)
                            if ($isVisible) {
                                Write-Host "Found a visible header with text: '$text'."
                                $feedPostHeaders += $header # Add the visible header to our collection
                            }
                            else {
                                Write-Host "Found a header with text: '$text', but it is not currently visible."
                            }
                        }
                    }
                    catch {
                        Write-Host "Error examining header: $_"
                    }
                }
            }
        }

        # Extract post elements if visible headers are found
        if ($feedPostHeaders.Count -gt 0) {
            foreach ($header in $feedPostHeaders) {
                # Define potential XPath paths to the post container
                $ancestryPaths = @(
                    "./ancestor::div[contains(@class, 'feed-shared-update-v2')]",
                    "./ancestor::div[@role='article']",
                    "./ancestor::div[contains(@class, 'relative') and contains(@class, 'artdeco-card')]"
                )

                foreach ($path in $ancestryPaths) {
                    try {
                        $postElement = $header.FindElementByXPath($path)
                        if ($postElement) {
                            $postElements += $postElement
                            Write-Host "Found post container using path: '$path'."
                            break 
                        }
                    }
                    catch {
                        # Continue to the next path if the current one fails
                    }
                }
                if (-not $postElement) {
                    Write-Host "Warning: Could not find a post container for a visible header."
                }
            }

            if ($postElements.Count -gt 0) {
                Write-Host "Successfully found $($postElements.Count) complete posts based on visible headers." -ForegroundColor Green

                # Save a limited number of posts
                $limitToSave = [Math]::Min($limit, $postElements.Count)
                $htmlOutput = "<html><head><meta charset='UTF-8'><title>Posts By Headers</title></head><body>"

                for ($i = 0; $i -lt $limitToSave; $i++) {
                    try {
                        $html = $postElements[$i].GetAttribute("outerHTML")
                        if ($html) {
                            $htmlOutput += $html
                            Write-Host "Added post $($i + 1) to output."
                        }
                    }
                    catch {
                        Write-Host "Error reading post $($i + 1): $_"
                    }
                }

                $htmlOutput += "</body></html>"
                $htmlOutput | Out-File $postsHtmlPath -Encoding UTF8
                Write-Host "Saved $limitToSave posts to: $postsHtmlPath."
            }
            else {
                Write-Host "Warning: Could not find any post containers associated with the identified visible headers."
            }
        }
    }
    catch {
        Write-Host "Error trying to find posts by headers: $_"
    }

    #Scroll to Find More Posts
    Write-Host "Beginning scrolling to find at least 10 posts..."

    # Initial scan for existing post numbers
    try {
        $initialPosts = $global:driver.ExecuteScript(@"
            const headers = Array.from(document.querySelectorAll('h2'))
                              .filter(h => h.textContent.includes('Feed post number'))
                              .map(h => h.textContent.trim());
            return headers;
"@)

        foreach ($post in $initialPosts) {
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

        if ($targetFound) {
            Write-Host "Post #10 is already visible. Skipping further scrolling for now."
        }
    } catch {
        Write-Host "Error during initial post scan: $_"
    }

    # Scroll and check for more posts if target not found
    if (-not $targetFound) {
        $targetPostNumber = $highestPostSeen + 1
        $scrollAttempt = 0
        $noChangeCount = 0

        Write-Host "Looking for post #$targetPostNumber..."

        # Initial scroll to load more content
        try {
            $lastVisiblePostPosition = $global:driver.ExecuteScript(@"
                const headers = Array.from(document.querySelectorAll('h2'))
                                  .filter(h => h.textContent.includes('Feed post number'))
                                  .filter(h => h.offsetParent !== null);
                if (headers.length > 0) {
                    const lastPost = headers[headers.length - 1];
                    return lastPost.getBoundingClientRect().bottom;
                } else {
                    return 500;
                }
"@)
            $scrollAmount = $lastVisiblePostPosition + 50
            $global:driver.ExecuteScript("window.scrollBy(0, $scrollAmount);")
            Write-Host "Initial scroll: Scrolled down $scrollAmount pixels. Waiting for content..." -ForegroundColor Yellow
            Start-Sleep -Seconds 20
        } catch {
            $global:driver.ExecuteScript("window.scrollBy(0, 1200);")
            Write-Host "Initial scroll: Fallback scroll performed. Waiting for content..."
            Start-Sleep -Seconds 20
        }

        while (($targetPostNumber -le 10) -and ($scrollAttempt -lt $maxScrollAttempts) -and ($noChangeCount -lt 3)) {
            $found = $false
            for ($checkAttempt = 1; ($checkAttempt -le $maxCheckAttemptsBeforeScroll) -and (-not $found); $checkAttempt++) {
                try {
                    $allHeaders = $global:driver.FindElementsByTagName("h2")
                    foreach ($header in $allHeaders) {
                        $text = $header.Text
                        if ($text -match "Feed post number $targetPostNumber") {
                            # Check for visibility
                            $isVisible = $global:driver.ExecuteScript("return arguments[0].offsetParent !== null;", $header)
                            if ($isVisible) {
                                Write-Host "Found visible post #$targetPostNumber on check attempt $checkAttempt."
                                $highestPostSeen = $targetPostNumber
                                $targetPostNumber = $highestPostSeen + 1
                                $noChangeCount = 0
                                $found = $true
                                Write-Host "Now looking for post #$targetPostNumber..."
                                if ($highestPostSeen -eq 10) {
                                    $targetFound = $true
                                    Write-Host "Found target post #10!"
                                    break
                                }
                                break
                            } else {
                                Write-Host "Found post #$targetPostNumber, but it is not currently visible." -ForegroundColor Red                            }
                        }
                    }
                    if (-not $found) {
                        Write-Host "Check attempt $checkAttempt/${maxCheckAttemptsBeforeScroll}: Post #$targetPostNumber not found or not visible."
                        Start-Sleep -Seconds 10 # Reduced sleep time between checks
                    }
                } catch {
                    Write-Host "Error checking for post #${targetPostNumber}: $_"
                    Start-Sleep -Seconds 10
                }
            }

            if (-not $found) {
                Write-Host "Post #$targetPostNumber not found or not visible after $maxCheckAttemptsBeforeScroll checks. Scrolling more..."
                try {
                    $scrollDistance = 1000 + ($scrollAttempt * 300)
                    $global:driver.ExecuteScript("window.scrollBy(0, $scrollDistance);")
                    Write-Host "Scrolled down $scrollDistance pixels."
                    Start-Sleep -Seconds 20
                } catch {
                    Write-Host "Error during scroll: $_"
                }
                $noChangeCount++
                $scrollAttempt++
                if ($noChangeCount -ge 3) {
                    Write-Host "Warning: No new visible posts found after 3 scroll attempts. Stopping search."
                    break
                }
            }
            if ($targetFound) {
                break # Exit the while loop if target is found
            }
        }

        if ($highestPostSeen -ge 10) {
            Write-Host "Successfully found at least 10 posts." -ForegroundColor Green
        } else {
            Write-Host "Found $highestPostSeen posts through scrolling before stopping." -ForegroundColor Yellow
        }
    }

    $postsHtmlPath = Join-Path -Path $categoryFolderPath -ChildPath "LatestPosts.html"

    # Save Full Page HTML
    Write-Host "Saving the full page HTML..." 
    $fullHtml = $global:driver.PageSource
    $fullHtml | Out-File $postsHtmlPath -Encoding UTF8
    Write-Host "Successfully saved the full page HTML to: $postsHtmlPath." -ForegroundColor Cyan

    $resultMessage = if ($targetFound) {
        "Found 10 posts!"
    } elseif ($noChangeCount -ge 3) {
        "No new visible posts after $highestPostSeen"
    } else {
        "Reached max scrolls at $highestPostSeen"
    }
    Write-Host "Post scraping process finished with result: $resultMessage" -ForegroundColor Green
}