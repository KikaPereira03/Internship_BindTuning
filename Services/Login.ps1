function Login-Network {
    param (
        [string]$network
    )

    # Config files
    . .\_Configs\credentials.ps1
    . .\_Configs\scrappingsettings.ps1

    # Try cookie-based login first
    $loggedInWithCookies = $false

    if (Test-Path $global:socialNetwork.Cookies) {
        try {
            Write-Host "Trying login using saved cookies..."
            $global:driver.Navigate().GoToUrl($global:socialNetwork.Uri)

            # Load and apply cookies
            $cookieList = Import-Csv -Path $global:socialNetwork.Cookies
            $cookieList | ForEach-Object {
                try {
                    $cookie = New-Object OpenQA.Selenium.Cookie($_.Name, $_.Value, $_.Domain, $_.Path, $null)
                    $global:driver.Manage().Cookies.AddCookie($cookie)
                }
                catch {
                    Write-Warning "Could not add cookie: $($_.Name)"
                }
            }

            # Refresh to apply cookies
            $global:driver.Navigate().Refresh()

            # Retry mechanism to confirm login by detecting "Start a post" section
            $retryCount = 0
            $loggedInWithCookies = $false
    
            while ($retryCount -lt $global:maxRetries) {
                try {
                    # Wait for the "Start a post" section to confirm the feed is loaded
                    $postBox = $global:driver.FindElementByXPath("//button[contains(@class, 'artdeco-button')]
                                                       //span[contains(@class, 'artdeco-button__text')]
                                                       //strong[contains(text(), 'Start a post') or contains(text(), 'Comece uma publicação')]")
                    if ($postBox.Displayed) {
                        $loggedInWithCookies = $true
                        break
                    }
                }
                catch {
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
            Write-Host "Cookie-based login failed. Will try manual login."
        }
    }

    # Manual login fallback
    if (-not $loggedInWithCookies) {
        try {
            Write-Host "Navigating to LinkedIn login page..."
            $global:driver.Navigate().GoToUrl("$($global:socialNetwork.Uri)login")
    
            # Wait for login fields
            $wait = New-Object OpenQA.Selenium.Support.UI.WebDriverWait($global:driver, [TimeSpan]::FromSeconds(10))
    
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
    
            $loginButton = $global:driver.FindElementByXPath("//button[@type='submit']")
            $global:driver.ExecuteScript("arguments[0].click();", $loginButton)
    
            Write-Host "Waiting for LinkedIn feed page..."
    
            # Retry mechanism to confirm login by detecting "Start a post" section
            $retryCount = 0
            $isLoggedIn = $false
    
            while ($retryCount -lt $global:maxRetries) {
                try {
                    # Wait for the "Start a post" section to confirm the feed is loaded
                    $postBox = $global:driver.FindElementByXPath("//button[contains(@class, 'artdeco-button')]
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
                # throw "Login failed!"
                return $false
            }
    
            # Save cookies if login successful
            $currentUrl = $global:driver.Url
            if ($currentUrl -like "*feed*") {
                $cookieList = Get-SeCookie -Driver $global:driver
                $cookieList | Export-Csv -Path $global:socialNetwork.Cookies -NoTypeInformation
                Write-Host "Cookies Saved"
            }
        }
        catch {
            Write-Host "Login failed: $_" -ForegroundColor Red
            $global:driver.Quit()
            return $false
            # Exit 1
        }
    }

    return $true
}