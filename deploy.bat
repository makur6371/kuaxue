@echo off
cd /d D:\project\aistu\kuaxue

echo [0/3] Bumping version...
powershell -Command "$f='pubspec.yaml'; $c=Get-Content $f -Raw; if($c -match 'version:\s*(\d+\.\d+\.\d+)\+(\d+)'){ $v=$matches[1]; $n=[int]$matches[2]+1; $c=$c -replace 'version:\s*\d+\.\d+\.\d+\+\d+', ('version: {0}+{1}' -f $v,$n); Set-Content $f $c -NoNewline; Write-Host ('  Version: {0}+{1}' -f $v,$n) } else { Write-Host '  Failed to parse version' }"

echo [1/3] Building release APK...
call flutter build apk --release
if errorlevel 1 (
    echo Build failed!
    exit /b 1
)

echo [2/3] Uploading to server...
scp -P 2222 -i D:\key\cc.pem build\app\outputs\flutter-apk\app-release.apk root@106.53.160.23:/opt/kuaxue-server/uploads/kuaxue.apk
if errorlevel 1 (
    echo Upload failed!
    exit /b 1
)

echo [3/3] Registering version in database...
for /f "tokens=*" %%i in ('powershell -Command "$c=Get-Content pubspec.yaml -Raw; if($c -match ''version:\s*(\d+\.\d+\.\d+)\+(\d+)''){ Write-Host $matches[2] }"') do set BUILD_NUM=%%i
for /f "tokens=*" %%i in ('powershell -Command "$c=Get-Content pubspec.yaml -Raw; if($c -match ''version:\s*(\d+\.\d+\.\d+)\+(\d+)''){ Write-Host $matches[1] }"') do set VER_NAME=%%i
ssh -p 2222 -i D:\key\cc.pem root@106.53.160.23 "cd /opt/kuaxue-server && node -e \"const db=require('./db'); db.prepare('INSERT INTO app_versions(version_code,version_name,changelog,apk_url,is_force) VALUES(%BUILD_NUM%,\\'v%VER_NAME%\\',\\'自动构建\\',\\'/api/app/download\\',0)').run(); console.log('Registered v%VER_NAME%+%BUILD_NUM%')\""

echo Done! APK deployed.
