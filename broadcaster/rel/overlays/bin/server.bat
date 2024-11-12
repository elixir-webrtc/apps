if "%DISTRIBUTION_MODE%"=="k8s" (
  set RELEASE_DISTRIBUTION=name
  set RELEASE_NODE="broadcaster@%POD_IP%"
)

set PHX_SERVER=true
call "%~dp0\broadcaster" start
