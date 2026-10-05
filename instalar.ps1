# ============================================================
#  Instalacao silenciosa de programas
#  Execute em um PowerShell aberto como Administrador
# ============================================================
$ErrorActionPreference = 'Stop'

# --- Verifica se esta como administrador (funciona tambem com irm | iex) ---
$ehAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $ehAdmin) {
    Write-Warning 'Abra o PowerShell como Administrador e execute novamente.'
    return
}

# --- Menu inicial ---
Write-Host ''
Write-Host '=====================================' -ForegroundColor Cyan
Write-Host '   INSTALACAO AUTOMATICA DE PROGRAMAS' -ForegroundColor Cyan
Write-Host '=====================================' -ForegroundColor Cyan
Write-Host '  [1] Iniciar instalacao'
Write-Host '  [0] Sair'
Write-Host ''

do {
    $opcao = (Read-Host 'Escolha uma opcao').Trim()
    if ($opcao -notin '0', '1') {
        Write-Warning 'Opcao invalida. Digite 1 para iniciar ou 0 para sair.'
    }
} until ($opcao -in '0', '1')

if ($opcao -eq '0') {
    Write-Host 'Saindo sem instalar nada.' -ForegroundColor Yellow
    return
}

# --- Log da execucao ---
$logArquivo = Join-Path $env:TEMP ('instalacao_{0:yyyyMMdd_HHmmss}.log' -f (Get-Date))
Start-Transcript -Path $logArquivo | Out-Null

# --- Servidor de impressao (NDD Print Host) ---
# A documentacao do NDD Print Agent pede IP no HostAddress,
# entao o nome e resolvido para IP. Se falhar, usa o nome direto.
$hostNome = 'prdprt-srv01'
try {
    $hostIP = (Resolve-DnsName $hostNome -Type A -ErrorAction Stop |
               Where-Object { $_.IPAddress } |
               Select-Object -First 1).IPAddress
    Write-Host "Servidor de impressao: $hostNome -> $hostIP" -ForegroundColor DarkCyan
}
catch {
    Write-Warning "Nao foi possivel resolver $hostNome. Usando o nome direto."
    $hostIP = $hostNome
}

# ============================================================
#  LISTA DE PROGRAMAS  (preencha aqui)
#
#  Nome        : nome exibido no console
#  Caminho     : caminho do instalador (rede ou local)
#  Args        : parametros silenciosos (vazio se nao houver)
#  Teste       : (opcional) arquivo que indica que ja esta instalado
#  CopiarPasta : (opcional) $true copia a pasta inteira do instalador
#  Ini         : (opcional) arquivo de configuracao criado ao lado
#                do instalador (ex.: Agent.ini do NDDPrint)
# ============================================================
$apps = @(
    @{
        Nome    = 'BitDefender'
        Caminho = '\\diagonal.net\Global\Transfer_TI\Notebooks\1-NOTEBOOKS\epskit_x64_7.9.27.574\epskit_x64.exe'
        Args    = '/S'
    },
    @{
        Nome    = 'Java'
        Caminho = '\\diagonal.net\Global\Transfer_TI\Notebooks\1-NOTEBOOKS\4-jre-8u231-windows-x64.exe'
        Args    = '/qn /norestart'
    },
    @{
        Nome    = 'Google Chrome'
        Caminho = '\\diagonal.net\Global\Transfer_TI\Notebooks\1-NOTEBOOKS\5-ChromeSetup.exe'
        Args    = '/qn /norestart'
    },
    @{
        Nome    = '7zip'
        Caminho = '\\diagonal.net\Global\Transfer_TI\Notebooks\1-NOTEBOOKS\7z2401-x64.exe'
        Args    = '/qn /norestart'
    },
    @{
        Nome    = 'AnyDesk'
        Caminho = '\\diagonal.net\Global\Transfer_TI\Notebooks1-NOTEBOOKS\\AnyDesk_Diagonal.exe'
        Args    = '/qn /norestart'
    },
    @{
        Nome    = 'FortiClient'
        Caminho = '\\diagonal.net\Global\Transfer_TI\Notebooks\1-NOTEBOOKS\FortiClientVPN.exe'
        Args    = '/qn /norestart'
    },
    @{
        Nome    = 'Office'
        Caminho = '\\diagonal.net\Global\Transfer_TI\Notebooks\1-NOTEBOOKS\OfficeSetup.exe'
        Args    = '/qn /norestart'
    },
    @{
        Nome        = 'NDDPrint'
        Caminho     = '\\servidor\instaladores\NDDPrint\NDDPrintAgent.exe'
        Args        = ''    # confirme a chave silenciosa com a TI/fornecedor, se abrir a tela
        CopiarPasta = $true
        Ini         = @{
            Arquivo  = 'Agent.ini'
            Conteudo = @"
[InstallSettings]
HostAddress=$hostIP
Language=PT-BR
InstallType=1
"@
        }
    }
)

