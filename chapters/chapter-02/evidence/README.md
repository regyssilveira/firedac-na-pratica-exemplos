# Evidência — capítulo 2

**Data:** 3 de setembro de 2026

**Ambiente:** RAD Studio 13 Florence, Delphi 37.0; Firebird 5.0.4 via TCP 3050;
clientes oficiais Firebird Win32 e Win64; SQLite 3.42 estático do FireDAC.

Comando reproduzível: `scripts/validate-chapter-02.ps1`.

## Resultados

| Exemplo | Win32 | Win64 | Evidência observada |
|---|---|---|---|
| EX-02-01 | aprovado | aprovado | Datasource, dataset, conexão e driver foram percorridos e verificados. |
| EX-02-02 | aprovado | aprovado | Dois formulários mantiveram datasources próprios apontando ao mesmo dataset do DataModule. |
| EX-02-03 | aprovado | aprovado | Console e VCL reutilizaram `TCatalogData` contra SQLite e Firebird. |
| EX-02-04 | aprovado | aprovado | Manager listou FB/SQLite e o driver link recebeu uma `VendorLib` existente da arquitetura correta. |
| EX-02-05 | aprovado | aprovado | Metadata físico informou versões e flags sem incluir parâmetros de conexão ou senha. |

## Relatório observado

| Driver | Cliente | Servidor | Unicode | FileBased | Transações | Savepoints | Eventos |
|---|---|---|---:|---:|---:|---:|---:|
| SQLite | 3.42.0.0.0 | 3.42.0.0.0 | False | False | True | True | True |
| Firebird | 5.0.4.0.0 | 5.0.4.0.0 | True | False | True | True | True |

As flags são respostas da interface `IFDPhysConnectionMetadata`, não uma descrição
exaustiva do produto. Em particular, `FileBased=False` e `Events=True` para SQLite
mostram que nomes intuitivos não bastam para inferir semântica operacional. Cada
capacidade crítica ainda precisa de um ensaio próprio.

Os quatro binários foram recompilados antes da execução. Bancos, clientes, resultados
e credenciais permaneceram fora do repositório.

## Revisão contra o manuscrito

Os resultados foram confrontados com o Capítulo 2. O texto passou a descrever o
DataModule efetivamente compilado, o uso de `SilentMode` no núcleo não visual, o
compartilhamento do mesmo dataset por dois formulários e os limites das flags de
`IFDPhysConnectionMetadata`.
