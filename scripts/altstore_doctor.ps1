# AltStore/AltServer 자동 진단 (Windows PowerShell 5.1 이상, 관리자 권한 불필요)
# 실행: 저장소 맨 위의 'AltStore 진단.cmd' 더블클릭, 또는
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\altstore_doctor.ps1 [-ErrorText "오류 문구"]
# 결과: 화면 출력 + .validation-tools\altstore-doctor\latest.txt (Claude/Codex가 읽어 원인 판단)
# 읽기 전용: 서비스·프로그램을 바꾸거나 Apple ID·토큰을 다루지 않는다. 접속 확인은 인증 없는 HEAD 요청만 보낸다.
[CmdletBinding()]
param(
    [string]$ErrorText = $null,
    [int]$TimeoutSec = 8,
    [switch]$NoPrompt
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$repoRoot = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $repoRoot '.validation-tools\altstore-doctor'
$lines = New-Object System.Collections.Generic.List[string]
$findings = New-Object System.Collections.Generic.List[object]

function Say([string]$text, [string]$color = 'Gray') {
    $lines.Add($text)
    Write-Host $text -ForegroundColor $color
}
function Mark([bool]$ok) { if ($ok) { '[OK]  ' } else { '[문제]' } }
function Add-Finding([int]$priority, [string]$cause, [string[]]$steps) {
    $findings.Add([pscustomobject]@{ Priority = $priority; Cause = $cause; Steps = $steps })
}

if (-not $ErrorText -and -not $NoPrompt) {
    try { $ErrorText = Read-Host 'iPad AltStore에 뜬 오류 문구를 붙여 넣으세요 (없으면 Enter)' } catch { $ErrorText = '' }
}

Say "=== AltStore 진단 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" 'Cyan'
if ($ErrorText) { Say "입력한 오류: $ErrorText" }

# ---------- 1. 프로그램·서비스 ----------
Say ''
Say '[1] 노트북 프로그램·서비스' 'Cyan'
$procs = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName })
$altServer = $procs -contains 'AltServer'
$iTunes = ($procs -contains 'iTunes') -or ($procs -contains 'iTunesHelper')
$iCloud = @($procs | Where-Object { $_ -match '^iCloud' }).Count -gt 0
Say "$(Mark $altServer) AltServer 실행 중: $altServer"
Say "$(Mark $iTunes) iTunes(또는 iTunesHelper) 실행 중: $iTunes"
Say "$(Mark $iCloud) iCloud 실행 중: $iCloud"
if (-not $altServer) { Add-Finding 1 'AltServer가 꺼져 있음' @('시작 메뉴에서 AltServer 실행 → 작업 표시줄 오른쪽 트레이에 다이아몬드 아이콘이 보이는지 확인') }
if (-not $iTunes) { Add-Finding 3 'iTunes가 실행 중이 아님 (기기 인식·Wi-Fi 동기화에 필요)' @('iTunes를 한 번 실행해 둔다(창은 최소화해도 됨)') }
if (-not $iCloud) { Add-Finding 3 'iCloud가 실행 중이 아님 (Apple ID 인증 정보 생성에 필요)' @('iCloud를 실행하고 같은 Apple ID로 로그인되어 있는지 확인') }

$storeApps = @()
try { $storeApps = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'AppleInc\.(iTunes|iCloud)' } | ForEach-Object { $_.Name }) } catch {}
if ($storeApps.Count -gt 0) {
    Say "[문제] Microsoft Store판 설치 감지: $($storeApps -join ', ')" 'Yellow'
    Add-Finding 2 'Microsoft Store판 iTunes/iCloud는 AltServer와 호환되지 않음' @('Store판 iTunes·iCloud 제거', 'Apple 홈페이지(apple.com/itunes/download/win64, iCloud Windows 웹 설치판)에서 받아 다시 설치')
} else { Say '[OK]   Microsoft Store판 iTunes/iCloud 없음' }

foreach ($svcName in @('Apple Mobile Device Service', 'Bonjour Service')) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if (-not $svc) { $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $svcName } | Select-Object -First 1 }
    $running = $svc -and $svc.Status -eq 'Running'
    $state = if ($svc) { $svc.Status } else { '설치 안 됨' }
    Say "$(Mark $running) $svcName : $state"
    if (-not $running) { Add-Finding 2 "$svcName 이(가) 실행 중이 아님" @("Win+R → services.msc → '$svcName' 시작(안 보이면 iTunes 재설치)") }
}