# ============================================================
#  EXECUCAO  (nao precisa alterar daqui para baixo)
# ============================================================
$resultados = @()

foreach ($app in $apps) {

    # Pula se ja estiver instalado
    if ($app.Teste -and (Test-Path $app.Teste)) {
        Write-Host "Ja instalado: $($app.Nome)" -ForegroundColor Yellow
        $resultados += [pscustomobject]@{ Programa = $app.Nome; Status = 'Ja instalado' }
        continue
    }

    # Pasta temporaria propria de cada programa
    $pasta   = Join-Path $env:TEMP ('inst_' + [guid]::NewGuid().ToString('N'))
    $arquivo = Split-Path $app.Caminho -Leaf
    $local   = Join-Path $pasta $arquivo

    try {
        Write-Host "Instalando $($app.Nome)..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $pasta | Out-Null

        # Copia o instalador (ou a pasta inteira, se necessario)
        if ($app.CopiarPasta) {
            Copy-Item -Path (Join-Path (Split-Path $app.Caminho -Parent) '*') `
                      -Destination $pasta -Recurse -Force
        } else {
            Copy-Item -Path $app.Caminho -Destination $local -Force
        }

        # Cria o arquivo de configuracao ao lado do instalador
        if ($app.Ini) {
            $iniPath = Join-Path $pasta $app.Ini.Arquivo
            Set-Content -Path $iniPath -Value $app.Ini.Conteudo -Encoding ASCII
        }

        # Executa o instalador
        if ($local -like '*.msi') {
            $logMsi = Join-Path $env:TEMP (($app.Nome -replace '\W', '_') + '.log')
            $p = Start-Process msiexec.exe `
                -ArgumentList "/i `"$local`" $($app.Args) /l*v `"$logMsi`"" `
                -Wait -PassThru
        }
        elseif ($app.Args) {
            $p = Start-Process -FilePath $local -ArgumentList $app.Args `
                -WorkingDirectory $pasta -Wait -PassThru
        }
        else {
            $p = Start-Process -FilePath $local `
                -WorkingDirectory $pasta -Wait -PassThru
        }

        # 0 = sucesso, 3010 = sucesso mas pede reinicializacao
        if ($p.ExitCode -in 0, 3010) {
            $status = if ($p.ExitCode -eq 3010) { 'OK (reiniciar)' } else { 'OK' }
            Write-Host "OK: $($app.Nome) (codigo $($p.ExitCode))" -ForegroundColor Green
        } else {
            $status = "FALHA (codigo $($p.ExitCode))"
            Write-Warning "$($app.Nome) terminou com codigo $($p.ExitCode)"
        }
        $resultados += [pscustomobject]@{ Programa = $app.Nome; Status = $status }
    }
    catch {
        Write-Warning "Falha em $($app.Nome): $_"
        $resultados += [pscustomobject]@{ Programa = $app.Nome; Status = 'ERRO' }
    }
    finally {
        Remove-Item $pasta -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Resumo final ---
Write-Host ''
Write-Host '========== RESUMO ==========' -ForegroundColor Green
$resultados | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "Log completo: $logArquivo"

Stop-Transcript | Out-Null
