function Get-ProfileName {
    param(
        [Parameter(Mandatory=$true)]
        $driver,
        
        [Parameter(Mandatory=$false)]
        [int]$global:maxRetries,
        
        [Parameter(Mandatory=$false)]
        [int]$retryDelay = 1000
    )

    
    # Get the page title
    $pageTitle = $driver.Title
    Write-Host "Page Title: $pageTitle"
    
    # Extract name from activity page title pattern: "(25) Activity | Name | LinkedIn"
    if ($pageTitle -match '\(\d+\)\s*Activity\s*\|\s*([^|]+)\s*\|') {
        $name = $matches[1].Trim()
        return $name
    }
    
    # Try other title patterns
    if ($pageTitle -match '\|\s*([^|]+)\s*\|\s*LinkedIn') {
        $name = $matches[1].Trim()
        if ($name -ne "Activity") {
            Write-Host "Extracted name from alternative title pattern: '$name'"
            return $name
        }
    }
    
    try {
        $h3Element = $driver.FindElementByXPath("//h3[contains(@class, 'single-line-truncate')]")
        if ($h3Element) {
            $name = $h3Element.Text.Trim()
            Write-Host "Extracted name from H3 element: '$name'"
            return $name
        }
    } catch {
        Write-Host "H3 extraction failed: $_"
    }
    
    try {
        $currentUrl = $driver.Url
        if ($currentUrl -match 'linkedin\.com\/in\/([^/]+)') {
            $profileId = $matches[1]
            $profileId = $profileId -replace '-', ' '
            $nameParts = $profileId.Split(' ')
            $formattedName = ($nameParts | ForEach-Object { 
                if ($_.Length -gt 0) {
                    (Get-Culture).TextInfo.ToTitleCase($_) 
                }
            }) -join ' '
            
            Write-Host "Fallback: Using name from URL: '$formattedName'"
            return $formattedName
        }
    } catch {
        Write-Host "URL extraction failed: $_"
    }
    
    Write-Host "All methods failed. Using hardcoded fallback."
    return "Unknown Profile"
}

function Get-FolderPath {
    param(
        [Parameter(Mandatory=$true)]
        $driver,
        
        [Parameter(Mandatory=$false)]
        [string]$baseFolder = "_logs",
        
        [Parameter(Mandatory=$false)]
        [string]$category = "Activity"
    )
    
    # Extract profile name
    try {
        $profileName = Get-ProfileName -driver $driver
        $global:personName = $profileName
        Write-Host "Successfully extracted profile name: $profileName" -ForegroundColor Green
    } catch {
        Write-Host "Error extracting profile name: $_"
        $global:personName = "Unknown Profile" 
    }
    
    # Create folder structure
    try {
        # Format the profile name for folder use
        $folderName = $global:personName -replace '[\\\/\:\*\?\"\<\>\|]', '_'
        
        # Get current timestamp
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH:mm"
        
        # Build paths - _logs/Name/TimeStamp/Activity/LatestPosts.html
        $basePath = Join-Path -Path (Get-Location) -ChildPath "_logs"
        $personPath = Join-Path -Path $basePath -ChildPath $folderName
        $datePath = Join-Path -Path $personPath -ChildPath $timestamp
        $categoryPath = Join-Path -Path $datePath -ChildPath $category
        $filePath = Join-Path -Path $categoryPath -ChildPath "LatestPosts.html"
        
        # Create directories
        if (-not (Test-Path $basePath)) {
            New-Item -ItemType Directory -Path $basePath -Force | Out-Null
        }
        if (-not (Test-Path $personPath)) {
            New-Item -ItemType Directory -Path $personPath -Force | Out-Null
        }
        if (-not (Test-Path $datePath)) {
            New-Item -ItemType Directory -Path $datePath -Force | Out-Null
        }
        if (-not (Test-Path $categoryPath)) {
            New-Item -ItemType Directory -Path $categoryPath -Force | Out-Null
        }
        
        Write-Host "Created path structure: $filePath"
        
        # Return path information
        return @{
            BasePath = $basePath
            PersonPath = $personPath
            DatePath = $datePath
            CategoryPath = $categoryPath
            FilePath = $filePath
        }
    } catch {
        Write-Host "Error in direct path construction: $_"
        # Create emergency fallback paths
        $folderName = $global:personName -replace '[\\\/\:\*\?\"\<\>\|]', '_'
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
        $emergencyPath = Join-Path -Path (Get-Location) -ChildPath "_logs\${folderName}\${timestamp}\Activity"
        $emergencyFile = Join-Path -Path $emergencyPath -ChildPath "LatestPosts.html"
        
        if (-not (Test-Path $emergencyPath)) {
            New-Item -ItemType Directory -Path $emergencyPath -Force | Out-Null
        }
        
        # Return the emergency paths
        return @{
            CategoryPath = $emergencyPath
            FilePath = $emergencyFile
        }
    }
}