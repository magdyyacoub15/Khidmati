@echo off
echo ==========================================
echo      Manger App - Web Deployment Tool
echo ==========================================

echo 1. Building Web App...
if exist build\web (
    echo Cleaning old build...
    rd /s /q build\web
)
call flutter build web --release --base-href "/Khidmati/"
if %errorlevel% neq 0 (
    echo [ERROR] Build failed! Please fix errors and try again.
    pause
    exit /b %errorlevel%
)

echo 2. Preparing Deployment...
cd build\web

:: Clean previous git init if exists
if exist .git (
    rd /s /q .git
)

:: Initialize temporary git repo for deployment
git init
git checkout -b gh-pages
git add .
git commit -m "Deploy Update"
git remote add origin https://github.com/magdyyacoub15/Khidmati.git

echo 3. Uploading to GitHub Pages...
git push -f origin gh-pages

cd ..\..

echo ==========================================
echo [SUCCESS] Site updated successfully!
echo Link: https://magdyyacoub15.github.io/Khidmati/
echo (It may take 1-2 minutes to see changes)
echo [NOTE] If site is blank, try clearing browser cache (Ctrl+Shift+R)
echo ==========================================
pause
