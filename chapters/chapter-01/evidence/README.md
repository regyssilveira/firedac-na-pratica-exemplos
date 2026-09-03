# Evidência — capítulo 1

**Data:** 3 de setembro de 2026

**Ambiente:** RAD Studio 13 Florence, Delphi 37.0; Firebird 5.0.4 via TCP 3050;
clientes oficiais Firebird Win32 e Win64; SQLite estático do FireDAC.

Comando reproduzível: `scripts/validate-chapter-01.ps1`.

## Resultados

| Exemplo | Win32 | Win64 | Evidência observada |
|---|---|---|---|
| EX-01-01 | aprovado | aprovado | Formulário VCL abriu catálogo Firebird com três produtos. |
| EX-01-02 | aprovado | aprovado | SQLite criou e consultou catálogo com dois produtos. |
| EX-01-03 | aprovado | aprovado | SKU conhecido retornou linha; entrada com SQL foi tratada como valor e retornou zero. |
| EX-01-04 | aprovado | aprovado | DFM sem senha, conexão aberta ou dataset ativo; configuração injetada em execução. |
| EX-01-05 | aprovado | aprovado | Caminho inexistente de `fbclient.dll` produziu `EFDException` com biblioteca e bitness. |

Os quatro projetos nativos — console e VCL em cada arquitetura — foram recompilados
antes dos testes. Binários, bancos e credenciais permaneceram fora do repositório.
