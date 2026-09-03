# Capítulo 10 — transações sem surpresas

- `commit`: confirma pedido, item, estoque e outbox como uma unidade;
- `rollback`: provoca uma constraint no detalhe e prova ausência de cabeçalho parcial;
- `nested`: reverte somente o trabalho interno com nesting/savepoint;
- `isolation`: observa quatro níveis com duas conexões independentes;
- `helper`: testa ownership, commit, rollback e participação em transação externa.

```powershell
.\scripts\validate-chapter-10.ps1 `
  -AdminPassword '<senha-administrativa>' `
  -AppPassword '<senha-do-laboratório>'
```

Os bancos são descartáveis e cada modo restaura sua massa de teste. Diferenças de
isolamento são resultados por driver, não uma tabela universal inferida dos nomes.
