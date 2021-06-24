Function Concat-Video{
#Automate FFMPEG concatenation

param([string]$Name,$Path,$Destination)
#Add ffmepg to system path or use this alias to make subsequent commands easier to read
New-Alias -Name ffmpeg -Value "C:\Program Files\ffmpeg\bin\ffmpeg.exe"
$videos = gci $path

#Create the "list file"
New-Item -Name mylist.txt -ItemType File -Path $path
$videos.Name | %{Add-Content -Path "$path\mylist.txt" -Value "file '$path\$_'"}

#Feedback num of videos 
Write-Host ""(Get-Content $path\mylist.txt).Count"" -NoNewline -ForegroundColor Yellow ;   "videos added to the list"
sleep 1
Write-host "Starting in 3..." -NoNewline; sleep 1; Write-Host "2..." -NoNewline; sleep 1; Write-Host "1"; sleep 1

#The final ffmpeg command
ffmpeg -f concat -safe 0 -i $path\mylist.txt -c copy $Destination\$name
}