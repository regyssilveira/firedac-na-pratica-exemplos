# Cliente Firebird para Win32 e Win64

O servidor Firebird pode ter arquitetura diferente do cliente quando a conexão usa
TCP. O `fbclient.dll`, porém, é carregado dentro do processo Delphi e precisa ter a
mesma arquitetura do executável.

Prepare os dois kits oficiais sem versionar binários:

```powershell
./scripts/install-firebird-clients.ps1 -Architecture Both
```

Os arquivos serão colocados em `.deps/firebird/Win32` e `.deps/firebird/Win64`, com
o SHA-256 do arquivo oficial e o cabeçalho PE de `fbclient.dll` validados. O código
compartilhado resolve o caminho por diretiva de compilação; não depende da arquitetura
do Windows nem da instalação do servidor.

Para testar somente um alvo:

```powershell
./scripts/test-firebird-client-profile.ps1 -Architecture Win32
./scripts/test-firebird-client-profile.ps1 -Architecture Win64
```

Para compilar e conectar realmente com FireDAC nos dois alvos, configure as variáveis
do `.env.example` no processo, acrescente `FIRESTORE_FB_DATABASE` com o caminho de um
banco de laboratório existente e execute:

```powershell
./scripts/validate-firebird-profiles.ps1
```

Credenciais são recebidas por variáveis de ambiente. Elas não são gravadas nem
impressas. Os kits vêm do projeto Firebird e permanecem sujeitos às licenças incluídas
em cada distribuição oficial.
