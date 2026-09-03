# FireStore

Aplicação evolutiva do livro. O marco M0 entrega migrations com checksum, seed
determinístico, reset controlado e smoke test em SQLite e Firebird 5.

## M0

O executável `FireStoreBootstrap` recebe configuração apenas por ambiente:

```powershell
$env:FIRESTORE_DRIVER = 'SQLite' # ou FB
$env:FIRESTORE_DB_NAME = 'caminho-do-banco'
$env:FIRESTORE_MIGRATIONS = 'firestore/database/sqlite/migrations'
```

Comandos:

```powershell
FireStoreBootstrap.exe migrate
FireStoreBootstrap.exe smoke
```

`migrate` cria `schema_version`, valida o SHA-256 de migrations já aplicadas e aplica
novas migrations em ordem. `smoke` exige duas versões aplicadas, duas categorias e
três produtos conhecidos.

## Firebird local

O provisionamento exige as senhas como parâmetros em tempo de execução; nenhuma
credencial é persistida no Git. Execute `scripts/provision-firestore-firebird.ps1`,
rode as migrations como administrador e então execute
`scripts/grant-firestore-app.ps1`. O smoke test deve ser feito com
`FIRESTORE_APP`, confirmando que a aplicação não depende de `SYSDBA`.

O parâmetro `-Reset` é deliberadamente explícito: ele conecta ao banco indicado,
executa `DROP DATABASE` e o recria. Não remove arquivos diretamente do sistema.

Para compilar e repetir a matriz completa localmente:

```powershell
.\scripts\validate-firestore-m0.ps1 `
  -AdminPassword $env:FIREBIRD_ADMIN_PASSWORD `
  -AppPassword $env:FIRESTORE_DB_PASSWORD
```

O script cobre SQLite e Firebird em Win32 e Win64. Os kits oficiais de cliente
devem ter sido preparados antes por `scripts/install-firebird-clients.ps1`.
