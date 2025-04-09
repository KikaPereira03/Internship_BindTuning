# ---------------------------------------------
# Function: Find-LatestHtmlFile
# Purpose:  Locate the most recent Full_HTML.html in the base folder
# ---------------------------------------------
function Find-LatestHtmlFile($baseFolder) {
    $file = Get-ChildItem -Path $baseFolder -Recurse -Filter "Full_HTML.html" |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    return $file
}

# ---------------------------------------------
# Function: CreateSectionsFolder
# Purpose:  Create the "Sections" folder if it doesn't exist
# ---------------------------------------------
function CreateSectionsFolder($basePath) {
    $folder = "$basePath/Sections"
    if (!(Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder | Out-Null
        Write-Host "Created Sections folder: $folder"
    }
    return $folder
}

# ---------------------------------------------
# Function: BelongsExcludeSection
# Purpose:  Check if a section should be excluded based on known patterns
# ---------------------------------------------
function BelongsExcludeSection($html) {
    foreach ($pattern in $excludePatterns) {
        if ($html -match $pattern) {
            return $true
        }
    }
    return $false
}

# ---------------------------------------------
# Function: Get-SectionName
# Purpose:  Extract and clean a name for each section based on headers or fallback patterns
# ---------------------------------------------
function Get-SectionName($sectionValue, [ref]$counter) {
    if ($sectionValue -match '<img[^>]*title="[^"]+[a-zA-Z]+"[^>]*src="https://media\.licdn\.com/dms/image/[^"]+"[^>]*alt="[^"]+[a-zA-Z]+"' -and 
        $sectionValue -match '<h1[^>]*class="[^"]*inline t-24[^"]*"') {
        return "ProfileSummary"
    }

    $titleMatch = [regex]::Match($sectionValue, '<h2[^>]*class="[^"]*pvs-header__title[^"]*"[^>]*>.*?<span[^>]*>(.*?)</span>', "Singleline")
    if (-not $titleMatch.Success) {
        $titleMatch = [regex]::Match($sectionValue, '<h2[^>]*>(.*?)</h2>', "Singleline")
    }

    $rawTitle = $titleMatch.Success ? $titleMatch.Groups[1].Value : "Untitled$($counter.Value++)"

    $cleanTitle = $rawTitle -replace '<.*?>|<!---->', '' -replace '[^\w\s]', '' -replace '\s+', '_'
    $cleanTitle = $cleanTitle -replace '^_+|_+$', ''

    switch ($cleanTitle) {
        "Licenses_amp_certifications" { $cleanTitle = "Licenses_certifications" }
        "Honors_amp_awards"           { $cleanTitle = "Honors_awards" }
        "Sales_insights"              { $cleanTitle = "Sales_Insights" }
    }

    if ($cleanTitle.Length -lt 2) {
        $cleanTitle = "Untitled$($counter.Value++)"
    }

    if ($cleanTitle -match "^(.+?)(\1)+$") {
        $cleanTitle = $matches[1]
    }

    return $cleanTitle
}

# ---------------------------------------------
# Function: Save-SectionToFile
# Purpose:  Save a section to a unique HTML file, avoiding duplicates
# ---------------------------------------------
function Save-SectionToFile($sectionValue, $sectionName, $folder, $processed) {
    $baseName = $sectionName
    $dup = 1
    while ($processed.ContainsKey($sectionName)) {
        $sectionName = "${baseName}_$dup"
        $dup++
    }
    $processed[$sectionName] = $true

    $path = "$folder/$sectionName.html"
    $sectionValue | Set-Content -Path $path -Encoding UTF8
    Write-Host "Extracted: $sectionName -> $path"
}

# ---------------------------------------------
# MAIN EXECUTION
# Purpose:  Coordinates the full extraction and saving process
# ---------------------------------------------
$excludePatterns = @(
    'ad-banner-container',
    'class="[^"]*browsemap_recommendation[^"]*"',
    'class="[^"]*pymk_recommendation[^"]*"',
    'class="[^"]*company_recommendation[^"]*"',
    'More profiles for you',
    'People you may know',
    'You might like',
    'Advertisement',
    '(?i)>Explore Premium profiles<'
)

$baseFolder = "/Users/kikapereira/Desktop/PS1/"
$latestHtmlFile = Find-LatestHtmlFile $baseFolder

if (-not $latestHtmlFile) {
    Write-Host "No Full_HTML.html file found in any profile folder!" -ForegroundColor Red
    Exit 1
}

$latestFolder = $latestHtmlFile.DirectoryName
Write-Host "Found latest Full_HTML.html in: $latestFolder"
$sectionsFolder = CreateSectionsFolder $latestFolder

$htmlContent = Get-Content $latestHtmlFile.FullName -Raw
$sections = [regex]::Matches($htmlContent, '<section[^>]*class="[^"]*artdeco-card[^"]*"[^>]*>.*?</section>', "Singleline")

if ($sections.Count -eq 0) {
    Write-Host "No sections found in the profile HTML." -ForegroundColor Yellow
    Exit 1
}

$processedSections = @{}
$counter = 1
foreach ($section in $sections) {
    $sectionValue = $section.Value
    if (BelongsExcludeSection $sectionValue) { continue }

    $sectionName = Get-SectionName $sectionValue ([ref]$counter)
    Save-SectionToFile $sectionValue $sectionName $sectionsFolder $processedSections
}

Write-Host "Section extraction completed successfully!"
