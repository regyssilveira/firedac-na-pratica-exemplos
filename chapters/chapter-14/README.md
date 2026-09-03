# Capítulo 14 — TFDMemTable de verdade

Laboratório independente de banco para criação de schema, `CopyDataSet`,
`CloneCursor`, mestre-detalhe em memória e dataset aninhado.

Os modos executáveis são `create`, `copy`, `clone`, `master-detail` e `nested`.
O modo `clone` também testa a atribuição de `Data`. No FireDAC 37 observado,
`CloneCursor` compartilha registros, mas o setter de `Data` importa a view para outra
tabela; editar esse destino não altera a origem. O filtro do clone não reduz a view
da origem.

Execute a matriz Win32/Win64:

```powershell
.\scripts\validate-chapter-14.ps1
```
