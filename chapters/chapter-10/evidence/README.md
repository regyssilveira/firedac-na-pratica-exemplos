# Evidência — capítulo 10

**Data:** 3 de setembro de 2026

**Ambiente:** RAD Studio 13 Florence, Delphi 37.0; Firebird 5.0.4 por TCP;
SQLite estático do FireDAC; clientes Firebird Win32 e Win64.

Comando reproduzível: `scripts/validate-chapter-10.ps1`.

## Matriz executada

| Exemplo | SQLite Win32 | SQLite Win64 | Firebird Win32 | Firebird Win64 |
|---|---:|---:|---:|---:|
| EX-10-01 — commit do pedido | aprovado | aprovado | aprovado | aprovado |
| EX-10-02 — rollback do detalhe | aprovado | aprovado | aprovado | aprovado |
| EX-10-03 — nesting/savepoint | aprovado | aprovado | aprovado | aprovado |
| EX-10-04 — quatro isolamentos | aprovado | aprovado | aprovado | aprovado |
| EX-10-05 — helper transacional | aprovado | aprovado | aprovado | aprovado |

## Unidade de negócio

O modelo M0 recebeu `sales_order`, `sales_order_item`, `inventory` e `outbox_event`,
com chaves estrangeiras, checks e índices. EX-10-01 confirmou na mesma transação o
cabeçalho, um item, a baixa de estoque de 100 para 98 e o evento outbox. As quatro
asserções foram feitas depois do `Commit`; o fixture foi restaurado no `finally`.

EX-10-02 inseriu o cabeçalho e tentou inserir quantidade zero. A constraint do banco
produziu `EFDDBEngineException`; o rollback encerrou a transação e as consultas em
seguida provaram zero cabeçalhos e zero itens. O teste não aceita uma exceção local
simulada como prova da constraint.

## Nesting e savepoint

Com `TxOptions.EnableNested = True`, a unidade externa inseriu um evento, a unidade
interna inseriu outro e fez `Rollback`. A conexão continuou em transação, o evento
interno desapareceu e um segundo evento externo foi inserido. Após o commit externo,
existiam exatamente os dois eventos externos nos quatro perfis.

## Isolamento observado

Cada nível começou com conexões novas, valor restaurado e duas sessões independentes.
`LockWait = False` e `BusyTimeout = 100` mantiveram conflitos limitados no tempo.

| Driver | Nível solicitado | escritor confirmou | releitura mudou |
|---|---|---:|---:|
| SQLite | `xiDirtyRead` | sim | sim |
| SQLite | `xiReadCommitted` | não | não |
| SQLite | `xiRepeatableRead` | não | não |
| SQLite | `xiSerializible` | não | não |
| Firebird | `xiDirtyRead` | sim | sim |
| Firebird | `xiReadCommitted` | sim | sim |
| Firebird | `xiRepeatableRead` | sim | não |
| Firebird | `xiSerializible` | não | não |

Win32 e Win64 produziram a mesma matriz. “Escritor não confirmou” agrega a rejeição
esperada pelo banco/driver neste ensaio; não a chama automaticamente de deadlock. O
resultado demonstra o comportamento desta sequência e configuração, não todos os
fenômenos permitidos por cada nível.

## Ownership do helper

EX-10-05 comprovou três caminhos. Fora de uma transação, o helper iniciou e confirmou
o callback bem-sucedido. Diante de falha intencional, reverteu sua unidade e preservou
a exceção original. Quando chamado dentro de uma transação externa, não confirmou nem
encerrou a unidade do chamador; o rollback externo removeu seu trabalho.

## Limites

O ensaio não simula perda de rede durante commit, deadlock circular, retaining nem
retry. A matriz não substitui documentação do SGBD nem teste da carga real. Esses
limites permanecem explícitos no manuscrito e nos capítulos de concorrência e
recuperação.

EX-10-01 a EX-10-05 possuem implementação, compilação e execução comprovadas. A
promoção a `RV` depende do confronto final entre resultados, fonte e capítulo.
