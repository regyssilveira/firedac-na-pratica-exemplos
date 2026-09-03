# Evidência — capítulo 3

**Data:** 3 de setembro de 2026

**Ambiente:** RAD Studio 13 Florence, Delphi 37.0; Firebird 5.0.4; PostgreSQL 18
ativo em TCP 5432; SQLite estático do FireDAC.

Comando reproduzível: `scripts/validate-chapter-03.ps1`.

## Resultados

| Exemplo | Estado comprovado | Win32 | Win64 | Limite atual |
|---|---|---:|---:|---|
| EX-03-01 | executado | aprovado | aprovado | Parâmetros diretos e definição privada abriram SQLite. |
| EX-03-02 | executado | aprovado | aprovado | Arquivo absoluto foi criado sem senha e usado para abrir SQLite. |
| EX-03-03 | compilado/parcial | local aprovado | local aprovado | Perfis remoto e alias foram construídos, não conectados. |
| EX-03-04 | compilado | aprovado | aprovado | `PGAdvanced` foi validado sem abrir PostgreSQL. |
| EX-03-05 | executado | aprovado | aprovado | Três nomes aceitos; nome desconhecido rejeitado antes da conexão. |

## Descoberta sobre persistência

`FDManager.AddConnectionDef(..., True)` marcou a definição como persistente, mas não
criou o arquivo por si só no ensaio. A chamada explícita a
`FDManager.SaveConnectionDefFile` realizou a gravação. O resultado coincide com o
código-fonte FireDAC 37: `AddConnectionDef` chama `MarkPersistent`; o método de save
invoca `ConnectionDefs.Save`.

## PostgreSQL e alias Firebird

O serviço PostgreSQL respondeu em `127.0.0.1:5432`, mas a autenticação SCRAM rejeitou
a credencial convencional de laboratório. Nenhuma conta, senha ou regra `pg_hba.conf`
foi alterada. A instalação disponível possui cliente x64; portanto, conexão real e
matriz Win32/Win64 continuam pendentes.

O Firebird abriu o banco descartável por TCP local. O perfil remoto preservou o
caminho como caminho do servidor e o perfil de alias preservou o nome lógico, mas não
havia alias de laboratório configurado. Esses dois caminhos não são descritos como
executados.

Binários, bancos, arquivos de definição e credenciais permaneceram fora do Git.
