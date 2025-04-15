

#Profile top scrap
$network = "linkedin"
$networkUri = "https://www.{0}.com/" -F $network
$networkProfile = "{0}{1}" -F $networkUri, "in/carlos-miguel-silva/"

$global:socialNetwork = [PSCustomObject]@{
    Name = $network
    Uri = $networkUri
    Profile = $networkProfile
    Cookies = "Services/{0}/cookies.csv" -F $network
}
$global:scrappingSection = "posts"

#Retry policy
$global:maxRetries = 20
$global:socialNetwork.Cookies = "Services/linkedin_cookies.csv"
