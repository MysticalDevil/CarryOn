# CarryOn 26.3 移植构建脚本
#
# 用法: pwsh -File .\build-26.3.ps1 [-Target Fabric|NeoForge|All]
#
# 背景: NeoForge 26.3.x 的 dev 管线(NeoForm 26.3-1 + JST 2.0.6)在重编译 Minecraft
#       源码时会报 HolderSet 匿名类的访问级别错误, 导致 :NeoForge 无法配置。
#       本脚本会在构建 NeoForge 前, 把 neoform-runtime 内部固定的 JST 版本
#       从 2.0.6 提升到 2.0.11, 并清掉受影响的中间缓存。
#       首次修改前会自动备份原 jar。

param(
    [ValidateSet('Fabric', 'NeoForge', 'All')]
    [string]$Target = 'All'
)

$ErrorActionPreference = 'Continue'

$env:JAVA_HOME = 'C:\Users\jinpe\scoop\apps\openjdk25\current'
$env:Path      = "$env:JAVA_HOME\bin;$env:Path"

# 仓库根 = 脚本所在目录, 产物输出到其上一级的 jars\
$repo = $PSScriptRoot
if (-not $repo) { $repo = (Get-Location).Path }
$out  = Join-Path (Split-Path $repo -Parent) 'jars'
New-Item -ItemType Directory -Force -Path $out | Out-Null

# ---------------------------------------------------------------- NeoForge 工具链修补
function Repair-NeoFormToolchain {
    $nfrRoot = Join-Path $env:USERPROFILE '.gradle\caches\modules-2\files-2.1\net.neoforged\neoform-runtime'
    if (-not (Test-Path $nfrRoot)) {
        Write-Output "  [skip] 未找到 neoform-runtime 缓存 (先跑一次 NeoForge 构建即可生成)"
        return
    }

    Get-ChildItem $nfrRoot -Recurse -File -Filter 'neoform-runtime-*-all.jar' | ForEach-Object {
        $jar = $_.FullName
        $bak = "$jar.bak"

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $z = [System.IO.Compression.ZipFile]::OpenRead($jar)
        $e = $z.Entries | Where-Object FullName -eq 'tools.properties'
        $txt = ''
        if ($e) {
            $r = New-Object System.IO.StreamReader($e.Open())
            $txt = $r.ReadToEnd()
            $r.Close()
        }
        $z.Dispose()

        if ($txt -notmatch 'jst-cli-bundle:2\.0\.6') {
            Write-Output "  [ok]   $([System.IO.Path]::GetFileName($jar)) 已是 2.0.11+, 无需修补"
            return
        }

        if (-not (Test-Path $bak)) {
            Copy-Item $jar $bak
            Write-Output "  [bak]  已备份 -> $([System.IO.Path]::GetFileName($bak))"
        }

        $z = [System.IO.Compression.ZipFile]::Open($jar, 'Update')
        $old = $z.Entries | Where-Object FullName -eq 'tools.properties'
        if ($old) { $old.Delete() }
        $new = $z.CreateEntry('tools.properties')
        $w = New-Object System.IO.StreamWriter($new.Open())
        $w.Write(@"
JAVA_SOURCE_TRANSFORMER=net.neoforged.jst:jst-cli-bundle:2.0.11

DIFF_PATCH=io.codechicken:DiffPatch:2.0.0.36:all

MCF_SIDE_ANNOTATION_STRIPPER=net.minecraftforge:mergetool:1.1.7:fatjar

INSTALLER_TOOLS=net.neoforged.installertools:installertools:4.0.12:fatjar

AUTO_RENAMING_TOOL=net.neoforged:AutoRenamingTool:2.0.17:all
"@)
        $w.Close()
        $z.Dispose()
        Write-Output "  [fix]  $([System.IO.Path]::GetFileName($jar)) : JST 2.0.6 -> 2.0.11"

        # 缓存键不含 JST 版本, 必须清掉受影响的中间产物
        $mid = Join-Path $env:USERPROFILE '.gradle\caches\neoformruntime\intermediate_results'
        if (Test-Path $mid) {
            Get-ChildItem $mid -Filter 'transformSources_*' | Remove-Item -Force -ErrorAction SilentlyContinue
            Get-ChildItem $mid -Filter 'recompile_*'        | Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Output "  [fix]  已清理 transformSources / recompile 中间缓存"
        }
    }
}

# ---------------------------------------------------------------- 构建
function Build-Target([string]$name, [string]$jarPrefix) {
    Write-Output ""
    Write-Output "================ 构建 $name ================"
    Push-Location $repo
    $log = Join-Path (Split-Path $repo -Parent) "build-$($name.ToLower()).log"
    & .\gradlew.bat ":$name`:build" --no-daemon --console=plain 2>&1 | Tee-Object -FilePath $log | Select-Object -Last 12
    $code = $LASTEXITCODE
    Pop-Location

    if ($code -ne 0) {
        Write-Output "  ==> 失败 (exit $code), 详见 $log"
        return $false
    }

    $libs = Join-Path $repo "$name\build\libs"
    $jar  = Get-ChildItem $libs -Filter '*.jar' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch 'sources|javadoc' } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($jar) {
        Copy-Item $jar.FullName (Join-Path $out $jar.Name) -Force
        Write-Output "  ==> OK  $($jar.Name)"
        return $true
    }
    Write-Output "  ==> 编译成功但未找到 jar"
    return $false
}

# ---------------------------------------------------------------- 主流程
$ok = @()
$fail = @()

if ($Target -in @('Fabric', 'All')) {
    if (Build-Target 'Fabric' 'carryon-fabric') { $ok += 'Fabric' } else { $fail += 'Fabric' }
}

if ($Target -in @('NeoForge', 'All')) {
    Write-Output ""
    Write-Output "================ 修补 NeoForm 工具链 ================"
    Repair-NeoFormToolchain
    if (Build-Target 'NeoForge' 'carryon-neoforge') { $ok += 'NeoForge' } else { $fail += 'NeoForge' }
}

Write-Output ""
Write-Output "================ 汇总 ================"
$ok   | ForEach-Object { "  OK    $_" }
$fail | ForEach-Object { "  FAIL  $_" }
Write-Output "产物目录: $out"
