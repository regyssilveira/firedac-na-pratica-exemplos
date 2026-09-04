# FireDAC na Prática — exemplos oficiais

Repositório público dos exemplos do livro **FireDAC na Prática: Do primeiro acesso
ao banco às técnicas avançadas com Delphi**, de Regys Silveira.

> Estado: preparação editorial. O FireStore M0 já possui evidência executável;
> os demais exemplos ainda não representam uma edição publicada do livro. Consulte
> o manifesto antes de assumir que um projeto foi compilado ou executado.

## Linha de base

- RAD Studio 13 Florence / Delphi 37.0;
- um único código-fonte para Windows 32-bit e Windows 64-bit, ambos validados;
- sintaxe moderna do Delphi, incluindo variáveis inline, inferência de tipo e strings
  multilinha onde elas tornam os exemplos mais claros;
- Firebird 5.0.x como SGBD principal;
- PostgreSQL 18.x, SQLite embutido e MySQL 8.4 LTS como laboratórios complementares.

## Organização

```text
chapters/          projetos independentes por capítulo
firestore/         aplicação evolutiva e scripts dos SGBDs
infra/             ambiente local reproduzível, sem credenciais
manifest/          estado e evidências dos exemplos
scripts/           validações e automações
```

Cada exemplo percorre os estados:

`PL` planejado → `IM` implementado → `CP` compilado → `EX` executado → `RV` revisado.

`EC` significa **evidência condicionada**: uma parte relevante já foi executada e
documentada, mas ainda existe um gate externo explícito — por exemplo, TLS com CA e
hostname ou implantação em uma máquina limpa. Um exemplo em `EC` não pode ser
apresentado como integralmente revisado.

Somente exemplos em `RV` podem ser apresentados no livro como tecnicamente revisados.

## Segurança

Nunca envie senhas, certificados privados, bancos pessoais, dumps de produção ou
arquivos `.env`. Use os modelos versionados e forneça segredos apenas em execução.

## Win32 e Win64

O repositório usa um perfil de fonte independente de arquitetura: não é preciso
alterar o código para escolher Win32 ou Win64. Delphi, porém, gera um binário nativo
por alvo; não existe executável Windows `AnyCPU`. Distribua a pasta Win32, a Win64 ou
ambas, conforme o público.

Os perfis Firebird suportam os dois alvos a partir do mesmo código. Execute
`scripts/install-firebird-clients.ps1 -Architecture Both`; o script baixa os kits
oficiais, valida seus hashes e separa os clientes por arquitetura. Consulte
`infra/firebird/README.md`.

## Licença

Código autoral distribuído sob a Apache License 2.0. Exemplos ou dependências de
terceiros continuam sujeitos às respectivas licenças e devem ser identificados.
Exemplos oficiais do livro FireDAC na Prática, de Regys Silveira
