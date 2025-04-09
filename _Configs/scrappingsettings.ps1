#Profile top scrap
$socialNetwork = "https://www.linkedin.com"
$profileUrl = $socialNetwork + "/in/carlos-miguel-silva/"

$contentSelectors = @{
    "Latest Posts" = "//li[.//div[contains(@class, 'fie-impression-container')]]"
}


#Retry policy
$maxRetries = 20
$cookiePath = "./linkedin_cookies.csv"


function Scroll-ToLimit {
    param (
        [string]$itemXPath = "//h2[contains(text(), 'Feed post number')]",
        [int]$minItems = 10,
        [int]$maxScrolls = 20
    )

    $scrollCount = 0
    $staleCount = 0
    $maxStale = 3
    $lastCount = 0

    while ($scrollCount -lt $maxScrolls) {
        $elements = $driver.FindElementsByXPath($itemXPath)
        $currentCount = $elements.Count

        if ($currentCount -ge $minItems) {
            Write-Host "Found $currentCount headers after $scrollCount scrolls."
            break
        }

        if ($currentCount -eq $lastCount) {
            $staleCount++
            Write-Host "No new posts loaded. Stale count: $staleCount"
            if ($staleCount -ge $maxStale) {
                Write-Host "Max stale scrolls reached. Stopping."
                break
            }
        } else {
            $staleCount = 0
        }

        $lastCount = $currentCount

        Write-Host "Scroll $scrollCount - Found $currentCount headers. Scrolling..."
        $driver.ExecuteScript("window.scrollTo(0, document.body.scrollHeight);")
        Start-Sleep -Seconds 10
        $scrollCount++
    }

    return $driver.FindElementsByXPath($itemXPath)
}
