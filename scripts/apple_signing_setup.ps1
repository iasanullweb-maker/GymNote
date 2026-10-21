<#
  GymNote 유료 Apple Developer 서명 준비 도구 (Windows PowerShell 5.1 호환)
  - Csr     : 배포 인증서용 개인키와 CSR 생성
  - P12     : Apple에서 받은 distribution.cer + 개인키 -> .p12 (macOS 호환 암호화)
  - Secrets : GitHub Actions 시크릿용 base64 파일 생성 (-Upload: gh CLI로 바로 등록)
  비밀 파일은 .validation-tools\apple-signing\ (Git 미추적)에만 저장한다.
  자세한 순서: docs\APPLE_DEVELOPER_SETUP.md
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Csr', 'P12', 'Secrets')]
    [string]$Mode,
    [string]$Email,
    [string]$Name,
    [string]$CerPath,
    [string]$AscKeyId,
    [string]$AscIssuerId,
    [switch]$Upload
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $repo '.validation-tools\apple-signing'
$keyPath = Join-Path $outDir 'gymnote_distribution.key'
$csrPath = Join-Path $outDir 'gymnote_distribution.csr'
$p12Path = Join-Path $outDir 'gymnote_distribution.p12'

function Find-OpenSsl {
    $cmd = Get-Command openssl -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "$env:ProgramFiles\Git\usr\bin\openssl.exe",
        "${env:ProgramFiles(x86)}\Git\usr\bin\openssl.exe",
        "$env:LOCALAPPDATA\Programs\Git\usr\bin\openssl.exe"
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    throw 'openssl을 찾지 못했습니다. Git for Windows를 설치하면 함께 설치됩니다.'
}

function Invoke-OpenSsl {
    param([string[]]$Arguments)
    & $script:openssl @Arguments
    if ($LASTEXITCODE -ne 0) { throw "openssl 실패 (종료 코드 $LASTEXITCODE): $($Arguments -join ' ')" }
}

function Write-Base64File {
    param([string]$Source, [string]$Target)
    $bytes = [System.IO.File]::ReadAllBytes($Source)
    [System.IO.File]::WriteAllText($Target, [Convert]::ToBase64String($bytes))
}

if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$script:openssl = Find-OpenSsl

