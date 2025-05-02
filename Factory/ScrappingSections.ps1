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
        [Parameter(Mandatory)]
        [string]$Profile)

    $postsUrl = $Profile
    Write-Host "Navigating to posts page: $postsUrl"

    $result = Navigate-ToPostsPage -url $postsUrl
    if (-not $result.PageLoaded) {
        Write-Host "Error: Could not load posts page." -ForegroundColor Red
        return
    }

    $paths = Get-FolderPath -driver $global:driver -baseFolder "_logs" -category "Activity"
    $postsHtmlPath = $paths.FilePath
    $categoryFolderPath = $paths.CategoryPath

    if ($result.NoPosts) {
        Save-NoPostsHtml -path $postsHtmlPath
        return
    }

    $headers = Get-VisibleFeedPostHeaders
    $postElements = Extract-PostContainers -headers $headers
    Save-PostsToFile -posts $postElements -limit 10 -path $postsHtmlPath

    $highestSeen = Scan-VisiblePostNumbers
    if ($highestSeen -lt 10) {
        $highestSeen = Scroll-ToFindMorePosts -startFrom $highestSeen
    }

    Save-FullPageHtml -path (Join-Path $categoryFolderPath "LatestPosts.html")
}

function Navigate-ToPostsPage {
    param([string]$url)
    
    Write-Host "Starting navigation to $url" -ForegroundColor Cyan
    $global:driver.Navigate().GoToUrl($url)
    
    # Log current URL and wait for initial load
    try {
        $currentUrl = $global:driver.Url
        Write-Host "Current URL after navigation: $currentUrl" -ForegroundColor Gray
    } catch {}
    
    Write-Host "Waiting 5 seconds for initial page load..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
    
    # CRITICAL FIX: Force setting maxRetries to ensure it's recognized
    if (-not $global:maxRetries -or $global:maxRetries -le 0) {
        $global:maxRetries = 20
        Write-Host "Reset maxRetries to 20" -ForegroundColor Yellow
    }
    
    Write-Host "Beginning retry loop with $global:maxRetries max attempts..." -ForegroundColor Magenta
    
    # Use a do-while loop instead to guarantee at least one iteration
    $attemptCount = 0
    do {
        $attemptCount += 1
        Write-Host "LOOP ITERATION: Attempt $attemptCount of $global:maxRetries" -ForegroundColor Magenta
        
        # Check for empty container
        try {
            $emptyContainer = $global:driver.FindElementByXPath("//div[contains(@class, 'scaffold-finite-scroll__empty')]")
            if ($emptyContainer -and $emptyContainer.Displayed) {
                Write-Host "Found empty posts container." -ForegroundColor Yellow
                return @{ PageLoaded = $true; NoPosts = $true }
            }
        } catch {
            Write-Host "No empty container found in attempt $attemptCount" -ForegroundColor Gray
        }
        
        # Check for post items
        try {
            $postItem = $global:driver.FindElementByXPath("//div[contains(@class, 'scaffold-finite-scroll__content')]//ul/li")
            if ($postItem.Displayed) {
                Write-Host "Found post container." -ForegroundColor Green
                return @{ PageLoaded = $true; NoPosts = $false }
            }
        } catch {
            Write-Host "No post items found in attempt $attemptCount" -ForegroundColor Gray
        }
        
        # Try alternative selectors
        try {
            $alternateSelectors = @(
                "//div[@role='article']",
                "//div[contains(@class, 'feed-shared-update-v2')]",
                "//div[contains(@class, 'artdeco-card')]//div[contains(@class, 'feed-shared-actor')]"
            )
            
            foreach ($selector in $alternateSelectors) {
                try {
                    $element = $global:driver.FindElementByXPath($selector)
                    if ($element -and $element.Displayed) {
                        Write-Host "Found post using alternate selector: $selector" -ForegroundColor Green
                        return @{ PageLoaded = $true; NoPosts = $false }
                    }
                } catch {}
            }
        } catch {}
        
        # Add an explicit wait before next iteration
        if ($attemptCount -lt $global:maxRetries) {
            Write-Host "Waiting 3 seconds before next attempt..." -ForegroundColor Gray
            Start-Sleep -Seconds 3
        }
    } while ($attemptCount -lt $global:maxRetries)
    
    Write-Host "All $attemptCount attempts completed without finding elements." -ForegroundColor Red
    return @{ PageLoaded = $false; NoPosts = $false }
}

function Save-NoPostsHtml {
    param([string]$path)

    $html = "<html><head><meta charset='UTF-8'><title>No Posts Found</title></head><body><h1>Nothing to see for now</h1><p>This profile has no activity posts.</p></body></html>"
    $html | Out-File $path -Encoding UTF8
    Write-Host "Created empty posts file at: $path"
}

function Get-VisibleFeedPostHeaders {
    $visibleHeaders = @()
    $headers = $global:driver.FindElementsByTagName("h2")

    foreach ($header in $headers) {
        try {
            $text = $header.Text
            if ($text -match "Feed post number") {
                $isVisible = $global:driver.ExecuteScript("return arguments[0].offsetParent !== null;", $header)
                if ($isVisible) {
                    $visibleHeaders += $header
                }
            }
        }
        catch {}
    }

    return $visibleHeaders
}

function Extract-PostContainers {
    param([Parameter(Mandatory)] [array]$headers)

    $postElements = @()
    foreach ($header in $headers) {
        $paths = @(
            "./ancestor::div[contains(@class, 'feed-shared-update-v2')]",
            "./ancestor::div[@role='article']",
            "./ancestor::div[contains(@class, 'relative') and contains(@class, 'artdeco-card')]"
        )

        foreach ($path in $paths) {
            try {
                $element = $header.FindElementByXPath($path)
                if ($element) {
                    $postElements += $element
                    break
                }
            }
            catch {}
        }
    }

    return $postElements
}

