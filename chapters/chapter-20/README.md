# Capítulo 20 — Metadados, eventos e automação

O laboratório confronta nomes, campos/chaves/índices, rotinas, um snapshot de explorer
e eventos com fallback outbox em SQLite e Firebird.

```powershell
.\scripts\validate-chapter-20.ps1 -AdminPassword '<senha>' -AppPassword '<senha>'
```

O usuário de aplicação é deliberadamente restrito. Por isso a matriz distingue objeto
existente, objeto pertencente ao usuário e objeto visível por privilégio.
