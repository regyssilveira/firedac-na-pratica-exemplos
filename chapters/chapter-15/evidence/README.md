# Evidência — capítulo 15

Validação executada com FireDAC 37 em Win32 e Win64:

- EX-15-01: binário preservou schema, tipos, duas linhas e `ChangeCount=2`;
- EX-15-02: XML preservou o mesmo contrato;
- EX-15-03: JSON FireDAC preservou metadata/delta; JSON livre inferiu `price`
  (`ftFMTBcd`, 1234,56) como `ftBoolean=True` e voltou com `ChangeCount=0`;
- EX-15-04: `PersistentFileName` carregou e salvou no fechamento; uma gravação
  explícita com `Backup=True` conservou a versão anterior em `.bak`;
- EX-15-05: arquivo binário truncado foi rejeitado e o backup versionado foi aceito.

BM-06 contém 90 medições: três formatos × cinco volumes × três repetições × duas
arquiteturas. Em 100.000 linhas, as medianas observadas foram:

| Arquitetura | Formato | Escrita | Leitura | Bytes |
|---|---|---:|---:|---:|
| Win32 | binário | 35,19 ms | 102,60 ms | 7.879.194 |
| Win32 | XML | 1.282,00 ms | 1.938,59 ms | 11.446.189 |
| Win32 | JSON | 143,24 ms | 238,03 ms | 11.146.238 |
| Win64 | binário | 39,51 ms | 97,91 ms | 7.879.194 |
| Win64 | XML | 1.062,09 ms | 1.596,21 ms | 11.446.189 |
| Win64 | JSON | 150,00 ms | 284,62 ms | 11.146.238 |

Os dados brutos estão em `bm-06-raw.csv`. Tempos descrevem esta máquina e não incluem
flush físico garantido pelo sistema operacional, checksum, compressão ou criptografia.