function Save-PostsToFile {
    param(
        [array]$posts,
        [int]$limit,
        [string]$path
    )

    $limit = [Math]::Min($limit, $posts.Count)
    $html = "<html><head><meta charset='UTF-8'><title>Posts</title></head><body>"

    for ($i = 0; $i -lt $limit; $i++) {
        try {
            $html += $posts[$i].GetAttribute("outerHTML")
        }
        catch {}
    }

    $html += "</body></html>"
    $html | Out-File $path -Encoding UTF8
}

function Scan-VisiblePostNumbers {
    $highest = 0
    $foundPostNumbers = @()

    Write-Host "Looking for initially loaded posts..." 

    try {
        $headers = $global:driver.ExecuteScript(@"
            return Array.from(document.querySelectorAll('h2'))
                        .filter(h => h.textContent.includes('Feed post number'))
                        .map(h => h.textContent.trim());
"@)

        foreach ($text in $headers) {
            if ($text -match "Feed post number (\d+)") {
                $num = [int]$matches[1]
                $foundPostNumbers += $num
                if ($num -gt $highest) { $highest = $num }
            }
        }

        if ($foundPostNumbers.Count -gt 0) {
            Write-Host "Found posts: $($foundPostNumbers -join ", ")" -ForegroundColor Cyan
        } else {
            Write-Host "No initially loaded posts found."
        }
    } catch {
        Write-Host "Error scanning initial post numbers: $_"
    }

    return $highest
}

function Scroll-ToFindMorePosts {
    param(
        [int]$highestSeen,
        [int]$maxScrolls = 3,
        [int]$maxChecks = 10,
        [int]$targetPost = 10
    )

    $scrollAttempt = 0
    $noChangeCount = 0
    $targetFound = $false
    $foundPosts = @()

    Write-Host "Scrolling more until target ($targetPost) is met..."

    try {
        $scrollAmount = $global:driver.ExecuteScript(@"
            const headers = Array.from(document.querySelectorAll('h2'))
                .filter(h => h.textContent.includes('Feed post number'))
                .filter(h => h.offsetParent !== null);
            if (headers.length > 0) {
                const last = headers[headers.length - 1];
                return last.getBoundingClientRect().bottom + 50;
            }
            return 500;
"@)
        $global:driver.ExecuteScript("window.scrollBy(0, $scrollAmount);")
        Start-Sleep -Seconds 20
    } catch {
        $global:driver.ExecuteScript("window.scrollBy(0, 1200);")
        Start-Sleep -Seconds 20
    }

    while (($highestSeen -lt $targetPost) -and ($scrollAttempt -lt $maxScrolls) -and ($noChangeCount -lt 3)) {
        $found = $false

        for ($check = 1; $check -le $maxChecks -and -not $found; $check++) {
            try {
                $allHeaders = $global:driver.FindElementsByTagName("h2")
                foreach ($header in $allHeaders) {
                    if ($header.Text -match "Feed post number (\d+)") {
                        $num = [int]$matches[1]
                        if ($num -eq ($highestSeen + 1)) {
                            $visible = $global:driver.ExecuteScript("return arguments[0].offsetParent !== null;", $header)
                            if ($visible) {
                                $highestSeen = $num
                                $foundPosts += $num
                                $found = $true
                                if ($highestSeen -eq $targetPost) {
                                    Write-Host "Target met! Found post #$targetPost." -ForegroundColor Green
                                    $targetFound = $true
                                    break
                                }
                            }
                        }
                    }
                }
            } catch {
                Write-Host "Error during check: $_"
            }

            if (-not $found) {
                Start-Sleep -Seconds 10
            }
        }

        if (-not $found) {
            try {
                $scrollDistance = 1000 + ($scrollAttempt * 300)
                $global:driver.ExecuteScript("window.scrollBy(0, $scrollDistance);")
                Start-Sleep -Seconds 20
            } catch {}
            $noChangeCount++
            $scrollAttempt++
        }

        if ($targetFound) { break }
    }

    if ($foundPosts.Count -gt 0) {
        Write-Host "Found posts: $($foundPosts -join ", ")"
    }
    Write-Host "Scrolling complete." 
    return $highestSeen
}

function Convert-HTMLToJSON {
    param(
        [string]$htmlPath
    )

    Write-Host "Converting HTML to JSON..." -ForegroundColor Cyan
    
    try {
        # Get the directory where the HTML file is located
        $outputFolder = Split-Path -Parent $htmlPath
        
        # Path to your Python script
        $pythonScript = Join-Path $PSScriptRoot "CreateJSON.py"
        
        # Run the Python script with the HTML file as input
        python $pythonScript $htmlPath $outputFolder
        
        # Check if conversion was successful
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully converted HTML to JSON. Output saved to: $outputFolder" -ForegroundColor Green
        } else {
            Write-Host "Error converting HTML to JSON. Exit code: $LASTEXITCODE" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "Exception occurred during HTML to JSON conversion: $_" -ForegroundColor Red
    }
}

function Save-FullPageHtml {
    param([string]$path)

    try {
        $html = $global:driver.PageSource
        $html | Out-File $path -Encoding UTF8
        Write-Host "Saved full HTML to: $path" -ForegroundColor Cyan
        
        Convert-HTMLToJSON -htmlPath $path
    } catch {
        Write-Host "Error saving full HTML: $_" -ForegroundColor Red
    }
}