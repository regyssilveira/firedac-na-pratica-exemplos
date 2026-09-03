# Evidência — capítulo 14

Validação executada com FireDAC 37 nas arquiteturas Win32 e Win64:

- EX-14-01: schema explícito, índice único, localização, validação e total;
- EX-14-02: duas linhas filtradas copiadas e edição independente da origem;
- EX-14-03: `CloneCursor` compartilhou edições, enquanto a atribuição de `Data`
  importou uma cópia independente; o filtro do clone não alterou a contagem da
  origem; fechar o clone manteve a origem ativa;
- EX-14-04: ranges mestre-detalhe de 1, 2 e 0 registros;
- EX-14-05: campo `ftDataSet` com dois filhos e edição preservada.

São dez execuções: cinco contratos em cada arquitetura. Como o laboratório opera
inteiramente sobre DatS em memória, nenhum SGBD participa desta matriz; tipos trazidos
de um servidor continuam exigindo testes nos capítulos de leitura e persistência.
