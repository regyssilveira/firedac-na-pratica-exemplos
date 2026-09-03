# Capítulo 18 — Medindo, diagnosticando e otimizando

Este laboratório mede cinco contratos: N+1 versus lote, reutilização/preparo,
fetch parcial versus total, plano do SGBD e relatório técnico sanitizado.

Execute a matriz completa com:

```powershell
.\scripts\validate-chapter-18.ps1 -AdminPassword '<senha>' -AppPassword '<senha>'
```

Os resultados são locais ao ambiente documentado e não constituem promessa universal
de desempenho. Os modos comparam resultados equivalentes por contagem e checksum.
