# Import the Selenium module
Import-Module Selenium

# Set Chrome driver path—
$chromeDriverPath = "./_Configs/chromedriver-mac-arm64_second"

# Initialize Chrome options with additional settings
$chromeOptions = New-Object OpenQA.Selenium.Chrome.ChromeOptions
$chromeOptions.AddArguments("start-maximized")
$chromeOptions.AddArguments("--disable-blink-features=AutomationControlled")
$chromeOptions.AddArguments("--no-sandbox")
$chromeOptions.AddArguments("--disable-dev-shm-usage")
$chromeOptions.AddArguments("--disable-gpu")
$chromeOptions.AddUserProfilePreference("credentials_enable_service", $false)

# Add a user agent that looks more like a regular browser
$chromeOptions.AddArguments("user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36")

$chromeOptions.PageLoadStrategy = "none"

# Start ChromeDriver
try {
    $global:driver = New-Object OpenQA.Selenium.Chrome.ChromeDriver($chromeDriverPath, $chromeOptions)
    Write-Host "ChromeDriver started successfully"
}
catch {
    Write-Host "Failed to start ChromeDriver: $_" -ForegroundColor Red
    Exit 1
}