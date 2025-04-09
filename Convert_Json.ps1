$basePath = "/Users/kikapereira/Desktop/PS1"
$latestScrape = $null

# Find the absolute latest scrape among all users
foreach ($user in Get-ChildItem $basePath -Directory) {
    $dateFolders = Get-ChildItem $user.FullName -Directory | Sort-Object Name -Descending
    if ($dateFolders.Count -gt 0) {
        $mostRecentDate = $dateFolders[0]
        $sectionsPath = Join-Path $mostRecentDate.FullName "sections"
        if (Test-Path $sectionsPath) {
            if (-not $latestScrape -or $mostRecentDate.Name -gt $latestScrape.Date.Name) {
                $latestScrape = [PSCustomObject]@{
                    UserFolder = $user.FullName
                    Date       = $mostRecentDate
                    Sections   = $sectionsPath
                }
            }
        }
    }
}

if ($latestScrape) {
    $aboutPath = Join-Path $latestScrape.Sections "About.html"
    if (Test-Path $aboutPath) {
        Write-Host "`Processing About.html for user at: $($latestScrape.UserFolder)"
        
        # Parse and convert
        Add-Type -Path "/Users/kikapereira/FEUP/3Ano/Estágio/libs/HtmlAgilityPack.dll"

        $html = Get-Content $aboutPath -Raw
        $doc = New-Object HtmlAgilityPack.HtmlDocument
        $doc.LoadHtml($html)
        $node = $doc.DocumentNode.SelectSingleNode("//div[contains(@class, 'inline-show-more-text')]")
        $text = if ($node) { $node.InnerText.Trim() } else { "" }

        $aboutJson = [PSCustomObject]@{
            section     = "About"
            description = $text
        }

        $outputPath = Join-Path $latestScrape.Sections "About.json"
        $aboutJson | ConvertTo-Json -Depth 3 | Out-File $outputPath -Encoding UTF8
        Write-Host "Saved: $outputPath"
    }
    else {
        Write-Warning "About.html not found in: $($latestScrape.Sections)"
    }

    # EXPERIENCE
    $experiencePath = Join-Path $latestScrape.Sections "Experience.html"
    if (Test-Path $experiencePath) {
        $html = Get-Content $experiencePath -Raw
        $doc = New-Object HtmlAgilityPack.HtmlDocument
        $doc.LoadHtml($html)

        $items = $doc.DocumentNode.SelectNodes("//li[contains(@class, 'artdeco-list__item')]")
        $experienceList = @()

        foreach ($item in $items) {
            # Look for nested roles under one company
            $roleItems = $item.SelectNodes(".//li[contains(@class, 'pvs-list__paged-list-item')]")
            $companyNode = $item.SelectSingleNode(".//span[contains(@class, 't-bold')]/span")
            $companyName = if ($companyNode) { $companyNode.InnerText.Trim() } else { "" }

            if ($roleItems.Count -gt 0) {
                # GROUPED ROLES UNDER ONE COMPANY
                $roles = @()

                foreach ($role in $roleItems) {
                    $titleNode = $role.SelectSingleNode(".//span[contains(@class, 't-bold')]/span")
                    $title = if ($titleNode) { $titleNode.InnerText.Trim() } else { "" }

                    $typeNode = $role.SelectSingleNode(".//span[contains(@class, 't-normal') and not(contains(@class, 'visually-hidden'))]")
                    $type = if ($typeNode) { $typeNode.InnerText.Trim() } else { "" }

                    $datesNode = $role.SelectSingleNode(".//span[contains(@class, 't-14') and contains(., '-')]/span")
                    $datesRaw = if ($datesNode) { $datesNode.InnerText.Trim() } else { "" }

                    if ($datesRaw -match "·") {
                        $parts = $datesRaw -split "·"
                        $dates = $parts[0].Trim()
                        $duration = $parts[1].Trim()
                    }
                    else {
                        $dates = $datesRaw
                        $duration = ""
                    }

                    $locationNode = $role.SelectSingleNode(".//span[contains(@class, 't-14') and not(contains(., '-')) and not(contains(., 'mo'))]/span")
                    $location = if ($locationNode) { $locationNode.InnerText.Trim() } else { "" }

                    $descNode = $role.SelectSingleNode(".//div[contains(@class, 'inline-show-more-text')]")
                    $description = if ($descNode) { $descNode.InnerText.Trim() } else { "" }

                    $roles += [PSCustomObject]@{
                        title       = $title
                        type        = $type
                        dates       = $dates
                        duration    = $duration
                        location    = $location
                        description = $description
                    }
                }

                $experienceList += [PSCustomObject]@{
                    company = $companyName
                    roles   = $roles
                }

            }
            else {
                # 🔹 SINGLE-POSITION JOB
                $titleNode = $item.SelectSingleNode(".//div[contains(@class, 't-bold')]/span")
                $title = if ($titleNode) { $titleNode.InnerText.Trim() } else { "" }

                $companyNode = $item.SelectSingleNode(".//span[contains(@class, 't-normal')]/span")
                $company = if ($companyNode) { $companyNode.InnerText.Trim() } else { "" }

                $datesNode = $item.SelectSingleNode(".//span[contains(@class, 't-14') and contains(., '-')]/span")
                $datesRaw = if ($datesNode) { $datesNode.InnerText.Trim() } else { "" }

                if ($datesRaw -match "·") {
                    $parts = $datesRaw -split "·"
                    $dates = $parts[0].Trim()
                    $duration = $parts[1].Trim()
                }
                else {
                    $dates = $datesRaw
                    $duration = ""
                }

                $locationNode = $item.SelectSingleNode(".//span[contains(@class, 't-14') and not(contains(., '-')) and not(contains(., 'mo'))]/span")
                $location = if ($locationNode) { $locationNode.InnerText.Trim() } else { "" }

                $descNode = $item.SelectSingleNode(".//div[contains(@class, 'inline-show-more-text')]")
                $description = if ($descNode) { $descNode.InnerText.Trim() } else { "" }

                $experienceList += [PSCustomObject]@{
                    title       = $title
                    company     = $company
                    dates       = $dates
                    duration    = $duration
                    location    = $location
                    description = $description
                }
            }
        }

        # ✅ Save as JSON
        $experienceJsonPath = Join-Path $latestScrape.Sections "experience.json"
        $experienceList | ConvertTo-Json -Depth 10 | Out-File $experienceJsonPath -Encoding UTF8
        Write-Host "✅ Saved: $experienceJsonPath"
    }


}
else {
    Write-Warning "No valid sections folder found across users."
}
