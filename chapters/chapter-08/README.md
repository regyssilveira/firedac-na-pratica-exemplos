# Capítulo 8 — edição e regras de atualização

O projeto separa seis contratos:

- `calculated`: campo `fkCalculated`, chamadas de `OnCalcFields` e `ProviderFlags`;
- `internalcalc`: cálculo por `OnCalcFields` e `DefaultExpression`, armazenado por registro;
- `lookup`: chave válida e ausente em campo `fkLookup`;
- `aggregate`: `TAggregateField`, coleção `Aggregates`, append, post e cancel;
- `join`: update automático delimitado a `product`, com SQL capturado por trace;
- `conflict`: `TFDUpdateSQL` com `OLD_version` e conflito otimista reproduzido.

```powershell
.\scripts\validate-chapter-08.ps1 `
  -AdminPassword '<senha-administrativa>' `
  -AppPassword '<senha-do-laboratório>'
```

O mesmo fonte é compilado para Win32/Win64 e executado contra SQLite/Firebird. Traces,
binários, bancos e credenciais permanecem em `.deps`, fora do Git.
