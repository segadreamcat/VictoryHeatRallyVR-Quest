# Victory Heat Rally VR - Quest standalone installer.
# Builds the Quest app on YOUR PC from YOUR copy of the game, then installs it on your headset over USB.
# Nothing from the game is downloaded or included in this package.
param(
 [string]$GameDirectory = 'C:\Program Files (x86)\Steam\steamapps\common\Victory Heat Rally',
 [string]$UndertaleModCli = (Join-Path $PSScriptRoot 'tools\UndertaleModCli\UndertaleModCli.exe'),
 [string]$DriverArtwork = '',
 [string]$Adb = '',
 [switch]$BuildOnly
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$build = Join-Path $root 'build'
New-Item -ItemType Directory -Path $build -Force | Out-Null
function Step($t) { Write-Host ''; Write-Host "== $t" -ForegroundColor Cyan }

# 1. Game data: the supported Steam build (the PC VR mod's backup is used if that mod is installed).
Step 'Checking your game files'
$expected = '2F7161D6250C42FE9AD72F078C2E41C035125C19694D5E41A9B456EB8E20F680'
if (!(Test-Path -LiteralPath $GameDirectory)) { throw "Game folder not found: $GameDirectory  (pass -GameDirectory 'your folder')" }
$data = Join-Path $GameDirectory 'data.win'
if (!(Test-Path -LiteralPath $data) -or (Get-FileHash -LiteralPath $data).Hash -ne $expected) {
  $backup = Join-Path $GameDirectory '.vhrvr-backup\data.win'
  if ((Test-Path -LiteralPath $backup) -and (Get-FileHash -LiteralPath $backup).Hash -eq $expected) { $data = $backup; Write-Host 'Using the original data.win saved by the PC VR mod.' }
  else { throw 'Unsupported or modified data.win. Verify the game files in Steam (Properties > Installed Files > Verify) and try again.' }
}
Write-Host "Game data OK: $data"

# 2. Tools.
Step 'Checking tools'
if (!(Test-Path -LiteralPath $UndertaleModCli)) { throw "UndertaleModCli not found at $UndertaleModCli. Download UndertaleModTool's CLI (Windows) from https://github.com/UnderminersTeam/UndertaleModTool/releases and extract it to tools\UndertaleModCli\ (keep the whole folder together)." }
$py = $null
foreach ($c in @(@('py','-3'), @('python'))) { try { & $c[0] $c[1..9] --version *> $null; if ($LASTEXITCODE -eq 0) { $py = $c; break } } catch {} }
if (!$py) { throw 'Python 3 not found. Install it from https://www.python.org/downloads/ (tick "Add python.exe to PATH") and run this again.' }
function Py { & $py[0] $py[1..9] @args; if ($LASTEXITCODE -ne 0) { throw "Python step failed: $args" } }
Py -m pip install --quiet --disable-pip-version-check cryptography pillow
if (!$Adb) {
  $cand = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe' } else { '' }
  if ($cand -and (Test-Path $cand)) { $Adb = $cand }
  elseif (Test-Path (Join-Path $root 'tools\platform-tools\adb.exe')) { $Adb = Join-Path $root 'tools\platform-tools\adb.exe' }
  elseif (Get-Command adb -ErrorAction SilentlyContinue) { $Adb = (Get-Command adb).Source }
}
if (!$BuildOnly -and !$Adb) { throw 'adb not found. Download Android SDK Platform-Tools from https://developer.android.com/tools/releases/platform-tools and extract it to tools\platform-tools\.' }

# 3. OpenXR loader (Khronos, Apache-2.0) from Maven Central.
$aar = Join-Path $build 'openxr_loader_for_android-1.1.63.aar'
if (!(Test-Path $aar)) {
  Step 'Downloading the OpenXR loader'
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -UseBasicParsing 'https://repo1.maven.org/maven2/org/khronos/openxr/openxr_loader_for_android/1.1.63/openxr_loader_for_android-1.1.63.aar' -OutFile $aar
}

# 4. Driver hands/wheel art (not included: see README). The PC VR mod installs the same file.
if (!$DriverArtwork) { $guess = Join-Path $GameDirectory 'VHR-driver.png'; if (Test-Path $guess) { $DriverArtwork = $guess } }
$paint = Join-Path $build 'vhrpaint'
if ($DriverArtwork) {
  Step 'Preparing driver art (gloves and sleeves for every car)'
  if (Test-Path $paint) { Remove-Item -Recurse -Force $paint }
  Py (Join-Path $root 'quest\tools\gen_driver_art.py') --art $DriverArtwork --out $paint
} else { Write-Warning 'No driver artwork (VHR-driver.png): the cockpit will have no hands or steering wheel. See README.' }

# 5. Patch the game data for the Quest.
Step 'Patching game data (takes a minute)'
$droid = Join-Path $build 'game.droid'
$old = $env:VHRVR_PACKAGE
try {
  $env:VHRVR_PACKAGE = $root
  & $UndertaleModCli load $data -s (Join-Path $root 'quest\Patch-Quest.csx') -o $droid -f *> (Join-Path $build 'patch.log')
  if ($LASTEXITCODE -ne 0 -or !(Test-Path $droid) -or (Select-String -LiteralPath (Join-Path $build 'patch.log') -Pattern 'Script execution failed|Compile errors occurred' -Quiet)) { throw 'Patching failed. See build\patch.log.' }
} finally { $env:VHRVR_PACKAGE = $old }

# 6. Build and sign the APK (your own signing key is created at first run: %USERPROFILE%\.vhrquest-key.pem).
Step 'Building VHRQuest.apk'
$apk = Join-Path $build 'VHRQuest.apk'
$bargs = @((Join-Path $root 'quest\build_apk.py'), '--runner', (Join-Path $root 'runner\gamemaker-runner-2024.8.apk'), '--data', $droid, '--game', $GameDirectory,
          '--lib', (Join-Path $root 'bin\libvhrvr.so'), '--dex', (Join-Path $root 'bin\VHRQuest.dex'), '--loader', $aar, '--out', $apk)
if (Test-Path $paint) { $bargs += @('--extra', $paint) }
Py @bargs
if ($BuildOnly) { Write-Host ''; Write-Host "Built: $apk" -ForegroundColor Green; Write-Host 'Personal use only: it contains your copy of the game. Do not share it.'; exit }

# 7. Install over USB.
Step 'Installing on the headset'
& $Adb start-server *> $null
$devices = (& $Adb devices) -match "`tdevice$"
if (!$devices) { throw 'No headset found. Plug it in, enable Developer Mode, put it on and allow USB debugging ("Always allow"), then run this again.' }
$out = & $Adb install -r $apk 2>&1 | Out-String
Write-Host $out
if ($out -notmatch 'Success') {
  if ($out -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') { throw 'A copy signed by someone else is installed. Uninstall "VHR Quest" from the headset first (Library > Unknown Sources), then run this again. Your save data on the headset is removed with it.' }
  throw 'Install failed (see the message above).'
}
Write-Host ''
Write-Host 'Installed! Put the headset on: Library > Unknown Sources > VHR Quest.' -ForegroundColor Green
