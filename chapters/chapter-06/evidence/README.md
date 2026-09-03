# Evidência — capítulo 6

**Data:** 3 de setembro de 2026

**Ambiente:** RAD Studio 13 Florence, Delphi 37.0; Firebird 5.0.4 por TCP;
SQLite estático do FireDAC; clientes Firebird Win32 e Win64.

Comando reproduzível: `scripts/validate-chapter-06.ps1`.

## Matriz executada

| Exemplo | SQLite Win32 | SQLite Win64 | Firebird Win32 | Firebird Win64 |
|---|---:|---:|---:|---:|
| EX-06-01 — parâmetros opcionais | aprovado | aprovado | aprovado | aprovado |
| EX-06-02 — macro e allowlist | aprovado | aprovado | aprovado | aprovado |
| EX-06-03 — data, hora e fuso | aprovado | aprovado | aprovado | aprovado |
| EX-06-04 — BLOB por stream | aprovado | aprovado | aprovado | aprovado |
| EX-06-05 — matriz de tipos | aprovado | aprovado | aprovado | aprovado |

Os modos foram executados em processos independentes. Toda escrita ocorreu em
transação explícita terminada em `Rollback`.

## Resultados observados

| Conceito | SQLite | Firebird 5 |
|---|---|---|
| chave `id` | `TIntegerField` | `TLargeintField` |
| `NUMERIC(18,2)` | `TFMTBCDField` | `TFMTBCDField` |
| booleano lógico | `TIntegerField`, valor 1 | `TBooleanField`, valor `True` |
| UUID textual | `TWideMemoField` para `TEXT` | `TWideStringField` para `CHAR(36)` |
| instante | `TWideMemoField`, ISO 8601 UTC | `TSQLTimeStampOffsetField`, deslocamento -03:00 |
| BLOB binário | hash e bytes preservados | hash e bytes preservados |

O BLOB determinístico continha 8.192 bytes. Antes e depois do round-trip, seu SHA-256
foi `dbad062eb0fd46ce757919db4fa215ae96210fb1dda443169a204946e385128d`.

Os filtros opcionais produziram contagens 3, 2, 1 e 0 para as quatro combinações
testadas. Os parâmetros receberam tipo antes de `Clear`, porque `NULL` sozinho não
carrega informação de tipo. A entrada estrutural `price; delete from product` foi
rejeitada pela conversão para enumeração antes de alcançar a macro; a tabela continuou
com três registros.

No Firebird, `ftTimeStampOffset` preservou o deslocamento -03:00 e a fração de
milissegundo do valor de ensaio. No SQLite, o esquema deliberadamente adotou texto
ISO 8601 UTC (`2026-09-03T15:34:56.789Z`); isso é uma política da aplicação, não um
tipo temporal nativo do SQLite.

## Limites

A matriz não prova os tipos de PostgreSQL e MySQL, UUID nativo, datas históricas,
regras de horário de verão, BLOBs de grande volume nem efeito de filtros opcionais
nos planos. Esses experimentos permanecem destinados aos capítulos apropriados.
