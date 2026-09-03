# Capítulo 12 — stored procedures, funções e serviços do SGBD

- `procedure`: deriva e executa parâmetros IN/OUT no Firebird; registra a ausência no SQLite;
- `function`: função escalar e procedure selecionável Firebird versus view/SELECT SQLite;
- `multiset`: consome um conjunto e detecta seu término sem presumir um próximo;
- `close`: fecha pedido e grava outbox uma única vez, com retry idempotente;
- `event`: compara evento transacional entre conexões no Firebird e `Events` local SQLite.

```powershell
.\scripts\validate-chapter-12.ps1 `
  -AdminPassword '<senha-administrativa>' `
  -AppPassword '<senha-do-laboratório>'
```

A migration V008 instala função, procedures e trigger no Firebird. No SQLite, ela
instala somente a view de total; o adapter de domínio permanece declarado no cliente.
