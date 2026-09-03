# Evidência — capítulo 11

**Data:** 3 de setembro de 2026

**Ambiente:** RAD Studio 13 Florence, Delphi 37.0; Firebird 5.0.4 por TCP;
SQLite estático do FireDAC; clientes Firebird Win32 e Win64.

Comando reproduzível: `scripts/validate-chapter-11.ps1`.

## Matriz executada

| Exemplo | SQLite Win32 | SQLite Win64 | Firebird Win32 | Firebird Win64 |
|---|---:|---:|---:|---:|
| EX-11-01 — parâmetros | aprovado | aprovado | aprovado | aprovado |
| EX-11-02 — range local | aprovado | aprovado | aprovado | aprovado |
| EX-11-03 — chave gerada | aprovado | aprovado | aprovado | aprovado |
| EX-11-04 — cascatas | aprovado | aprovado | aprovado | aprovado |
| EX-11-05 — adapter atômico | aprovado | aprovado | aprovado | aprovado |
| EX-11-06 — `fiDetails` | aprovado | aprovado | aprovado | aprovado |
| EX-11-07 — `DetailDelay` | aprovado | aprovado | aprovado | aprovado |
| EX-11-08 — chave composta | aprovado | aprovado | aprovado | aprovado |
| EX-11-09 — mestre e três filhos | aprovado | aprovado | aprovado | aprovado |
| EX-11-10 — conflito e retry | aprovado | aprovado | aprovado | aprovado |

## Relação e identidade

EX-11-01 alternou entre dois pedidos e confirmou conjuntos 2/1, parâmetro atualizado
e `ActualDetailFields = order_id`. EX-11-02 abriu as três linhas uma vez e aplicou
ranges locais 2/1/2 com `IndexFieldNames = order_id`. EX-11-08 distinguiu duas
empresas com o mesmo número de pedido usando a chave ordenada
`company_id;order_id`.

EX-11-03 obteve uma identidade real do banco e gravou um item com essa FK. Os valores
concretos diferiram, como esperado: SQLite reutilizou 111003 nos bancos descartáveis;
Firebird produziu 1 e 2 nas execuções observadas. O contrato exige chave positiva e
integridade referencial, não um número específico.

EX-11-09 mostrou uma condição estrutural importante: os dois `TFDQuery` precisam
compartilhar o mesmo `TFDSchemaAdapter` para que seus DatS participem do mesmo grafo.
A mudança de -1001 para 119001 foi propagada aos três detalhes pendentes.

## Cache, atraso e cascatas

Com `fiDetails`, a navegação A/B/A manteve três linhas no DatS. O evento
`BeforeGetRecords` ocorreu três vezes; portanto, ele não é apresentado como contador
de viagens físicas ao banco. A evidência aqui é a retenção dos conjuntos no cache.

`DetailDelay = 150` suprimiu a navegação intermediária e terminou no mestre B com
duas execuções observadas. O ensaio também revelou que o provedor Console registra
um timer inerte. O executável seleciona explicitamente o provedor `Forms`, inclui
`FireDAC.VCLUI.Wait` e bombeia mensagens; aplicações GUI já possuem essa infraestrutura.

EX-11-04 separou responsabilidades. `DetailCascade` removeu os filhos da visão local
quando o mestre foi excluído do journal compartilhado. Depois de cancelar o journal,
um `DELETE` direto no servidor removeu os filhos pela FK `ON DELETE CASCADE`.

## Atomicidade e conflito

EX-11-05 editou o total do mestre e acrescentou um item com quantidade zero. O
`TFDSchemaAdapter.ApplyUpdates` registrou um erro de constraint; o rollback manteve
o total persistido em 25, não gravou o item e preservou `UpdatesPending` nos dois
datasets. `CancelUpdates` só foi chamado depois dessas asserções.

EX-11-10 usou SQL otimista com `OLD_id` e `OLD_total`. Uma segunda conexão mudou o
total de 25 para 27. A primeira tentativa detectou zero linhas afetadas, foi revertida
e preservou a intenção local. Só então o teste cancelou o delta, releu 27, reaplicou
a decisão 26 numa nova transação, confirmou o banco e chamou `CommitUpdates`.

## Limites

Esta matriz valida Firebird e SQLite, Win32 e Win64. Não transforma callbacks em
métrica de rede, não mede centenas de mestres, não cobre nested datasets e não afirma
o mesmo comportamento para PostgreSQL ou MySQL sem execução própria. Esses caminhos
permanecem como portabilidade orientada, não como evidência executada.

EX-11-01 a EX-11-10 podem avançar a `RV` após revisão cruzada do manuscrito.
