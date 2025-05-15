$network = "linkedin"
$networkUri = "https://www.{0}.com/" -F $network

# Base Profile URL
$networkProfile = "{0}{1}" -F $networkUri, "in/"

#Profiles to scrap
$profileUsernames = @()
$profilesPath = "./users.txt"
Get-Content $profilesPath | ForEach-Object {
    if($_ -match "^#") {
        return
    }
    $profileUsernames += $_
}

$global:networkProfiles = foreach ($username in $profileUsernames) {
    "{0}{1}/recent-activity/all/" -F $networkProfile, $username
}

$global:socialNetwork = [PSCustomObject]@{
    Name = $network
    Uri = $networkUri
    Profile = $networkProfile
    Cookies = "Services/{0}_cookies.csv" -F $network
}

$global:scrappingSection = "posts"

# $global:cookiePath = "Services/linkedin_cookies.csv"
# $global:socialNetwork.Cookies = "Services/linkedin_cookies.csv"

#Retry policy
$global:maxRetries = 20
