# Capítulo 3 — Conexões, drivers e definições

`Chapter03Checks.dpr` separa cada cenário num processo próprio para evitar que o
estado global do manager esconda diferenças entre definições temporárias, privadas e
persistentes.

## Modos

- `temporary`: parâmetros diretamente em `TFDConnection`;
- `private`: definição nomeada não persistente;
- `persistent`: definição marcada persistente e gravada explicitamente;
- `firebird`: conexão TCP local e construção dos perfis remoto/alias;
- `postgres-config`: composição `PGAdvanced` sem autenticação;
- `environment`: allowlist de desenvolvimento, teste e produção, com caso negativo.

## Validação

```powershell
.\scripts\validate-chapter-03.ps1 `
  -AdminPassword '<senha administrativa Firebird>' `
  -AppPassword '<senha descartável para FIRESTORE_APP>'
```

O PostgreSQL 18 local exige uma credencial que não pertence ao repositório. Sem ela,
o exemplo valida somente a composição e permanece em `CP`. O perfil remoto/alias do
Firebird também permanece em `CP` até ser executado contra um segundo endpoint e um
alias configurado no servidor.
