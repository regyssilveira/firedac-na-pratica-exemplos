# Capítulo 3 — Conexões, drivers e definições

`Chapter03Checks.dpr` separa cada cenário num processo próprio para evitar que o
estado global do manager esconda diferenças entre definições temporárias, privadas e
persistentes.

## Modos

- `temporary`: parâmetros diretamente em `TFDConnection`;
- `private`: definição nomeada não persistente;
- `persistent`: definição marcada persistente e gravada explicitamente;
- `firebird`: conexão TCP local, endpoint independente e alias de servidor;
- `postgres-config`: composição e conexão autenticada com `PGAdvanced`;
- `environment`: allowlist de desenvolvimento, teste e produção, com caso negativo.

## Validação

```powershell
.\scripts\validate-chapter-03.ps1 `
  -AdminPassword '<senha administrativa Firebird>' `
  -AppPassword '<senha descartável para FIRESTORE_APP>'
```

Para reproduzir também os cenários externos em laboratórios descartáveis:

```powershell
.\scripts\validate-chapter-03-external.ps1
```

O segundo comando cria contêineres temporários de Firebird 5.0.4 e PostgreSQL 18,
executa conexão por caminho remoto, alias e `PGAdvanced` em Win32 e Win64 e remove os
contêineres ao terminar. As senhas padrão do script são exclusivas do laboratório e
podem ser substituídas por parâmetros.
