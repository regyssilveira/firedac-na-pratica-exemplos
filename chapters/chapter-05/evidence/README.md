# Evidência — capítulo 5

**Data:** 3 de setembro de 2026

**Ambiente:** RAD Studio 13 Florence, Delphi 37.0; Firebird 5.0.4 por TCP;
SQLite estático do FireDAC; clientes Firebird nativos Win32 e Win64.

Comando reproduzível: `scripts/validate-chapter-05.ps1`.

## Matriz executada

| Exemplo | SQLite Win32 | SQLite Win64 | Firebird Win32 | Firebird Win64 |
|---|---:|---:|---:|---:|
| EX-05-01 — lista com `TFDQuery` | aprovado | aprovado | aprovado | aprovado |
| EX-05-02 — DML com `ExecSQL` | aprovado | aprovado | aprovado | aprovado |
| EX-05-03 — `TFDCommand` reutilizável | aprovado | aprovado | aprovado | aprovado |
| EX-05-04 — chave gerada | aprovado | aprovado | aprovado | aprovado |
| EX-05-05 — paginação determinística | aprovado | aprovado | aprovado | aprovado |

Cada modo foi executado em processo independente. Os ensaios de escrita abriram
transação explícita e terminaram em `Rollback`; os três registros do seed permaneceram
inalterados.

## Descobertas incorporáveis ao texto

- A coluna `id INTEGER PRIMARY KEY` do SQLite chegou ao dataset como
  `TIntegerField`; `BIGINT IDENTITY` do Firebird chegou como `TLargeintField`.
  `price` foi `TFMTBCDField` nos dois drivers. DDL semelhante não prova classe de
  campo idêntica.
- Antes de `TFDCommand.Prepare`, os parâmetros `delta` e `id` precisaram receber
  `DataType`. Sem isso, o SQLite produziu a exceção FireDAC `-335`, pois não conseguiu
  inferir o tipo de `delta` na expressão aritmética.
- `RowsAffected` distinguiu uma linha conhecida de um identificador inexistente em
  todos os quatro perfis.
- `INSERT ... RETURNING id` devolveu uma chave que identificou a linha inserida nos
  dois SGBDs. No Firebird, a migration V003 reiniciou a identidade em 4 depois de o
  seed ter usado valores explícitos; sem essa sincronização, o primeiro valor gerado
  colidiria com o seed.
- Com cinco linhas, páginas de tamanho três produziram conjuntos 3 + 2, sem
  sobreposição. Sem mutação concorrente, offset e keyset devolveram a mesma segunda
  página sob `ORDER BY name, id`.

## BM-03 — offset alto versus keyset

O benchmark cria 100 mil produtos com chaves pares, fora da medição, e consulta 50
linhas na posição 90 mil. Um aquecimento é descartado e cinco repetições são
registradas por perfil. As medianas foram:

| Perfil | Offset (µs) | Keyset (µs) |
|---|---:|---:|
| SQLite Win32 | 1.117 | 103 |
| Firebird Win32 | 40.980 | 950 |
| SQLite Win64 | 1.156 | 90 |
| Firebird Win64 | 99.364 | 1.171 |

Antes da mutação, ambos começam no id 280000. O ensaio insere então uma chave ímpar
antes da fronteira já visitada. A mesma posição por offset passa a começar na última
chave da página anterior, produzindo duplicação; o cursor keyset `id > 279998`
continua começando em 280000. Essa asserção passou nas vinte repetições registradas.
O CSV `bm-03-raw.csv` conserva tempos, fronteira e estados de estabilidade.

Os valores não comparam capacidade dos SGBDs nem provam que keyset vence em qualquer
consulta. A massa, o índice, o offset e o cache são controlados neste cenário. Keyset
também exige ordenação única e não oferece salto arbitrário para “página 900” sem um
cursor ou índice auxiliar.

## Limites da evidência

O ensaio funcional comprova correção em conjunto pequeno; BM-03 acrescenta custo de
offset alto e uma escrita anterior à fronteira. Ele não mede ganho de `Prepare`,
latência de rede remota, deletes/updates concorrentes nem ordenação não única. Esses
pontos exigem experimentos específicos para cada consulta e ambiente.

## Revisão contra o manuscrito

O código e esta evidência foram confrontados com o Capítulo 5 após a execução. O
texto passou a distinguir as classes de campo observadas, documentar a tipagem dos
parâmetros antes de `Prepare`, explicar por que rollback não restaura a sequência do
Firebird e limitar a comparação de offset e keyset ao cenário sem mutação concorrente.

Os exemplos EX-05-01 a EX-05-05 podem avançar a `RV`: cada afirmação apresentada
como resultado do laboratório possui uma asserção correspondente nos quatro perfis.
`NextRecordSet` e desempenho de preparação não são promovidos como resultados deste
projeto. A concorrência de BM-03 é uma mutação determinística dentro do laboratório,
não uma simulação de carga multissessão.
