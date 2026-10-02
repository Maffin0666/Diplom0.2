# Run after `flutter create --platforms android,ios --project-name lecture_reader .`.
# Idempotently configures the generated platform projects for camera, speech and LAN HTTP.
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mainManifest = Join-Path $project 'android\app\src\main\AndroidManifest.xml'
$debugManifest = Join-Path $project 'android\app\src\debug\AndroidManifest.xml'
$iosPlist = Join-Path $project 'ios\Runner\Info.plist'
$gradleKts = Join-Path $project 'android\app\build.gradle.kts'
$gradleGroovy = Join-Path $project 'android\app\build.gradle'
$podfile = Join-Path $project 'ios\Podfile'

if (-not (Test-Path -LiteralPath $mainManifest) -or -not (Test-Path -LiteralPath $iosPlist)) {
    throw 'Сначала выполните flutter create --platforms android,ios --project-name lecture_reader .'
}

$androidNs = 'http://schemas.android.com/apk/res/android'
[xml]$manifest = Get-Content -LiteralPath $mainManifest -Raw
foreach ($permissionName in @('android.permission.INTERNET', 'android.permission.RECORD_AUDIO')) {
    $existing = @($manifest.SelectNodes('/manifest/uses-permission')) | Where-Object {
        $_ -and $_.GetAttribute('name', $androidNs) -eq $permissionName
    }
    if (-not $existing) {
        $item = $manifest.CreateElement('uses-permission')
        $item.SetAttribute('name', $androidNs, $permissionName)
        [void]$manifest.manifest.PrependChild($item)
    }
}
$queries = $manifest.manifest.queries
if ($null -eq $queries) {
    $queries = $manifest.CreateElement('queries')
    [void]$manifest.manifest.AppendChild($queries)
}
$recognitionIntent = @($manifest.SelectNodes('/manifest/queries/intent/action')) | Where-Object {
    $_ -and $_.GetAttribute('name', $androidNs) -eq 'android.speech.RecognitionService'
}
if (-not $recognitionIntent) {
    $intent = $manifest.CreateElement('intent')
    $action = $manifest.CreateElement('action')
    $action.SetAttribute('name', $androidNs, 'android.speech.RecognitionService')
    [void]$intent.AppendChild($action)
    [void]$queries.AppendChild($intent)
}
# Lecture photos and audio are private app data; exclude them from cloud backup.
[void]$manifest.manifest.application.SetAttribute('allowBackup', $androidNs, 'false')
[void]$manifest.manifest.application.SetAttribute('label', $androidNs, 'Лектория.Ai')
$manifest.Save($mainManifest)

# Only debug builds may send photos and results over plaintext local Wi-Fi.
$debugDirectory = Split-Path -Parent $debugManifest
New-Item -ItemType Directory -Force -Path $debugDirectory | Out-Null
@'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:usesCleartextTraffic="true" />
</manifest>
'@ | Set-Content -LiteralPath $debugManifest -Encoding utf8

[xml]$plist = Get-Content -LiteralPath $iosPlist -Raw
$dict = $plist.plist.dict
$values = [ordered]@{
    NSCameraUsageDescription = 'Сфотографировать конспект для распознавания и озвучивания.'
    NSPhotoLibraryUsageDescription = 'Выбрать снимок конспекта для распознавания и озвучивания.'
    NSMicrophoneUsageDescription = 'Распознавать голосовые команды управления лекцией.'
    NSSpeechRecognitionUsageDescription = 'Распознавать голосовые команды управления лекцией.'
}
foreach ($keyName in $values.Keys) {
    $existing = @($plist.SelectNodes('/plist/dict/key')) | Where-Object {
        $_ -and $_.InnerText -eq $keyName
    }
    if (-not $existing) {
        $key = $plist.CreateElement('key')
        $key.InnerText = $keyName
        $value = $plist.CreateElement('string')
        $value.InnerText = $values[$keyName]
        [void]$dict.AppendChild($key)
        [void]$dict.AppendChild($value)
    }
}
$plist.Save($iosPlist)

# image_picker and path_provider currently require Android API 24 / iOS 13.
if (Test-Path -LiteralPath $gradleKts) {
    $gradle = Get-Content -LiteralPath $gradleKts -Raw
    $gradle = $gradle.Replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
    $gradleProperties = Join-Path $project 'android\gradle.properties'
    if ((Test-Path -LiteralPath $gradleProperties) -and
        (Get-Content -LiteralPath $gradleProperties -Raw) -match 'android\.builtInKotlin=false' -and
        $gradle -notmatch 'id\("org\.jetbrains\.kotlin\.android"\)') {
        $gradle = $gradle.Replace('id("com.android.application")',
            "id(`"com.android.application`")`r`n    id(`"org.jetbrains.kotlin.android`")")
    }
    $gradle | Set-Content -LiteralPath $gradleKts -Encoding utf8
} elseif (Test-Path -LiteralPath $gradleGroovy) {
    $gradle = Get-Content -LiteralPath $gradleGroovy -Raw
    $gradle = $gradle.Replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 24')
    $gradle | Set-Content -LiteralPath $gradleGroovy -Encoding utf8
}
if (Test-Path -LiteralPath $podfile) {
    $pods = Get-Content -LiteralPath $podfile -Raw
    $pods = [regex]::Replace($pods, '(?m)^#?\s*platform :ios, .+$', "platform :ios, '13.0'")
    $pods | Set-Content -LiteralPath $podfile -Encoding utf8
}
Write-Host 'Разрешения Android/iOS настроены. Локальный HTTP разрешён только в Android debug.'