switch ($Mode) {
    'Csr' {
        if (-not $Email -or -not $Name) { throw '-Email 과 -Name 을 입력하세요.' }
        if (Test-Path $keyPath) {
            throw "이미 개인키가 있습니다: $keyPath`n기존 인증서에 쓰이는 키일 수 있으니 덮어쓰지 않습니다. 새로 만들려면 직접 다른 곳으로 옮긴 뒤 다시 실행하세요."
        }
        Invoke-OpenSsl @('genrsa', '-out', $keyPath, '2048')
        $subject = "/emailAddress=$Email/CN=$Name/C=KR"
        Invoke-OpenSsl @('req', '-new', '-utf8', '-key', $keyPath, '-out', $csrPath, '-subj', $subject)
        Write-Host ''
        Write-Host "[완료] CSR: $csrPath" -ForegroundColor Green
        Write-Host '다음: developer.apple.com > Certificates > + > Apple Distribution 에 이 CSR을 올리고,'
        Write-Host "      받은 distribution.cer 를 $outDir 에 저장한 뒤 -Mode P12 를 실행하세요."
        Write-Host "주의: $keyPath 는 백업하고 누구에게도 보내지 마세요."
    }
    'P12' {
        if (-not $CerPath) { $CerPath = Join-Path $outDir 'distribution.cer' }
        if (-not (Test-Path $CerPath)) { throw "인증서 파일이 없습니다: $CerPath" }
        if (-not (Test-Path $keyPath)) { throw "개인키가 없습니다: $keyPath (먼저 -Mode Csr 로 만든 키가 필요합니다)" }
        $pemPath = Join-Path $outDir 'distribution.pem'
        # Apple은 DER 형식을 주지만 PEM으로 받은 경우도 처리
        # PS 5.1은 Stop 상태에서 네이티브 stderr 리디렉션을 오류로 바꾸므로 잠시 Continue
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $script:openssl x509 -inform DER -in $CerPath -out $pemPath 2>$null
        $derExit = $LASTEXITCODE
        $ErrorActionPreference = $previousPreference
        if ($derExit -ne 0) { Invoke-OpenSsl @('x509', '-inform', 'PEM', '-in', $CerPath, '-out', $pemPath) }
        $secure = Read-Host '.p12 비밀번호 (GitHub 시크릿 APPLE_CERT_PASSWORD로 저장할 값)' -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            if (-not $plain) { throw '비밀번호가 비어 있습니다.' }
            $env:GYMNOTE_P12_PASS = $plain
            # macOS security import 호환: OpenSSL 3 기본(AES/PBKDF2) 대신 3DES/SHA1
            Invoke-OpenSsl @('pkcs12', '-export', '-inkey', $keyPath, '-in', $pemPath, '-out', $p12Path,
                '-name', 'GymNote Apple Distribution',
                '-keypbe', 'PBE-SHA1-3DES', '-certpbe', 'PBE-SHA1-3DES', '-macalg', 'sha1',
                '-passout', 'env:GYMNOTE_P12_PASS')
            Invoke-OpenSsl @('pkcs12', '-in', $p12Path, '-noout', '-passin', 'env:GYMNOTE_P12_PASS')
        }
        finally {
            Remove-Item Env:\GYMNOTE_P12_PASS -ErrorAction SilentlyContinue
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
        $subjectLine = & $script:openssl x509 -in $pemPath -noout -subject
        Write-Host ''
        Write-Host "[완료] $p12Path" -ForegroundColor Green
        Write-Host "인증서: $subjectLine"
        Write-Host '다음: 앱/위젯 App Store 프로파일을 만들어 같은 폴더에 저장한 뒤 -Mode Secrets 를 실행하세요.'
    }
    'Secrets' {
        if (-not $AscKeyId -or -not $AscIssuerId) { throw '-AscKeyId 와 -AscIssuerId 를 입력하세요.' }
        $p8Path = Join-Path $outDir "AuthKey_$AscKeyId.p8"
        $appProfile = Join-Path $outDir 'GymNote_AppStore.mobileprovision'
        $widgetProfile = Join-Path $outDir 'GymNoteWidget_AppStore.mobileprovision'
        $missing = @()
        foreach ($f in @($p12Path, $appProfile, $widgetProfile, $p8Path)) {
            if (-not (Test-Path $f)) { $missing += $f }
        }
        if ($missing.Count -gt 0) { throw ("다음 파일이 없습니다:`n" + ($missing -join "`n")) }
        $secretDir = Join-Path $outDir 'secrets'
        if (-not (Test-Path $secretDir)) { New-Item -ItemType Directory -Path $secretDir | Out-Null }
        Write-Base64File $p12Path (Join-Path $secretDir 'APPLE_CERT_P12_BASE64.txt')
        Write-Base64File $appProfile (Join-Path $secretDir 'APPLE_APP_PROFILE_BASE64.txt')
        Write-Base64File $widgetProfile (Join-Path $secretDir 'APPLE_WIDGET_PROFILE_BASE64.txt')
        Write-Base64File $p8Path (Join-Path $secretDir 'ASC_KEY_P8_BASE64.txt')
        [System.IO.File]::WriteAllText((Join-Path $secretDir 'ASC_KEY_ID.txt'), $AscKeyId)
        [System.IO.File]::WriteAllText((Join-Path $secretDir 'ASC_ISSUER_ID.txt'), $AscIssuerId)
        Write-Host "[완료] 시크릿 파일: $secretDir" -ForegroundColor Green
        Write-Host 'APPLE_CERT_PASSWORD 는 파일로 만들지 않았습니다. P12 단계에서 정한 비밀번호를 직접 입력하세요.'
        if ($Upload) {
            $gh = Get-Command gh -ErrorAction SilentlyContinue
            if (-not $gh) { throw 'gh CLI가 없습니다. -Upload 없이 실행하고 GitHub 웹에서 직접 붙여 넣으세요.' }
            Push-Location $repo
            try {
                foreach ($file in Get-ChildItem $secretDir -Filter '*.txt') {
                    $secretName = [IO.Path]::GetFileNameWithoutExtension($file.Name)
                    $value = (Get-Content -Raw $file.FullName).Trim()
                    & gh secret set $secretName --body $value
                    if ($LASTEXITCODE -ne 0) { throw "gh secret set $secretName 실패" }
                    Write-Host "등록: $secretName"
                }
                Write-Host 'APPLE_CERT_PASSWORD 등록: 아래에 비밀번호 입력'
                & gh secret set APPLE_CERT_PASSWORD
            }
            finally { Pop-Location }
        }
        else {
            Write-Host 'GitHub 저장소 Settings > Secrets and variables > Actions > Secrets 에 파일 이름과 같은 이름으로 내용을 붙여 넣으세요.'
        }
        Write-Host 'Variables 에 APPLE_TEAM_ID 도 등록했는지 확인하세요.'
    }
}
