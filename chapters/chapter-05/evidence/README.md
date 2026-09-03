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

## Limites da evidência

O ensaio comprova correção funcional em conjunto pequeno. Ele não mede ganho de
desempenho de `Prepare`, custo de offsets altos nem comportamento sob alterações
concorrentes. Esses pontos exigem experimentos específicos nos capítulos de fetch,
concorrência e desempenho.
