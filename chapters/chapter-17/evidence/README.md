# Evidência — capítulo 17

Validação executada com FireDAC 37 em SQLite/Firebird e Win32/Win64:

- EX-17-01: MemTable agrupada localmente em dois estados; soma ativa 33,40;
- EX-17-02: CSV UTF-8 tipado participou de `LEFT JOIN`; chave ausente virou zero;
- EX-17-03: query SQLite e query Firebird foram materializadas com três linhas cada
  e compostas pelo engine local;
- EX-17-04: soma local coincidiu com a soma do mesmo recorte no servidor;
- EX-17-05: o SQLite local reportou versão 3.42.0 e rejeitou `GEN_UUID()` e `FIRST`.

São vinte execuções. A primeira tentativa de EX-17-03 registrou a fonte como
`sqlite_products` e foi recusada porque nomes iniciados por `sqlite_` são reservados;
o contrato passou a usar `source_products`.
