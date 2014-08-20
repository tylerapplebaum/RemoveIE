<#
Written by: Tyler Applebaum
Notes: In order for the Logging and LoggingBad functions to work, Enable-WSManCredSSP must be configured in your domain. If you choose not to do this, you can have the logging functions write to the local drive, then access that file at a later time. You will also need to remove the Authentication CredSSP from the Invoke-Command statement as well.
$Rev =  "v2.0 31 Jul 2014"
Usage: RemoveIE.ps1 -l <Path_to_computer_list.txt> -f <Get-ADComputer filter (Can use single name too)> -v <10 or 11> -r (If -r is present, target computer will reboot automatically)
#>
[CmdletBinding(DefaultParameterSetName = "Set1")]
    param(
        [Parameter(mandatory=$true, parametersetname="Set1", HelpMessage="Specify the path to the list of computer names (C:\Scripts\list.txt)")]
		[Alias("l")]
        [string]$Complist,

        [Parameter(mandatory=$true, parametersetname="Set2", HelpMessage="Specify the Get-ADComputer name filter to apply (Use * for wildcard")]
		[Alias("f")]
        [string]$Filter,
		
		[Parameter (Mandatory=$true)]
		[ValidateSet('10','11')]
		[Alias("v")]
		[int] $script:Version,
		
		[Parameter(Mandatory=$false)]
		[Alias("r")]
		[switch] $Reboot
	)
	
Write-Host @'
    ____  ________  _______ _    ________   __________
   / __ \/ ____/  |/  / __ \ |  / / ____/  /  _/ ____/
  / /_/ / __/ / /|_/ / / / / | / / __/     / // __/   
 / _, _/ /___/ /  / / /_/ /| |/ / /___   _/ // /___   
/_/ |_/_____/_/  /_/\____/ |___/_____/  /___/_____/   
                                                    
'@ -fo green

function script:Input {
	If ($Complist){
	#Get content of file specified, trim any trailing spaces and blank lines
	$script:Computers = gc ($Complist) | where {$_ -notlike $null } | foreach { $_.trim() }
	}
	Elseif ($Filter) {
		If (!(Get-Module ActiveDirectory)) {
		Import-Module ActiveDirectory
		} #include AD module
	#Filter out AD computer objects with ESX in the name
	$script:Computers = Get-ADComputer -Filter {SamAccountName -notlike "*esx*" -AND Name -Like $Filter} | select -ExpandProperty Name | sort
	}
}#end Input

function script:PingTest {
$script:TestedComps = @()
	foreach ($WS in $Computers){
	$i++
		If (Test-Connection -count 1 -computername $WS -quiet){
		$script:TestedComps += "$WS.$env:userdnsdomain" #essential to append the FQDN with WSManCredSSP
		}
		Else {
		Write-Host "Cannot connect to $WS" -ba black -fo yellow
		}
	If ($computers.count -gt '1'){
	Write-Progress -Activity "Testing connectivity" -status "Tested connection to computer $i of $($computers.count)" -percentComplete ($i / $computers.length*100)
	}
	}#end foreach
}#end PingTest

function script:Duration {
$Time = $((Get-Date)-$date)
	If ($Time.totalseconds -lt 60) {
	$dur = "{0:N3}" -f $Time.totalseconds
	Write-Host "Script completed in $dur seconds" -fo DarkGray
	}
	Elseif ($Time.totalminutes -gt 1) {
	$dur = "{0:N3}" -f $Time.totalminutes
	Write-Host "Script completed in $dur minutes" -fo DarkGray
	}
}#end Duration

$Scriptblock = {
param ($Version,$Reboot)
$date = get-date
$IE = (((gci "C:\Program Files (x86)\Internet Explorer\iexplore.exe").versioninfo).productversion) #IE version check

	Function Logging {
	$LogLocation = "\\YourServerHere\GroupShares\ITNetwork\Procedures"
	Add-Content -path $LogLocation\RemoveIE.log -value "$env:computername`t$date`tInternet Explorer $Version successfully removed`r"
	}
	
	Function LoggingBad {
	$LogLocation = "\\YourServerHere\GroupShares\ITNetwork\Procedures"
	Add-Content -path $LogLocation\RemoveIEBad.log -value "$env:computername`t$date`tInternet Explorer $Version not removed`r"
	}
	
	Function AutoReboot {
		If ($Reboot){
		Write-Host "Rebooting $env:computername now."
		shutdown /r /t 00
		}
	}

	Function RemoveIE1011 {
		If ($IE -like "$Version*"){
		Write-Host "IE$Version exists on $env:computername, removing now." -fore DarkGray
		FORFILES /P C:\Windows\servicing\Packages /M Microsoft-Windows-InternetExplorer-*$Version.*.mum /c "cmd /c echo Uninstalling package @fname && start /w pkgmgr /up:@fname /quiet /norestart"
			If ($LastExitCode -eq '0'){
			Write-Host "Internet Explorer $Version successfully removed" -fore Green
			. Logging #Call Logging function
			. AutoReboot
			}
			Else {
			Write-Host "Internet Explorer $Version not successfully removed" -fore Red
			. LoggingBad
			}#endelse
		}#end if IE
		Else {
		Write-Host "IE version detected on $env:computername was: $IE"
		}
	} #end RemoveIE

	. RemoveIE1011 #Call RemoveIE function
} #end scriptblock

$i = 0
$date = get-date
$Cred = Get-Credential $env:userdomain\$env:username
. Input #Call input function
. Pingtest #Call PingTest function
Invoke-Command -ComputerName $TestedComps -Scriptblock ${Scriptblock} -ArgumentList @($Version,$Reboot) -Credential $Cred -Authentication CredSSP
. Duration #Call duration function