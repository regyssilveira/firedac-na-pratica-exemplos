# Evidência — capítulo 8

**Data:** 3 de setembro de 2026

**Ambiente:** RAD Studio 13 Florence, Delphi 37.0; Firebird 5.0.4 por TCP;
SQLite estático do FireDAC; clientes Firebird Win32 e Win64.

Comando reproduzível: `scripts/validate-chapter-08.ps1`.

## Matriz executada

| Exemplo | SQLite Win32 | SQLite Win64 | Firebird Win32 | Firebird Win64 |
|---|---:|---:|---:|---:|
| EX-08-01 — calculado | aprovado | aprovado | aprovado | aprovado |
| EX-08-02 — lookup | aprovado | aprovado | aprovado | aprovado |
| EX-08-03 — agregado | aprovado | aprovado | aprovado | aprovado |
| EX-08-04 — update de join | aprovado | aprovado | aprovado | aprovado |
| EX-08-05 — `TFDUpdateSQL` | aprovado | aprovado | aprovado | aprovado |

Os três primeiros exemplos usam `TFDMemTable` e comprovam comportamento da camada de
dataset em ambos os binários. Os dois últimos executam DML real nos dois bancos.

## Campos virtuais

- `display_name` produziu `BEB-001 - Café especial`; `OnCalcFields` foi chamado três
  vezes no ensaio. Ao criar o campo em runtime, `fkCalculated` não limpou sozinho os
  `ProviderFlags`, por isso o exemplo define `ProviderFlags := []` explicitamente.
- O lookup resolveu a categoria 1 como “Bebidas” e devolveu nulo para a chave 999.
  Seu `ProviderFlags` também foi esvaziado explicitamente.
- O agregado `SUM(quantity * unit_price)` passou de 35 para 40 após `Post`; uma edição
  posterior cancelada manteve 40. `TAggregateField.Active` precisou ser configurado
  antes de abrir o dataset, além de `AggregatesActive` no dataset.

## Query com join e SQL capturado

A query juntou `product` e `category`, definiu `UpdateTableName = product`,
`KeyFields = id`, `upWhereKeyOnly` e removeu `category_name` de `ProviderFlags`.
Após `Edit`, o estado foi `dsEdit`; após `Post`, `dsBrowse`. Na mesma transação, o
preço já estava alterado no servidor; `Rollback` removeu o efeito.

Os quatro traces registraram a mesma forma lógica:

```sql
UPDATE PRODUCT
SET PRICE = ?
WHERE ID = ?
```

O script exige `UPDATE product` e rejeita qualquer `UPDATE category` no trace.
Arquivos de trace ficam em `.deps` porque podem conter parâmetros e configuração.

## Conflito otimista

Duas conexões leram/alteraram o produto. A segunda incrementou `version`; a primeira,
com snapshot antigo, executou o `ModifySQL` que inclui `id` e `OLD_version`. O FireDAC
levantou especificamente a exceção que informa zero registros atualizados em vez de
um. O teste exige esse texto, confirma que o preço não foi sobrescrito e que a versão
concorrente permaneceu. Por fim, a segunda conexão restaura o registro do laboratório.

## Limites

O ensaio não cobre cached updates, inserts com refresh de chaves, deletes, triggers,
joins de múltiplas tabelas editáveis nem reconciliação visual. Esses contratos serão
tratados nos capítulos de transação, mestre-detalhe e trabalho desconectado.
