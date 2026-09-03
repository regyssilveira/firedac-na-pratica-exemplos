# Capítulo 7 — navegação, filtros e índices locais

Modos funcionais:

- `locate`: `Locate`, `Lookup`, bookmark e busca inexistente;
- `filter`: filtro por expressão e remoção do filtro;
- `callback`: `OnFilterRecord` com booleano adaptado ao tipo do campo;
- `index`: índice composto, `Locate` e range por categoria;
- `compare`: equivalência entre filtro local e `WHERE` parametrizado.

O modo `benchmark` executa BM-04 com 100, 10 mil e 1 milhão de linhas sintéticas,
seletividade de 10%, comparando fetch completo + filtro local com resultado reduzido
no servidor. Os tempos são observações do laboratório, não promessas de desempenho.

```powershell
.\scripts\validate-chapter-07.ps1 `
  -AdminPassword '<senha-administrativa>' `
  -AppPassword '<senha-do-laboratório>'
```

Os cinco exemplos funcionais usam o mesmo fonte em Win32/Win64 e SQLite/Firebird.
BM-04 descarta um aquecimento e registra cinco repetições nos quatro perfis. Os dados
brutos ficam em `evidence/bm-04-raw.csv`; arquitetura continua sendo contexto da
medição, não explicação causal automática para diferenças.
