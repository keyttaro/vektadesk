param([Parameter(Mandatory=$true)][string]$Installer)
$ErrorActionPreference = 'Stop'
$exe = Join-Path $env:ProgramFiles 'VektaDesk\VektaDesk.exe'
$started = Get-Date
$install = Start-Process (Resolve-Path $Installer).Path -ArgumentList '--silent-install' -PassThru
try {
    $deadline = (Get-Date).AddMinutes(3)
    do {
        Start-Sleep 2
        $service = Get-CimInstance Win32_Service -Filter "Name='VektaDesk'"
    } until (($service -and $service.State -eq 'Running' -and (Test-Path $exe)) -or (Get-Date) -gt $deadline)
    if (!(Test-Path $exe)) { throw "Installed executable missing: $exe" }
    foreach ($file in @('librustdesk.dll','flutter_windows.dll','data\icudtl.dat','data\flutter_assets')) {
        if (!(Test-Path (Join-Path (Split-Path $exe) $file))) { throw "Missing runtime asset: $file" }
    }
    if (!$service -or $service.State -ne 'Running' -or $service.PathName -notlike "*VektaDesk.exe*") {
        throw "Service not running with the expected executable"
    }
    $shell = New-Object -ComObject WScript.Shell
    foreach ($link in @(
        "$env:PUBLIC\Desktop\VektaDesk.lnk",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\VektaDesk\VektaDesk.lnk"
    )) {
        if (!(Test-Path $link)) { throw "Shortcut missing: $link" }
        if ($shell.CreateShortcut($link).TargetPath -ine $exe) { throw "Wrong shortcut target: $link" }
    }
    # Start from another working directory, as a desktop shortcut would.
    $gui = Start-Process $exe -WorkingDirectory $env:TEMP -PassThru
    Start-Sleep 15
    $gui.Refresh()
    if ($gui.HasExited) { throw "Installed GUI exited early with code $($gui.ExitCode)" }
    if (!$gui.Responding -or $gui.MainWindowHandle -eq 0) { throw "Installed GUI has no responding window" }
    Write-Host 'PASS: installed executable, runtime assets, service, shortcuts and GUI.'
} catch {
    Get-ChildItem (Split-Path $exe) -ErrorAction SilentlyContinue | Select-Object Name,Length
    Get-WinEvent -FilterHashtable @{LogName='Application';StartTime=$started} -ErrorAction SilentlyContinue |
        Where-Object {$_.ProviderName -in @('Application Error','Windows Error Reporting')} |
        Select-Object -First 5 TimeCreated,Message | Format-List
    throw
}