# ---------- 2. USB 기기 ----------
Say ''
Say '[2] USB로 연결된 iPad/iPhone' 'Cyan'
$pnp = @()
try { $pnp = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Apple Mobile Device|Apple iPad|Apple iPhone|^iPad|^iPhone' }) } catch {}
$broken = @($pnp | Where-Object { $_.Status -ne 'OK' })
if ($pnp.Count -gt 0) {
    foreach ($d in ($pnp | Sort-Object FriendlyName -Unique)) { Say "$(Mark ($d.Status -eq 'OK')) $($d.FriendlyName) ($($d.Status))" }
} else {
    Say '[참고] USB로 연결된 Apple 기기 없음 (USB로 연결했다면 인식 실패)' 'Yellow'
    Add-Finding 2 'USB로 연결한 iPad를 노트북이 인식하지 못함 (iTunes에 iPad가 안 보이는 상태)' @(
        'iPad 잠금 해제 상태로 케이블 재연결 → "이 컴퓨터 신뢰" → 암호 입력',
        '노트북 본체의 다른 USB 포트, 데이터 전송 가능한 다른 케이블로 시도',
        'iTunes 완전 종료 → services.msc에서 Apple Mobile Device Service 다시 시작 → iTunes 다시 실행',
        '신뢰 창이 안 뜨면 iPad 설정 → 일반 → 전송 또는 재설정 → 재설정 → 위치 및 개인정보 보호 재설정(데이터 유지) 후 재연결',
        'Wi-Fi로 갱신하려는 경우 이 항목은 무시')
}
if ($broken.Count -gt 0) {
    Add-Finding 1 'Apple USB 드라이버 오류(장치 관리자에서 느낌표 상태)' @(
        '장치 관리자 → 휴대용 장치/범용 직렬 버스 컨트롤러의 Apple Mobile Device USB Driver 우클릭 → 디바이스 제거 → 케이블 재연결',
        '그래도 안 되면 iTunes(Apple 홈페이지판) 복구/재설치')
}

# ---------- 3. 네트워크 ----------
Say ''
Say '[3] 네트워크' 'Cyan'
$ssid = $null
try {
    $wlan = netsh wlan show interfaces 2>$null
    $ssidLine = $wlan | Where-Object { $_ -match '^\s*SSID\s*:' } | Select-Object -First 1
    if ($ssidLine) { $ssid = ($ssidLine -split ':', 2)[1].Trim() }
} catch {}
Say "Wi-Fi: $(if ($ssid) { $ssid } else { '연결 없음/확인 불가' })"
$vpn = @()
try { $vpn = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and ($_.InterfaceDescription -match 'VPN|TAP-|WireGuard|Wintun|TUN|Tunnel|Fortinet|Cisco|Proton|Nord|Surfshark|Express|Cloudflare|OpenVPN' -or $_.Name -match 'VPN|WireGuard|Proton|Nord') } | ForEach-Object { "$($_.Name) [$($_.InterfaceDescription)]" }) } catch {}
$vpnOn = $vpn.Count -gt 0
Say "VPN 연결: $(if ($vpnOn) { $vpn -join ', ' } else { '없음' })"
try {
    $wp = (netsh winhttp show proxy 2>$null) -join ' '
    if ($wp -match 'Direct access|직접 액세스') { Say 'WinHTTP 프록시: 직접 연결' } else { Say "WinHTTP 프록시: $wp" 'Yellow' }
} catch {}

# ---------- 4. 서버 접속 (인증 없는 HEAD 요청) ----------
Say ''
Say "[4] 서버 접속 (각 최대 ${TimeoutSec}초)" 'Cyan'
$serverDate = $null
function Test-Endpoint([string]$name, [string]$url) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $result = [pscustomobject]@{ Name = $name; Url = $url; Ok = $false; Detail = '' }
    try {
        $req = [Net.HttpWebRequest]::Create($url)
        $req.Method = 'HEAD'
        $req.Timeout = $TimeoutSec * 1000
        $req.ReadWriteTimeout = $TimeoutSec * 1000
        $req.AllowAutoRedirect = $true
        $req.UserAgent = 'GymNote-AltStore-Doctor'
        $resp = $req.GetResponse()
        $result.Ok = $true
        $result.Detail = "HTTP $([int]$resp.StatusCode)"
        if (-not $script:serverDate -and $resp.Headers['Date']) { $script:serverDate = $resp.Headers['Date'] }
        $resp.Close()
    } catch [Net.WebException] {
        $ex = $_.Exception
        if ($ex.Response) {
            # 403/404 등 응답이 왔다면 서버까지는 닿은 것(익명 요청 거절은 정상).
            $result.Ok = $true
            $result.Detail = "HTTP $([int]$ex.Response.StatusCode) (응답 있음)"
            if (-not $script:serverDate -and $ex.Response.Headers['Date']) { $script:serverDate = $ex.Response.Headers['Date'] }
            $ex.Response.Close()
        } else {
            $result.Detail = "$($ex.Status)"
        }
    } catch {
        $result.Detail = $_.Exception.Message
    }
    $sw.Stop()
    $result.Detail = "$($result.Detail), $([math]::Round($sw.Elapsed.TotalSeconds, 1))초"
    return $result
}
$endpoints = @(
    @('AltStore 홈페이지', 'https://altstore.io/'),
    @('AltStore 다운로드 서버', 'https://cdn.altstore.io/'),
    @('Apple ID 인증(gsa)', 'https://gsa.apple.com/'),
    @('Apple ID 인증(idmsa)', 'https://idmsa.apple.com/'),
    @('Apple 개발자 서명 서버', 'https://developerservices2.apple.com/'),
    @('헬스노트 AltStore 소스', 'https://raw.githubusercontent.com/iasanullweb-maker/GymNote/altstore/source.json'),
    @('헬스노트 IPA 다운로드', 'https://github.com/iasanullweb-maker/GymNote/releases/latest/download/GymNote.ipa')
)
$net = @{}
foreach ($e in $endpoints) {
    $r = Test-Endpoint $e[0] $e[1]
    $net[$e[0]] = $r.Ok
    Say "$(Mark $r.Ok) $($r.Name): $($r.Detail)" $(if ($r.Ok) { 'Gray' } else { 'Yellow' })
}

