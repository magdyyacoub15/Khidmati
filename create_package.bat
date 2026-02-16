@echo off
echo ==========================================================
echo   Creating join_group.tar.gz for Appwrite Deployment
echo ==========================================================
echo.
tar -czf join_group.tar.gz -C functions/join_group .
echo.
echo ==========================================================
echo   DONE!
echo   Please upload 'join_group.tar.gz' to Appwrite Console.
echo ==========================================================
pause
