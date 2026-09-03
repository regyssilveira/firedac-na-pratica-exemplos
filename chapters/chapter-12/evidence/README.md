# Evidência — capítulo 12

**Data:** 3 de setembro de 2026

**Ambiente:** RAD Studio 13 Florence, Delphi 37.0; Firebird 5.0.4 por TCP;
SQLite estático do FireDAC; clientes Firebird Win32 e Win64.

Comando reproduzível: `scripts/validate-chapter-12.ps1`.

## Matriz executada

| Exemplo | SQLite Win32 | SQLite Win64 | Firebird Win32 | Firebird Win64 |
|---|---:|---:|---:|---:|
| EX-12-01 — IN/OUT | ausência aprovada | ausência aprovada | aprovado | aprovado |
| EX-12-02 — escalar/tabular | fallback aprovado | fallback aprovado | aprovado | aprovado |
| EX-12-03 — resultados seguintes | nenhum | nenhum | nenhum | nenhum |
| EX-12-04 — fechamento | adapter aprovado | adapter aprovado | aprovado | aprovado |
| EX-12-05 — evento | local aprovado | local aprovado | servidor aprovado | servidor aprovado |

## Rotinas e resultados

No Firebird, `TFDStoredProc.Prepare` derivou três parâmetros de `GET_ORDER_STATE`:
`P_ORDER_ID` como `ptInput`, `P_STATUS` e `P_TOTAL` como `ptOutput`. `ExecProc`
devolveu `PENDING` e zero para o fixture. No SQLite, a consulta a `sqlite_master`
confirmou que não há objetos persistentes `procedure` ou `function`.

`ORDER_TOTAL` calculou 35 no Firebird e `ORDER_LINES` devolveu duas linhas. O adapter
SQLite obteve o mesmo resultado de domínio pela view `order_total_view` e por um
`SELECT` comum. A saída distingue equivalência do resultado de equivalência física.

EX-12-03 abriu um único `SELECT`, consumiu seu valor e chamou `NextRecordSet`. O
dataset ficou inativo nos quatro perfis. O teste prova o término correto do fluxo; não
alega que Firebird ou SQLite suportam procedures com vários conjuntos independentes.

## Fechamento idempotente

No Firebird, `CLOSE_ORDER` calculou 35, alterou o estado para `CLOSED` e inseriu um
evento outbox na mesma transação. A segunda chamada devolveu `changed = False` e a
contagem da outbox continuou em um. No SQLite, o adapter Delphi executou o mesmo
contrato em SQL parametrizado sob uma transação explícita. Em ambos, resultado e
atomicidade são comuns; a tecnologia server-side não é.

## Dois significados de evento

No Firebird, o alerter foi registrado antes da alteração. Outra conexão iniciou uma
transação, mudou o pedido e fez `Commit`; somente então o trigger com `POST_EVENT`
entregou `ORDER_CLOSED`. O callback foi seguido por consulta compensatória que
confirmou o estado `CLOSED`.

O SQLite reportou `EventKinds = Events`. O código-fonte do driver mostra que o
FireDAC registra a função `POST_EVENT` e distribui a mensagem aos alerters da mesma
conexão física. `TFDEventAlerter.Signal` entregou exatamente um alerta local. Isso não
é evento de um servidor nem canal durável entre processos.

## Limites

Não foram testadas rotinas com overload, packages, BLOB de saída, parâmetros default,
cancelamento, perda de conexão ou múltiplos recordsets nativos de outro SGBD. Evento
não foi tratado como fila durável; outbox continua sendo a garantia de persistência.

EX-12-01 a EX-12-05 podem avançar a `RV` após revisão cruzada do manuscrito.