$appleOk = $net['Apple ID 인증(gsa)'] -and $net['Apple 개발자 서명 서버']
$altOk = $net['AltStore 홈페이지'] -and $net['AltStore 다운로드 서버']
$githubOk = $net['헬스노트 AltStore 소스'] -and $net['헬스노트 IPA 다운로드']
if (-not $appleOk) {
    Add-Finding 1 'Apple 서명/인증 서버에 접속 불가 (Refresh 시 "timed out"/12002의 주원인)' @(
        $(if ($vpnOn) { 'VPN은 켜져 있지만 접속 실패 → VPN 서버를 바꾸거나 다른 네트워크(휴대폰 핫스팟)로 연결' } else { '노트북 VPN을 켜거나 휴대폰 핫스팟에 연결한 뒤 이 진단을 다시 실행' }),
        'iPad를 USB로 노트북에 연결·잠금 해제 → AltStore → My Apps → Refresh All')
} elseif (-not $altOk) {
    Add-Finding 2 'AltStore 서버 접속 불가 (AltStore 재설치·AltServer 업데이트 시 문제, 단순 Refresh에는 영향 적음)' @('AltStore 재설치가 필요하면 노트북 VPN을 켠 뒤 진행')
}
if (-not $githubOk) {
    Add-Finding 2 'GitHub(헬스노트 소스·IPA)에 접속 불가 → 새 버전 UPDATE·소스 새로고침 실패' @('iPad에서도 VPN을 켜거나 핫스팟으로 바꾼 뒤 AltStore → Browse/소스 새로고침 → UPDATE')
}

# ---------- 5. 시계 ----------
Say ''
Say '[5] 시계' 'Cyan'
if ($serverDate) {
    try {
        $remote = [DateTime]::Parse($serverDate).ToUniversalTime()
        $skew = [math]::Abs(((Get-Date).ToUniversalTime() - $remote).TotalMinutes)
        $clockOk = $skew -lt 5
        Say "$(Mark $clockOk) 서버 시각과 차이 $([math]::Round($skew, 1))분"
        if (-not $clockOk) { Add-Finding 1 '노트북 시계가 5분 이상 틀림 (Apple 인증 실패 원인)' @('설정 → 시간 및 언어 → 자동으로 시간 설정 켜기 → 지금 동기화') }
    } catch { Say '[참고] 시각 비교 실패' }
} else { Say '[참고] 서버 응답이 없어 시각 비교 불가' }

