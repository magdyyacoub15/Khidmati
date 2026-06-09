@echo off
echo Updating Web Icons...
copy /Y "assets\icon2.png" "web\favicon.png"
copy /Y "assets\icon2.png" "web\icons\Icon-192.png"
copy /Y "assets\icon2.png" "web\icons\Icon-512.png"
copy /Y "assets\icon2.png" "web\icons\Icon-maskable-192.png"
copy /Y "assets\icon2.png" "web\icons\Icon-maskable-512.png"
echo Icons Updated Successfully!
