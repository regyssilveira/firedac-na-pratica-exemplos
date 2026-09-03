# Capítulo 17 — Local SQL e composição de fontes

Laboratório de SQL local sobre MemTable, CSV tipado, duas conexões, agregação
comparada e limites do dialeto SQLite embutido.

O exemplo de duas conexões faz `FetchAll` e confere três linhas por origem antes do
join. Os nomes registrados evitam o prefixo `sqlite_`, reservado pelo engine local.

```powershell
.\scripts\validate-chapter-17.ps1 `
  -AdminPassword '<senha-sysdba>' -AppPassword '<senha-firestore-app>'
```
