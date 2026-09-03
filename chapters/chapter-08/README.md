# Capítulo 8 — edição e regras de atualização

O projeto separa cinco contratos:

- `calculated`: campo `fkCalculated`, chamadas de `OnCalcFields` e `ProviderFlags`;
- `lookup`: chave válida e ausente em campo `fkLookup`;
- `aggregate`: total local durante append, post e cancel;
- `join`: update automático delimitado a `product`, com SQL capturado por trace;
- `conflict`: `TFDUpdateSQL` com `OLD_version` e conflito otimista reproduzido.

```powershell
.\scripts\validate-chapter-08.ps1 `
  -AdminPassword '<senha-administrativa>' `
  -AppPassword '<senha-do-laboratório>'
```

O mesmo fonte é compilado para Win32/Win64 e executado contra SQLite/Firebird. Traces,
binários, bancos e credenciais permanecem em `.deps`, fora do Git.
