function Get-ProfileName {
    param(
        [Parameter(Mandatory=$true)]
        $driver,
        
        [Parameter(Mandatory=$false)]
        [int]$global:maxRetries,
        
        [Parameter(Mandatory=$false)]
        [int]$retryDelay = 1000
    )

    Write-Host "Starting profile name extraction..." -ForegroundColor Cyan
    
    # Get the page title from the browser
    $pageTitle = $driver.Title
    Write-Host "Page title retrieved: '$pageTitle'" -ForegroundColor Yellow
    
    # METHOD 1: Extract name from LinkedIn ACTIVITY page title
    # Searches in: Browser page title for pattern "(123) Activity | Name | LinkedIn"
    if ($pageTitle -match '\(\d+\)\s*Activity\s*\|\s*([^|]+)\s*\|') {
        $name = $matches[1].Trim()
        Write-Host "Profile name extracted from activity pattern: '$name'" -ForegroundColor Green
        return $name
    }
    
    # METHOD 2: Extract name from LinkedIn GENERAL page titles
    # Searches in: Browser page title for pattern "Name | LinkedIn" or "Name | Title | LinkedIn"
    if ($pageTitle -match '\|\s*([^|]+)\s*\|\s*LinkedIn') {
        $name = $matches[1].Trim()
        if ($name -ne "Activity") {
            Write-Host "Profile name extracted from alternative title pattern: '$name'" -ForegroundColor Green
            return $name
        }
    }
    
    # METHOD 3: Extract name from H3 element on the LinkedIn page
    # Searches in: HTML page content for H3 element with class 'single-line-truncate'
    Write-Host "Attempting to extract name from H3 element..." -ForegroundColor Yellow
    try {
        $h3Element = $driver.FindElementByXPath("//h3[contains(@class, 'single-line-truncate')]")
        if ($h3Element) {
            $name = $h3Element.Text.Trim()
            Write-Host "Profile name extracted from H3 element: '$name'" -ForegroundColor Green
            return $name
        }
    } catch {
        Write-Host "H3 element extraction failed: $_" -ForegroundColor Red
    }
    
    # METHOD 4: Extract name from LinkedIn profile URL
    # Searches in: Browser URL for pattern "linkedin.com/in/profile-id" and converts to readable name
    Write-Host "Using fallback method: extracting name from URL..." -ForegroundColor Yellow
    try {
        $currentUrl = $driver.Url
        Write-Host "Current URL: $currentUrl" -ForegroundColor Gray
        if ($currentUrl -match 'linkedin\.com\/in\/([^/]+)') {
            $profileId = $matches[1]
            Write-Host "Profile ID from URL: '$profileId'" -ForegroundColor Gray
            
            # Convert profile ID to readable name format
            $profileId = $profileId -replace '-', ' '
            $nameParts = $profileId.Split(' ')
            $formattedName = ($nameParts | ForEach-Object { 
                if ($_.Length -gt 0) {
                    (Get-Culture).TextInfo.ToTitleCase($_) 
                }
            }) -join ' '
            
            Write-Host "Profile name formatted from URL: '$formattedName'" -ForegroundColor Green
            return $formattedName
        }
    } catch {
        Write-Host "URL extraction failed: $_" -ForegroundColor Red
    }
    
    # METHOD 5: Final fallback when all extraction methods fail
    # Returns: Hardcoded default name to prevent script failure
    Write-Host "All name extraction methods failed. Using fallback name." -ForegroundColor Red
    return "Unknown Profile"
}

# Function to construct the full folder path for storing scraped data
function Get-FolderPath {
    param(
        [Parameter(Mandatory=$true)]
        $driver,
        
        [Parameter(Mandatory=$false)]
        [string]$baseFolder = "_logs",
        
        [Parameter(Mandatory=$false)]
        [string]$category = "Activity"
    )
    
    Write-Host "Starting folder path construction..." -ForegroundColor Cyan
    Write-Host "Base folder: '$baseFolder', Category: '$category'" -ForegroundColor Gray
    
    # Extract profile name using the Get-ProfileName function
    try {
        $profileName = Get-ProfileName -driver $driver
        $global:personName = $profileName
        Write-Host "Successfully extracted profile name: '$profileName'" -ForegroundColor Green
    } catch {
        Write-Host "Error extracting profile name: $_" -ForegroundColor Red
        $global:personName = "Unknown Profile"
        Write-Host "Using fallback profile name: '$global:personName'" -ForegroundColor Yellow
    }
    
    # Create the complete folder structure for storing scraped data
    Write-Host "Building folder structure..." -ForegroundColor Yellow
    try {
        # Sanitize profile name for use as folder name (remove invalid characters)
        $folderName = $global:personName -replace '[\\\/\:\*\?\"\<\>\|]', '_'
        Write-Host "Sanitized folder name: '$folderName'" -ForegroundColor Gray
        
        # Generate timestamp for unique folder identification
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
        Write-Host "Timestamp for folder: '$timestamp'" -ForegroundColor Gray
        
        # Build complete folder hierarchy: _logs/ProfileName/Timestamp/Category/
        $basePath = Join-Path -Path (Get-Location) -ChildPath "_logs"
        $personPath = Join-Path -Path $basePath -ChildPath $folderName
        $datePath = Join-Path -Path $personPath -ChildPath $timestamp
        $categoryPath = Join-Path -Path $datePath -ChildPath $category
        $filePath = Join-Path -Path $categoryPath -ChildPath "LatestPosts.html"
        
        # Create directory structure if it doesn't exist
        if (-not (Test-Path $basePath)) {
            Write-Host "Creating base logs directory..." -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $basePath -Force | Out-Null
        }
        if (-not (Test-Path $personPath)) {
            Write-Host "Creating person directory: '$folderName'..." -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $personPath -Force | Out-Null
        }
        if (-not (Test-Path $datePath)) {
            Write-Host "Creating date directory: '$timestamp'..." -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $datePath -Force | Out-Null
        }
        if (-not (Test-Path $categoryPath)) {
            Write-Host "Creating category directory: '$category'..." -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $categoryPath -Force | Out-Null
        }
        
        Write-Host "Successfully created complete folder structure!" -ForegroundColor Green
        Write-Host "Full path: '$filePath'" -ForegroundColor Cyan
        
        # Return structured path information
        return @{
            BasePath = $basePath
            PersonPath = $personPath
            DatePath = $datePath
            CategoryPath = $categoryPath
            FilePath = $filePath
        }
        
    } catch {
        Write-Host "Error creating folder structure: $_" -ForegroundColor Red
        Write-Host "Attempting emergency fallback path creation..." -ForegroundColor Yellow
        
        # Create emergency fallback paths when normal path construction fails
        $folderName = $global:personName -replace '[\\\/\:\*\?\"\<\>\|]', '_'
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
        $emergencyPath = Join-Path -Path (Get-Location) -ChildPath "_logs\${folderName}\${timestamp}\Activity"
        $emergencyFile = Join-Path -Path $emergencyPath -ChildPath "LatestPosts.html"
        
        Write-Host "Emergency path: '$emergencyPath'" -ForegroundColor Gray
        
        if (-not (Test-Path $emergencyPath)) {
            New-Item -ItemType Directory -Path $emergencyPath -Force | Out-Null
            Write-Host "Emergency directory structure created successfully!" -ForegroundColor Green
        }
        
        # Return the emergency fallback paths
        Write-Host "Returning emergency fallback path structure" -ForegroundColor Yellow
        return @{
            CategoryPath = $emergencyPath
            FilePath = $emergencyFile
        }
    }
}