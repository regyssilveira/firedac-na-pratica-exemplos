# Evidência — capítulo 9

**Data:** 3 de setembro de 2026

**Ambiente:** RAD Studio 13 Florence, Delphi 37.0; Firebird 5.0.4 por TCP;
SQLite estático do FireDAC; clientes Firebird Win32 e Win64.

Comando reproduzível: `scripts/validate-chapter-09.ps1`.

## Matriz executada

| Exemplo | SQLite Win32 | SQLite Win64 | Firebird Win32 | Firebird Win64 |
|---|---:|---:|---:|---:|
| EX-09-01 — fetch sob demanda | aprovado | aprovado | aprovado | aprovado |
| EX-09-02 — fetch completo | aprovado | aprovado | aprovado | aprovado |
| EX-09-03 — BLOB sob demanda | aprovado | aprovado | aprovado | aprovado |
| EX-09-04 — cancelamento | aprovado | aprovado | aprovado | aprovado |
| EX-09-05 — feedback VCL | aprovado | aprovado | aprovado | aprovado |

O exemplo visual independe do driver e foi executado nos binários Win32 e Win64.
Todos os demais exemplos foram executados contra os dois bancos em ambas as
arquiteturas.

## Fetch incremental e completo

Cada consulta produziu 100 mil linhas, com `RowsetSize = 64` e
`RecordCountMode = cmFetched` nas medições que precisavam observar somente o cache.
Esse modo de contagem é deliberado: consultar `RecordCount` com uma configuração
inadequada pode executar trabalho adicional e invalidar a comparação.

| Perfil | `fmOnDemand`: Open | linhas iniciais | FetchAll restante | `fmAll`: Open | memória sob demanda | memória `fmAll` |
|---|---:|---:|---:|---:|---:|---:|
| SQLite Win32 | 0 ms | 64 | 77 ms | 68 ms | 17.088.512 B | 17.063.936 B |
| Firebird Win32 | 4 ms | 64 | 618 ms | 656 ms | 18.845.696 B | 18.845.696 B |
| SQLite Win64 | 0 ms | 64 | 50 ms | 52 ms | 26.984.448 B | 27.004.928 B |
| Firebird Win64 | 7 ms | 64 | 647 ms | 647 ms | 27.508.736 B | 27.369.472 B |

Os valores são observações de uma execução, não metas de desempenho. Em todos os
perfis, `fmAll` já continha as 100 mil linhas após `Open`. Ainda assim,
`SourceEOF` permaneceu falso até uma chamada explícita e idempotente a `FetchAll`,
que levou 0 ms. Isso ocorre porque o último lote completo pode ser recebido sem a
leitura vazia adicional que marca formalmente o fim do cursor. Portanto,
`SourceEOF = False` sozinho não prova que o cache esteja parcial.

## BLOB realmente tardio

O teste removeu `fiBlobs` de `FetchOptions.Items`, abriu o produto sem materializar
seus 8 KiB e só então consultou `TBlobField.BlobSize`. Os quatro traces mostram uma
segunda operação `SELECT A.IMAGE_DATA` dentro de `FetchRow`. No Firebird aparecem
`isc_open_blob2`, `isc_blob_info`, `isc_get_segment` e `isc_close_blob`; no SQLite,
`sqlite3_column_blob` informa exatamente 8192 bytes. Isso comprova a leitura tardia,
em vez de inferi-la apenas pela configuração.

## Cancelamento assíncrono

O ensaio usa `CmdExecMode = amAsync` sobre um comando deliberadamente demorado e
sem result set. Após 20 ms, `AbortJob(True)` retornou entre 15 e 16 ms em todos os
perfis, deixou o dataset inativo e permitiu executar outra consulta na mesma
conexão. Em seguida, `Disconnect(True)` encerrou e despreparou o comando.

Uma versão inicial usava `Open` sobre `SELECT COUNT(...)`. Ela expôs duas fases
assíncronas distintas — abertura do cursor e fetch — e permitia que a conclusão da
primeira disparasse a segunda depois do primeiro cancelamento. O exemplo final usa
`ExecSQL` justamente para ensinar o contrato testado sem confundir cancelamento de
execução com cancelamento de fetch.

## Interface e instrumentação

O ensaio VCL verificou cinco estados: carregando, resultado parcial, concluído,
cancelado e falhou, incluindo a habilitação coerente dos botões de busca e
cancelamento. O trace `FlatFile` foi habilitado apenas no teste de BLOB: instrumentar
a medição de fetch alterava fortemente o tempo observado. `ShowTraces = False` evita
caixas de diálogo ao finalizar os executáveis automatizados.

## Limites

Os números não constituem benchmark científico e variam com máquina, cache, rede e
carga. O teste não mede latência remota, paginação no servidor, múltiplos result sets
nem cancelamento durante cada fase possível de um dataset. Esses cenários devem ser
avaliados com a consulta e o driver reais da aplicação.

## Revisão contra o manuscrito

Fonte, saídas, traces e Capítulo 9 foram confrontados. O texto agora distingue cache
completo de cursor formalmente esgotado, usa `cmFetched` para não perturbar a medição,
expõe o fetch tardio real do BLOB e separa cancelamento de execução das fases de
abertura e fetch. Também registra a interferência do monitor e o teardown seguro da
operação assíncrona.

EX-09-01 a EX-09-05 podem avançar a `RV`. Cada afirmação apresentada como resultado
possui asserção nos binários correspondentes ou evidência nos quatro traces; os
limites de benchmark e de generalização entre drivers permanecem explícitos.
