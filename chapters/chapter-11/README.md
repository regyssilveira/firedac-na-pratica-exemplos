# Capítulo 11 — mestre-detalhe e atualizações coordenadas

- `parameter`: relação por parâmetro e resolução de `ActualDetailFields`;
- `range`: filtro local com índice compatível;
- `generated`: chave produzida pelo banco e usada pelo detalhe;
- `cascade`: cascata no cache FireDAC versus FK no servidor;
- `atomic`: journal centralizado e rollback integral após erro no detalhe;
- `cache`: retenção dos conjuntos de detalhes com `fiDetails`;
- `delay`: supressão da navegação intermediária com timer VCL;
- `composite`: chave composta explícita e ordenada;
- `newdetails`: chave temporária propagada a três filhos;
- `conflict`: conflito otimista, rollback, releitura e nova tentativa.

```powershell
.\scripts\validate-chapter-11.ps1 `
  -AdminPassword '<senha-administrativa>' `
  -AppPassword '<senha-do-laboratório>'
```

O script recria o M0, compila para Win32 e Win64 e executa os dez contratos em
SQLite e Firebird. Os fixtures são descartáveis e restaurados por cenário.
