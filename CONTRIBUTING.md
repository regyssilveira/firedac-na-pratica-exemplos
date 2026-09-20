# Contribuindo

Abra uma issue antes de alterações amplas. Pull requests devem indicar o ID do
exemplo, versão do Delphi, plataforma, SGBD, biblioteca cliente e comandos usados.

Não inclua código proprietário, conteúdo integral do livro, credenciais ou dados de
produção. Um exemplo só pode avançar de estado quando a evidência exigida existir.

## Código

- A linha de base é Delphi 13 Florence, compilador 37.0.
- Nunca use `with`; mantenha explícito o objeto de cada propriedade e método.
- Use nomes descritivos e não omita código executável com reticências.
- Use strings multilinha para SQL, DDL, JSON, templates e qualquer texto com mais de
  uma linha lógica. Não concatene linhas de SQL com `+`.
- Ao tocar em um exemplo legado, modernize também as strings multilinha daquele
  exemplo.

## Gates

- `IM`: fonte e instruções implementadas;
- `CP`: compilação limpa registrada;
- `EX`: execução e resultado esperado registrados;
- `EC`: evidência parcial registrada, com um gate externo explícito ainda pendente;
- `RV`: revisão técnica, segurança e sincronização com a edição concluídas.
