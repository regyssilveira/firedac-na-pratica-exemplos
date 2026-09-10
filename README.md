# FireDAC na Prática — exemplos oficiais

Repositório público dos exemplos do livro **FireDAC na Prática: Do primeiro acesso
ao banco às técnicas avançadas com Delphi**, de Regys Silveira.

> Estado do repositório: 109 exemplos estão revisados (`RV`) e um permanece com
> evidência condicionada (`EC`). O item condicionado é `EX-21-04`, que depende da
> validação do pacote Win32/Win64 em uma máquina limpa. Consulte o manifesto antes
> de assumir o estado técnico de qualquer exemplo.

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

## Comece por aqui

1. Leia `manifest/examples.json` para localizar o ID do exemplo e seu estado de
   validação.
2. Comece pelo Capítulo 1 em `chapters/chapter-01/`; seu README descreve os
   pré-requisitos, a compilação e o resultado esperado.
3. Para a aplicação evolutiva, siga `firestore/README.md`. O marco M0 é o ponto de
   partida para migrations, seed e smoke tests em SQLite e Firebird.
4. Copie `.env.example` apenas como referência de nomes de variáveis. Informe
   credenciais reais exclusivamente em tempo de execução.
5. Valide a estrutura pública do catálogo com:

   ```powershell
   .\scripts\validate-manifest.ps1
   ```

Os scripts de capítulo e do FireStore exigem Windows, RAD Studio 13, as bibliotecas
cliente apropriadas e, quando indicado, um SGBD local. Cada README de capítulo
declara seus pré-requisitos e o comando de validação correspondente.

## O que a automação pública valida

O GitHub Actions valida o manifesto em todo push e pull request: formato, IDs
únicos, estados permitidos e existência dos arquivos de evidência indicados. A
compilação e a execução dos laboratórios não são executadas pelo GitHub Actions,
pois dependem de RAD Studio, drivers e serviços de banco configurados no ambiente
de validação. As evidências e os comandos reproduzíveis ficam documentados nos
diretórios dos capítulos e em `firestore/`.

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
