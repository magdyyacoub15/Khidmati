@echo off
echo Adding new updates...
git add .
echo Committing changes...
set /p msg="Enter commit message (or press Enter for default): "
if "%msg%"=="" set msg="Auto update from computer"
git commit -m "%msg%"
echo Pushing to GitHub...
git push origin master
echo Done!
pause
