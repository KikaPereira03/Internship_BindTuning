cls

# Config files
. .\_Configs\credentials.ps1
. .\_Configs\scrappingsettings.ps1

# Import the Selenium module
Import-Module Selenium

# Set Chrome driver path—
$chromeDriverPath = "/Users/kikapereira/FEUP/3Ano/Estágio/chromedriver-mac-arm64_second/"

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
    $driver = New-Object OpenQA.Selenium.Chrome.ChromeDriver($chromeDriverPath, $chromeOptions)
    Write-Host "ChromeDriver started successfully"
}
catch {
    Write-Host "Failed to start ChromeDriver: $_" -ForegroundColor Red
    Exit 1
}

#---------------------------------------------
# LOGIN
#---------------------------------------------

# Try cookie-based login first
$loggedInWithCookies = $false

if (Test-Path $cookiePath) {
    try {
        Write-Host "Trying login using saved cookies..."
        $driver.Navigate().GoToUrl($socialNetwork)

        # Load and apply cookies
        $cookieList = Import-Csv -Path $cookiePath
        $cookieList | ForEach-Object {
            try {
                $cookie = New-Object OpenQA.Selenium.Cookie($_.Name, $_.Value, $_.Domain, $_.Path, $null)
                $driver.Manage().Cookies.AddCookie($cookie)
            }
            catch {
                Write-Warning "Could not add cookie: $($_.Name)"
            }
        }

        # Refresh to apply cookies
        $driver.Navigate().Refresh()

        # Retry mechanism to confirm login by detecting "Start a post" section
        $retryCount = 0
        $loggedInWithCookies = $false
    
        while ($retryCount -lt $maxRetries) {
            try {
                # Wait for the "Start a post" section to confirm the feed is loaded
                $postBox = $driver.FindElementByXPath("//button[contains(@class, 'artdeco-button')]
                                                       //span[contains(@class, 'artdeco-button__text')]
                                                       //strong[contains(text(), 'Start a post') or contains(text(), 'Comece uma publicação')]")
                if ($postBox.Displayed) {
                    $loggedInWithCookies = $true
                    break
                }
            }
            catch {
                Write-Host "Retry $($retryCount): Feed not fully loaded yet..."
            }
    
            # Wait before retrying
            Start-Sleep -Seconds 2
            $retryCount++
        }
    
        if ($loggedInWithCookies) {
            Write-Host "Logged in using cookies!" -ForegroundColor Green
        }
        else {
            Write-Host"Cookies didn’t work. Falling back to manual login..."
        }
    }
    catch {
        Write-Host"Cookie-based login failed. Will try manual login."
    }
}

# Manual login fallback
if (-not $loggedInWithCookies) {
    try {
        Write-Host "Navigating to LinkedIn login page..."
        $driver.Navigate().GoToUrl("$socialNetwork/login")
    
        # Wait for login fields
        $wait = New-Object OpenQA.Selenium.Support.UI.WebDriverWait($driver, [TimeSpan]::FromSeconds(10))
    
        # Random delay before interacting (mimics human behavior)
        Start-Sleep -Seconds (Get-Random -Minimum 1 -Maximum 3)
    
        Write-Host "Filling in login credentials..."
    
        #Filling Email
        $emailField = $wait.Until([OpenQA.Selenium.Support.UI.ExpectedConditions]::ElementIsVisible([OpenQA.Selenium.By]::Id("username")))
        $emailField.Clear()
        $emailField.SendKeys($loginUserName)
    
        #Filling Password
        $passwordField = $wait.Until([OpenQA.Selenium.Support.UI.ExpectedConditions]::ElementIsVisible([OpenQA.Selenium.By]::Id("password")))
        $passwordField.Clear()
        $passwordField.SendKeys($loginCredential)
    
        # Random delay before interacting (mimics human behavior)
        Start-Sleep -Seconds (Get-Random -Minimum 1 -Maximum 3)
    
        Write-Host "Clicking login button..."
    
        $loginButton = $driver.FindElementByXPath("//button[@type='submit']")
        $driver.ExecuteScript("arguments[0].click();", $loginButton)
    
        Write-Host "Waiting for LinkedIn feed page..."
    
        # Retry mechanism to confirm login by detecting "Start a post" section
        $retryCount = 0
        $isLoggedIn = $false
    
        while ($retryCount -lt $maxRetries) {
            try {
                # Wait for the "Start a post" section to confirm the feed is loaded
                $postBox = $driver.FindElementByXPath("//button[contains(@class, 'artdeco-button')]
                                                       //span[contains(@class, 'artdeco-button__text')]
                                                       //strong[contains(text(), 'Start a post') or contains(text(), 'Comece uma publicação')]")
                if ($postBox.Displayed) {
                    $isLoggedIn = $true
                    break
                }
            }
            catch {
                Write-Host "Retry $($retryCount): Feed not fully loaded yet..."
                #Exception error mesage atfer maxtries 
            }
    
            # Wait for a second before retrying
            Start-Sleep -Seconds 2
            $retryCount++
        }
    
        if ($isLoggedIn) {
            Write-Host "Login successful!" -ForegroundColor Green
        }
        else {
            throw "Login failed!"
        }
    
        # Save cookies if login successful
        $currentUrl = $Driver.Url
        if ($currentUrl -like "*feed*") {
            $cookieList = Get-SeCookie -Driver $Driver
            $cookieList | Export-Csv -Path $cookiePath -NoTypeInformation
            Write-Host "Cookies Saved"
        }
    }
    catch {
        Write-Host "Login failed: $_" -ForegroundColor Red
        $driver.Quit()
        Exit 1
    }
}

