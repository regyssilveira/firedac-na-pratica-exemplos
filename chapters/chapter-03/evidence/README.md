# Evidência — capítulo 3

**Data:** 4 de setembro de 2026

**Ambiente:** RAD Studio 13 Florence, Delphi 37.0; Firebird 5.0.4 local e em
contêiner independente; PostgreSQL 18 em contêiner; SQLite estático do FireDAC.

Comandos reproduzíveis: `scripts/validate-chapter-03.ps1` e
`scripts/validate-chapter-03-external.ps1`.

## Resultados

| Exemplo | Estado comprovado | Win32 | Win64 | Limite atual |
|---|---|---:|---:|---|
| EX-03-01 | executado | aprovado | aprovado | Parâmetros diretos e definição privada abriram SQLite. |
| EX-03-02 | executado | aprovado | aprovado | Arquivo absoluto foi criado sem senha e usado para abrir SQLite. |
| EX-03-03 | revisado | aprovado | aprovado | TCP local, endpoint independente e alias executados. |
| EX-03-04 | revisado | aprovado | aprovado | `PGAdvanced` autenticado e observado no servidor. |
| EX-03-05 | executado | aprovado | aprovado | Três nomes aceitos; nome desconhecido rejeitado antes da conexão. |

## Descoberta sobre persistência

`FDManager.AddConnectionDef(..., True)` marcou a definição como persistente, mas não
criou o arquivo por si só no ensaio. A chamada explícita a
`FDManager.SaveConnectionDefFile` realizou a gravação. O resultado coincide com o
código-fonte FireDAC 37: `AddConnectionDef` chama `MarkPersistent`; o método de save
invoca `ConnectionDefs.Save`.

## PostgreSQL e alias Firebird

O laboratório descartável abriu o Firebird por TCP em um segundo endpoint usando
tanto o caminho do servidor quanto o alias `FIRESTORE_PROD`. No PostgreSQL, a sessão
autenticada confirmou no próprio servidor o valor `FireDACNaPratica` recebido por
`PGAdvanced`. Os dois cenários passaram com clientes nativos Win32 e Win64.

Binários, bancos, arquivos de definição e credenciais permaneceram fora do Git.

## Revisão contra o manuscrito

Os cinco exemplos foram confrontados com o Capítulo 3 e estão em `RV`. O texto
incorporou a chamada explícita a `SaveConnectionDefFile` e separou configuração,
compilação e sessão autenticada.
