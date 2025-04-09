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
                        $isVisible = $driver.ExecuteScript("window.scrollBy(0, 1000);")
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

Write-Host "Beginning scrolling to find post #10..."

$maxScrollAttempts = 15
$scrollAttempt = 0
$targetFound = $false
$noChangeCount = 0

# First, check what posts we already have
try {
    $initialPosts = $driver.ExecuteScript(@"
const headers = Array.from(document.querySelectorAll('h2'))
              .filter(h => h.textContent.includes('Feed post number'))
              .map(h => h.textContent.trim());
return headers;
"@)
    
    Write-Host "Initial scan found $($initialPosts.Count) posts:"
    
    # Extract post numbers and find the highest one
    $highestPostSeen = 0
    
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
} catch {
    Write-Host "Error during initial post scan: $_"
    $highestPostSeen = 0
}

# Now begin scrolling if needed
while (-not $targetFound -and $scrollAttempt -lt $maxScrollAttempts -and $noChangeCount -lt 3) {
    # Perform gentle, incremental scrolling
    try {
        Write-Host "Scroll attempt $($scrollAttempt + 1). Performing gentle scroll..."
        
        # Find the position of the last visible post
        $lastVisiblePostPosition = $driver.ExecuteScript(@"
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
        
        # Scroll just enough to see a bit more content (about 2 posts worth)
        $driver.ExecuteScript("window.scrollBy(0, $lastVisiblePostPosition);")
        Write-Host "Scrolled to position after the last visible post. Waiting for content to load..."
        Start-Sleep -Seconds 5
    } catch {
        Write-Host "Error during scroll attempt: $_"
        # Fallback to a small scroll if the position-based scroll fails
        $driver.ExecuteScript("window.scrollBy(0, 800);")
        Write-Host "Performed fallback scroll. Waiting for content to load..."
        Start-Sleep -Seconds 5
    }
    
    # Check for new posts after scrolling
    $foundNewPostsAfterScroll = $false
    $checkAttempts = 0
    $maxCheckAttempts = 3
    
    while (-not $foundNewPostsAfterScroll -and $checkAttempts -lt $maxCheckAttempts -and -not $targetFound) {
        try {
            # Log what post numbers we currently have
            $currentPosts = $driver.ExecuteScript(@"
const headers = Array.from(document.querySelectorAll('h2'))
              .filter(h => h.textContent.includes('Feed post number'))
              .map(h => h.textContent.trim());
return headers;
"@)
            
            Write-Host "Check attempt $($checkAttempts + 1) after scroll $($scrollAttempt + 1). Found $($currentPosts.Count) posts."
            
            # Extract post numbers and find the highest one
            $postNumbers = @()
            $currentHighest = $highestPostSeen
            
            foreach ($post in $currentPosts) {
                if ($post -match "Feed post number (\d+)") {
                    $number = [int]$matches[1]
                    $postNumbers += $number
                    Write-Host "  - $post (Post #$number)"
                    
                    if ($number -gt $highestPostSeen) {
                        $highestPostSeen = $number
                        $foundNewPostsAfterScroll = $true
                        Write-Host "  --> New post found: #$number" 
                    }
                    
                    if ($number -eq 10) {
                        $targetFound = $true
                    }
                }
            }
            
            if ($foundNewPostsAfterScroll) {
                Write-Host "New posts found! Previous highest: #$currentHighest, New highest: #$highestPostSeen"
                break  # Exit the check loop since we found new posts
            } else {
                Write-Host "No new posts found on check attempt $($checkAttempts + 1). Waiting more time..."
                Start-Sleep -Seconds 5  # Wait 5 more seconds and check again
            }
        } catch {
            Write-Host "Error during check attempt $($checkAttempts + 1): $_"
        }
        
        $checkAttempts++
    }
    
    if ($targetFound) {
        Write-Host "Found Feed post number 10! Stopping scrolling."
        break
    }
    
    # Check if we've gotten any new posts after all our check attempts
    if (-not $foundNewPostsAfterScroll) {
        $noChangeCount++
        Write-Host "No new posts found after $maxCheckAttempts checks. Stale count: $noChangeCount"
        
        if ($noChangeCount -ge 3) {
            Write-Host "Max stale scrolls reached. Stopping."
            break
        }
    } else {
        $noChangeCount = 0  # Reset if we found new posts
    }
    
    $scrollAttempt++
}

# After either finding post #10 or reaching max scroll attempts, save the full HTML
Write-Host "Saving full page HTML..."

$resultMessage = if ($targetFound) {
    "Found_post_10"
} elseif ($noChangeCount -ge 3) {
    "No_new_posts_after_$highestPostSeen"
} else {
    "Reached_max_scrolls_at_$highestPostSeen"
}

# Get the entire page source
$fullHtml = $driver.PageSource

# Create the output path
$fullHtmlPath = Join-Path $dateFolderPath "LinkedIn_Posts_$resultMessage.html"

# Save the HTML to file
$fullHtml | Out-File $fullHtmlPath -Encoding UTF8

Write-Host "Successfully saved full page HTML to: $fullHtmlPath"