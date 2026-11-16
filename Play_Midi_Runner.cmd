@echo off
cd /d "%~dp0"
set "PYTHON=%USERPROFILE%\AppData\Local\Python\pythoncore-3.14-64\python.exe"
if not exist "%PYTHON%" (
  echo Python 3.14 was not found on this computer.
  pause
  exit /b 1
)
"%PYTHON%" -c "import http.server, webbrowser; server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), http.server.SimpleHTTPRequestHandler); url = 'http://127.0.0.1:' + str(server.server_port) + '/index.html'; print('Game URL: ' + url + ' -- keep this window open', flush=True); webbrowser.open(url); server.serve_forever()"
if errorlevel 1 pause



