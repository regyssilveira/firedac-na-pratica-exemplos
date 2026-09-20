# Diretrizes de código dos exemplos

Estas regras valem para todo código criado ou alterado neste repositório.

## Linha de base

- Considere sempre RAD Studio 13 Florence, Delphi 13 e compilador 37.0.
- Use os recursos atuais da linguagem quando aumentarem clareza e segurança, como
  variáveis inline, inferência de tipo e strings multilinha.
- Não sugira compatibilidade com Delphi antigo sem requisito e validação explícitos.

## Código explícito

- Nunca use `with`.
- Escreva explicitamente o objeto que recebe uma propriedade ou executa um método.
- Use nomes descritivos. Prefixos convencionados para componentes Delphi são
  permitidos; abreviações vagas ou encurtamentos sem necessidade não são.
- Não use reticências, ramos omitidos ou pseudocódigo em fontes executáveis.

## Strings

- Use strings multilinha do Delphi 13 para SQL, DDL, JSON, templates e qualquer
  conteúdo com mais de uma linha lógica.
- Não construa SQL multilinha concatenando literais terminados em `+`.
- Strings simples ficam reservadas a conteúdo genuinamente curto e de uma linha.

## Validação

- Código novo deve obedecer às regras imediatamente.
- Ao modificar um exemplo legado, elimine nele concatenações multilinha antigas.
- O mesmo fonte deve continuar compilável para Win32 e Win64, salvo limitação
  expressamente documentada.
