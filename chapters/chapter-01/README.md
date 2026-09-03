# Capítulo 1 — O primeiro acesso ao banco

Este diretório contém os cinco exemplos do capítulo em um conjunto pequeno e
reproduzível. O mesmo fonte é compilado nativamente para Win32 e Win64.

## Projetos

- `Chapter01Vcl.dpr`: formulário com `TFDConnection`, `TFDQuery`, `TDataSource` e
  `TDBGrid`; parâmetros sensíveis entram somente em execução.
- `Chapter01Checks.dpr`: verificações console para SQLite, Firebird, parâmetro e
  biblioteca cliente ausente.

O DFM conserva apenas ligações estruturais. Não contém senha, conexão aberta nem
dataset ativo. O modo `CH01_AUTORUN=1` existe para o teste automatizado do formulário;
no uso normal, a conexão só abre quando o leitor pressiona **Abrir catálogo**.

## Validação completa

Em uma máquina com RAD Studio 13 e Firebird 5 ativo:

```powershell
.\scripts\validate-chapter-01.ps1 `
  -AdminPassword '<senha administrativa local>' `
  -AppPassword '<senha descartável para FIRESTORE_APP>'
```

O script cria bancos descartáveis em `.deps`, compila os projetos nas duas
arquiteturas, executa os casos positivos e negativos e inspeciona o DFM. Senhas,
executáveis, clientes e bancos não são versionados.
