# Capítulo 16 — Cached Updates e reconciliação

Laboratório de journal, undo/savepoint, conflito otimista, rollback com nova tentativa
e cache centralizado mestre-detalhe.

Os cinco modos são `journal`, `undo`, `conflict`, `transaction` e `centralized`. O
programa usa o provider de espera `Console`, pois `TFDSchemaAdapter.ApplyUpdates`
solicita a factory de wait cursor mesmo sem interface visual.

```powershell
.\scripts\validate-chapter-16.ps1 `
  -AdminPassword '<senha-sysdba>' -AppPassword '<senha-firestore-app>'
```
