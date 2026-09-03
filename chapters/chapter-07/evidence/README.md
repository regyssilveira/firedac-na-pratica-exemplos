# Evidência — capítulo 7

**Data:** 3 de setembro de 2026

**Ambiente:** RAD Studio 13 Florence, Delphi 37.0; Firebird 5.0.4 por TCP local;
SQLite estático do FireDAC; clientes Firebird Win32 e Win64.

Comando reproduzível: `scripts/validate-chapter-07.ps1`.

## Matriz funcional

| Exemplo | SQLite Win32 | SQLite Win64 | Firebird Win32 | Firebird Win64 |
|---|---:|---:|---:|---:|
| EX-07-01 — `Locate`, `Lookup` e bookmark | aprovado | aprovado | aprovado | aprovado |
| EX-07-02 — filtro por expressão | aprovado | aprovado | aprovado | aprovado |
| EX-07-03 — `OnFilterRecord` | aprovado | aprovado | aprovado | aprovado |
| EX-07-04 — índice e range | aprovado | aprovado | aprovado | aprovado |
| EX-07-05 — local versus remoto | aprovado | aprovado | aprovado | aprovado |

O bookmark restaurou a posição no mesmo snapshot; `Lookup` de dois campos devolveu
array `Variant` sem mover o registro; busca inexistente devolveu `Null`. O filtro por
expressão deixou um produto e sua remoção restaurou três. O callback adaptou a leitura
de `active` a `TIntegerField` no SQLite e `TBooleanField` no Firebird.

O índice `category_id;name;id` sustentou `Locate` pela chave completa e range da
categoria 1 com dois produtos. O filtro local e o `WHERE` remoto devolveram os mesmos
ids, `1,2`, antes de qualquer interpretação de custo.

## BM-04 — observação controlada

BM-04 foi executado em Win64. Cada fonte gerou ids sequenciais, dez categorias e
seletividade exata de 10%. O caminho local mediu fetch completo e aplicação do filtro
separadamente; o remoto mediu geração e fetch apenas das linhas aceitas.

| Banco | Linhas | Fetch local (ms) | Filtro local (ms) | Remoto (ms) | Resultado |
|---|---:|---:|---:|---:|---:|
| SQLite | 100 | 0 | 0 | 0 | 10 |
| SQLite | 10.000 | 4 | 2 | 1 | 1.000 |
| SQLite | 1.000.000 | 572 | 289 | 220 | 100.000 |
| Firebird | 100 | 7 | 0 | 2 | 10 |
| Firebird | 10.000 | 66 | 3 | 40 | 1.000 |
| Firebird | 1.000.000 | 6.535 | 541 | 3.639 | 100.000 |

SQLite usou CTE recursiva; Firebird usou a selectable procedure
`benchmark_product_rows`. Portanto, os números não comparam os bancos entre si. Em
cada banco, o caminho remoto transferiu 10% das linhas, enquanto o local recebeu
100% antes de filtrar.

## Descobertas do protocolo

A primeira massa Firebird usava três cruzamentos de `RDB$TYPES` e `ROW_NUMBER`. O caso
de 1 milhão demorou excessivamente e foi interrompido porque media principalmente a
forma de geração. V005 passou a criar uma procedure linear. Como o corpo PSQL contém
pontos e vírgulas, a migration usa o marcador `FIRESTORE:SINGLE-COMMAND`; o bootstrap
envia o arquivo inteiro ao driver, sem confundir terminadores de `isql` com SQL.

O literal Unicode “Chá mate” também passou a ser construído com `#$00E1` no fonte de
ensaio, eliminando dependência da code page do compilador.

## Limites

Os tempos são uma execução de laboratório, sem aquecimento, repetição estatística,
contagem de bytes no fio ou medição de memória. A massa é sintética, e o filtro remoto
não usa uma tabela persistente indexada. BM-04 sustenta a discussão de escala e
transferência, mas não publica um vencedor universal nem números de capacidade.
