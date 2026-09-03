# Capítulo 5 — consultas e comandos

Este projeto console exercita, em processos independentes, os cinco contratos do
capítulo:

- `list`: dataset tipado e ordenação determinística com `TFDQuery`;
- `dml`: `ExecSQL` e distinção entre uma e zero linhas afetadas;
- `command`: preparação e reutilização de `TFDCommand`;
- `key`: chave gerada recuperada por `INSERT ... RETURNING`;
- `pagination`: comparação entre paginação por offset e por chave;
- `benchmark-pagination`: BM-03 com offset alto, keyset e escrita antes da fronteira.

O mesmo fonte é compilado nativamente para Win32 e Win64 e executado contra SQLite e
Firebird. As operações de escrita usam transação explícita e `Rollback`, preservando
o seed descartável.

BM-03 prepara 100 mil linhas em transação, descarta um aquecimento e registra cinco
repetições por perfil em `evidence/bm-03-raw.csv`. Depois insere uma linha antes da
fronteira para comprovar a instabilidade do offset e a estabilidade do keyset.

Execute:

```powershell
.\scripts\validate-chapter-05.ps1 `
  -AdminPassword '<senha-administrativa>' `
  -AppPassword '<senha-do-laboratório>'
```

As credenciais são parâmetros de execução e não devem ser versionadas.
