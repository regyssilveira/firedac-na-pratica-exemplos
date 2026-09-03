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

BM-04 foi executado em Win32 e Win64. Cada fonte gerou ids sequenciais, dez categorias
e seletividade exata de 10%. O caminho local mediu fetch completo e aplicação do
filtro separadamente; o remoto mediu geração e fetch apenas das linhas aceitas. Um
aquecimento foi descartado e o CSV conserva cinco repetições por perfil e massa, num
total de 60 observações. A tabela apresenta medianas.

| Perfil | Linhas | Fetch local (ms) | Filtro local (ms) | Remoto (ms) | Resultado |
|---|---:|---:|---:|---:|---:|
| SQLite Win32 | 100 | 0 | 0 | 0 | 10 |
| SQLite Win32 | 10.000 | 7 | 4 | 3 | 1.000 |
| SQLite Win32 | 1.000.000 | 727 | 358 | 262 | 100.000 |
| Firebird Win32 | 100 | 5 | 0 | 1 | 10 |
| Firebird Win32 | 10.000 | 65 | 4 | 38 | 1.000 |
| Firebird Win32 | 1.000.000 | 6.421 | 373 | 3.611 | 100.000 |
| SQLite Win64 | 100 | 0 | 0 | 0 | 10 |
| SQLite Win64 | 10.000 | 5 | 2 | 2 | 1.000 |
| SQLite Win64 | 1.000.000 | 566 | 273 | 207 | 100.000 |
| Firebird Win64 | 100 | 4 | 0 | 1 | 10 |
| Firebird Win64 | 10.000 | 65 | 3 | 37 | 1.000 |
| Firebird Win64 | 1.000.000 | 6.459 | 302 | 3.613 | 100.000 |

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

Os tempos são observações de laboratório com aquecimento e cinco repetições, mas sem
contagem de bytes no fio ou medição de memória. A massa é sintética, e o filtro remoto
não usa uma tabela persistente indexada. BM-04 sustenta a discussão de escala e
transferência, mas não publica um vencedor universal nem números de capacidade. Os
dois SGBDs usam geradores diferentes e não devem ser comparados entre si.

## Revisão contra o manuscrito

O Capítulo 7 foi confrontado com fonte, asserções e saída de BM-04. O texto limita o
bookmark ao mesmo snapshot, trata `Lookup` múltiplo como array, explica o prefixo do
range, adapta booleanos por driver e só compara tempos dentro do mesmo gerador.

EX-07-01 a EX-07-05 podem avançar a `RV`. Todos possuem asserções nos quatro perfis.
BM-04 sustenta equivalência, seletividade e as medianas registradas; memória, bytes e
tempo de primeira linha não foram promovidos como resultados. Os dados brutos estão
em `bm-04-raw.csv`.
