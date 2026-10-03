# Victory Heat Rally VR - Quest standalone installer (one click).
# Builds the Quest app on YOUR PC from YOUR copy of the game, then installs it on your headset over USB.
# Nothing from the game is downloaded or included in this package. The tools it needs are downloaded
# automatically on first run (UndertaleModTool CLI, Android platform-tools/adb, Khronos OpenXR loader).
param(
 [string]$GameDirectory = '',
 [string]$UndertaleModCli = '',
 [string]$Adb = '',
 [switch]$BuildOnly
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Windows PowerShell downloads crawl with the progress bar on
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$root = $PSScriptRoot
$build = Join-Path $root 'build'
$tools = Join-Path $root 'tools'
New-Item -ItemType Directory -Path $build, $tools -Force | Out-Null
function Step($t) { Write-Host ''; Write-Host "== $t" -ForegroundColor Cyan }
# Windows PowerShell 5.1 turns any stderr line from a program into a fatal error under 'Stop', so run tools under 'Continue'.
function Run([scriptblock]$b) { $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { & $b } finally { $ErrorActionPreference = $old } }
function Download($url, $file, $sha) {
  $tmp = "$file.part"
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp
  if ($sha -and (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash -ne $sha) { Remove-Item $tmp -Force; throw "Download check failed for $url (file changed or corrupted). Try again later." }
  Move-Item -LiteralPath $tmp -Destination $file -Force
}

# 1. Find the game (Steam library folders are searched automatically).
Step 'Finding Victory Heat Rally'
if (!$GameDirectory) {
  $libs = New-Object System.Collections.Generic.List[string]
  $steam = $null
  foreach ($k in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
    try { $p = Get-ItemProperty -Path $k -ErrorAction Stop; if ($p.SteamPath) { $steam = $p.SteamPath } elseif ($p.InstallPath) { $steam = $p.InstallPath }; if ($steam) { break } } catch {}
  }
  if (!$steam) { $steam = 'C:\Program Files (x86)\Steam' }
  $libs.Add($steam)
  $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
  if (Test-Path -LiteralPath $vdf) { foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs.Add($m.Groups[1].Value.Replace('\\', '\')) } }
  foreach ($l in $libs) { $g = Join-Path $l 'steamapps\common\Victory Heat Rally'; if (Test-Path -LiteralPath (Join-Path $g 'data.win')) { $GameDirectory = $g; break } }
  if (!$GameDirectory) { throw "Couldn't find Victory Heat Rally. Run it from PowerShell with your game folder:  .\Install-Quest.ps1 -GameDirectory 'D:\SteamLibrary\steamapps\common\Victory Heat Rally'" }
}
if (!(Test-Path -LiteralPath $GameDirectory)) { throw "Game folder not found: $GameDirectory" }
Write-Host "Game folder: $GameDirectory"

# 2. Game data: the supported Steam build (the PC VR mod's backup is used if that mod is installed).
Step 'Checking your game files'
$expected = '2F7161D6250C42FE9AD72F078C2E41C035125C19694D5E41A9B456EB8E20F680'
$data = Join-Path $GameDirectory 'data.win'
if (!(Test-Path -LiteralPath $data) -or (Get-FileHash -LiteralPath $data).Hash -ne $expected) {
  $backup = Join-Path $GameDirectory '.vhrvr-backup\data.win'
  if ((Test-Path -LiteralPath $backup) -and (Get-FileHash -LiteralPath $backup).Hash -eq $expected) { $data = $backup; Write-Host 'Using the original data.win saved by the PC VR mod.' }
  else { throw 'Unsupported or modified data.win. Verify the game files in Steam (Properties > Installed Files > Verify) and try again.' }
}
Write-Host 'Game data OK.'

# 3. Tools (downloaded once into tools\).
Step 'Getting tools (first run only)'
if (!$UndertaleModCli) { $UndertaleModCli = Join-Path $tools 'UndertaleModCli\UndertaleModCli.exe' }
if (!(Test-Path -LiteralPath $UndertaleModCli)) {
  Write-Host 'Downloading UndertaleModTool CLI 0.9.2.0 (about 60 MB)...'
  $zip = Join-Path $tools 'utmt-cli.zip'
  Download 'https://github.com/UnderminersTeam/UndertaleModTool/releases/download/0.9.2.0/UTMT_CLI_v0.9.2.0-Windows.zip' $zip 'E7573E45D107BE34F81F955C6E4AFC3C7C8F2628E5A6F307A871E3825B3DFB40'
  $dest = Join-Path $tools 'UndertaleModCli'
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force
  Remove-Item $zip -Force
  if (!(Test-Path -LiteralPath $UndertaleModCli)) { $f = Get-ChildItem -LiteralPath $dest -Recurse -Filter 'UndertaleModCli.exe' | Select-Object -First 1; if ($f) { $UndertaleModCli = $f.FullName } else { throw 'UndertaleModTool CLI download looks wrong (no UndertaleModCli.exe).' } }
}
Write-Host "UndertaleModTool CLI: OK"
if (!$Adb) {
  $local = Join-Path $tools 'platform-tools\adb.exe'
  $sdk = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe' } else { '' }
  if (Test-Path $local) { $Adb = $local }
  elseif ($sdk -and (Test-Path $sdk)) { $Adb = $sdk }
  elseif (Get-Command adb -ErrorAction SilentlyContinue) { $Adb = (Get-Command adb).Source }
  elseif (!$BuildOnly) {
    Write-Host 'Downloading Android platform-tools (adb) from Google...'
    $zip = Join-Path $tools 'platform-tools.zip'
    Download 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' $zip $null
    Expand-Archive -LiteralPath $zip -DestinationPath $tools -Force
    Remove-Item $zip -Force
    $Adb = $local
  }
}
if (!$BuildOnly) { if (!$Adb -or !(Test-Path -LiteralPath $Adb)) { throw 'adb download failed. Get platform-tools from https://developer.android.com/tools/releases/platform-tools and extract it into tools\.' }; Write-Host 'adb: OK' }
$aar = Join-Path $tools 'openxr_loader_for_android-1.1.63.aar'
if (!(Test-Path $aar)) {
  Write-Host 'Downloading the OpenXR loader (Khronos)...'
  Download 'https://repo1.maven.org/maven2/org/khronos/openxr/openxr_loader_for_android/1.1.63/openxr_loader_for_android-1.1.63.aar' $aar '622419D2F6741C3443A3BEB4779AF0764318EDD01830DE967F24C741EBCDED73'
}
Write-Host 'OpenXR loader: OK'

# 4. Patch the game data for the Quest.
Step 'Patching game data (takes a minute)'
$droid = Join-Path $build 'game.droid'
if (Test-Path $droid) { Remove-Item -Force $droid }
$log = Join-Path $build 'patch.log'
$env:VHRVR_PACKAGE = $root
Run { & $UndertaleModCli load $data -s (Join-Path $root 'quest\Patch-Quest.csx') -o $droid -f *> $log }
if ($LASTEXITCODE -ne 0 -or !(Test-Path $droid) -or (Select-String -LiteralPath $log -Pattern 'Script execution failed|Compile errors occurred' -Quiet)) { throw 'Patching failed. See build\patch.log.' }

# 5. Build and sign the APK: your patched data + game files, the VR bridge, the driver art (hands, gloves and
#    sleeves for every car). Your signing key is created on first run: %USERPROFILE%\.vhrquest-key.pem
Step 'Building VHRQuest.apk'
$apk = Join-Path $build 'VHRQuest.apk'
if (Test-Path $apk) { Remove-Item -Force $apk }
$home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$env:VHRQ_DATA = $droid; $env:VHRQ_GAME = $GameDirectory; $env:VHRQ_LOADER = $aar; $env:VHRQ_OUT = $apk
$env:VHRQ_KEY = Join-Path $home_ '.vhrquest-key.pem'
$blog = Join-Path $build 'build.log'
Run { & $UndertaleModCli load $droid -s (Join-Path $root 'quest\Build-Apk.csx') *> $blog }
if ($LASTEXITCODE -ne 0 -or !(Test-Path $apk) -or (Select-String -LiteralPath $blog -Pattern 'Script execution failed|Exception' -Quiet)) { throw 'Building the APK failed. See build\build.log.' }
Get-Content -LiteralPath $blog | Select-String -Pattern '^(Built|Created)' | ForEach-Object { Write-Host $_.Line }
if ($BuildOnly) { Write-Host ''; Write-Host "Built: $apk" -ForegroundColor Green; Write-Host 'Personal use only: it contains your copy of the game. Do not share it.'; exit }

# 6. Install over USB.
Step 'Installing on the headset'
Run { & $Adb start-server *> $null }
$list = Run { & $Adb devices 2>$null }
$devices = $list -match "`tdevice$"
if (!$devices) {
  if ($list -match "`tunauthorized$") { throw 'The headset is asking to allow USB debugging. Put it on, tick "Always allow from this computer", press Allow, then run this again.' }
  throw 'No headset found. Plug it in with a data USB cable, turn on Developer Mode, put it on and allow USB debugging, then run this again.'
}
Write-Host 'Copying to the headset (about 250 MB, a minute or two)...'
$out = Run { & $Adb install -r $apk 2>&1 | Out-String }
Write-Host $out
if ($out -notmatch 'Success') {
  if ($out -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') { throw 'A copy signed by someone else is installed. Uninstall "VHR Quest" from the headset first (Library > Unknown Sources), then run this again. Your save data on the headset is removed with it.' }
  throw 'Install failed (see the message above).'
}
Write-Host ''
Write-Host 'Installed! Put the headset on: Library > Unknown Sources > VHR Quest.' -ForegroundColor Green