# ---------- 6. 오류 문구 해석 ----------
if ($ErrorText) {
    Say ''
    Say '[6] 오류 문구 해석' 'Cyan'
    $t = $ErrorText.ToLowerInvariant()
    $rules = @(
        @('could not find altserver|altserver를 찾|unable to find altserver', 0, 'iPad가 노트북 AltServer를 찾지 못함 (학교 Wi-Fi는 기기끼리 통신이 막히는 경우가 많음)',
          @('iPad를 USB로 노트북에 연결하고 잠금 해제 → "이 컴퓨터 신뢰"', 'iTunes에서 iPad 선택 → "Wi-Fi를 통해 이 iPad와 동기화" 켜기(한 번만)', 'AltServer가 실행 중인지 확인 후 Refresh All')),
        @('timed out|12002|시간이 초과|timeout|network connection was lost|offline', 0, 'Apple/AltStore 서버까지 네트워크가 막힘(학교망)',
          @('노트북·iPad 모두 VPN 켜기 또는 휴대폰 핫스팟 사용', 'USB 연결 후 Refresh All')),
        @('503|service unavailable|502|bad gateway|504', 0, '서버가 요청을 거절함(HTTP 503): 학교망 필터/프록시 또는 Apple·AltStore 서버 일시 장애',
          @('노트북·iPad 모두 VPN 켜기 또는 휴대폰 핫스팟으로 바꾼 뒤 Refresh All', '그래도 같으면 https://developer.apple.com/system-status/ 에서 Certificates, Identifiers & Profiles·Account 장애 확인 → 장애면 풀릴 때까지 대기(서명 만료 전이면 앱은 계속 사용 가능)')),
        @('maximum.*app id|app ids|10 app|app id limit', 0, '무료 Apple ID의 주간 App ID 한도(7일에 10개) 초과',
          @('번들 ID를 바꾸거나 다른 앱을 새로 설치하지 말 것', '7일이 지나 한도가 풀릴 때까지 기다림(기존 헬스노트·AltStore는 삭제하지 않음)')),
        @('maximum number of apps|3 active|active apps|활성 앱', 0, '무료 Apple ID의 활성 앱 3개 한도(AltStore 포함) 초과',
          @('AltStore → My Apps에서 쓰지 않는 앱을 Deactivate')),
        @('incorrect apple id|password|session.*expired|-22411|-36607|2fa|two-factor|인증', 0, 'Apple ID 로그인 만료/오류',
          @('AltStore → Settings에서 로그아웃 후 같은 Apple ID로 다시 로그인', '2단계 인증 코드가 오면 입력')),
        @('anisette|-45054|alterror', 0, 'Apple 인증 정보(anisette) 생성 실패',
          @('iCloud(웹 설치판) 실행·로그인 확인', 'AltServer 종료 후 다시 실행')),
        @('expired|만료|revoked|certificate', 0, '앱/AltStore 서명 만료 또는 인증서 폐기',
          @('AltStore가 열리지 않으면: 노트북 AltServer 트레이 아이콘 → Install AltStore → 해당 iPad, 같은 Apple ID로 덮어 설치(삭제 금지)', '그 뒤 AltStore → My Apps → Refresh All')),
        @('download|could not be opened|couldn.t be read|파일', 0, 'IPA 다운로드 실패(GitHub 접속 문제 가능)',
          @('iPad에서 VPN/핫스팟으로 바꾼 뒤 다시 UPDATE')),
        @('device|기기를 찾|unable to connect|pair', 0, '노트북이 iPad를 인식하지 못함',
          @('USB 케이블 재연결·잠금 해제·신뢰', 'iTunes에서 iPad가 보이는지 확인'))
    )
    $matched = $false
    foreach ($rule in $rules) {
        if ($t -match $rule[0]) {
            $matched = $true
            Say "→ $($rule[2])" 'Yellow'
            Add-Finding $rule[1] "오류 문구: $($rule[2])" $rule[3]
        }
    }
    if (-not $matched) { Say '→ 알려진 패턴과 일치하지 않음. 이 보고서를 Claude/Codex에게 보여 주세요.' 'Yellow' }
}

# ---------- 결론 ----------
Say ''
Say '=== 원인 후보와 해결 순서 (위에서부터) ===' 'Cyan'
if ($findings.Count -eq 0) {
    Say '노트북 쪽 문제는 발견되지 않았습니다.' 'Green'
    Say '1) iPad를 USB로 연결·잠금 해제 → AltStore → My Apps → Refresh All'
    Say '2) 그래도 실패하면 iPad에 뜬 오류 문구를 넣어 이 진단을 다시 실행'
} else {
    $n = 1
    foreach ($f in ($findings | Sort-Object Priority)) {
        Say "$n. $($f.Cause)" 'Yellow'
        foreach ($s in $f.Steps) { Say "   - $s" }
        $n++
    }
}
Say ''
Say '주의: 기존 AltStore·헬스노트 앱은 삭제하지 마세요(기록 유지). 자세한 표: docs\ALTSTORE_TROUBLESHOOTING.md'

try {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $text = ($lines -join "`r`n")
    $utf8 = New-Object System.Text.UTF8Encoding($true)
    [IO.File]::WriteAllText((Join-Path $outDir "report-$stamp.txt"), $text, $utf8)
    [IO.File]::WriteAllText((Join-Path $outDir 'latest.txt'), $text, $utf8)
    Write-Host ''
    Write-Host "보고서 저장: $(Join-Path $outDir 'latest.txt')" -ForegroundColor Green
} catch {
    Write-Host "보고서 저장 실패: $($_.Exception.Message)" -ForegroundColor Red
}
