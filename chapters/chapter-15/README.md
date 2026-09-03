# Capítulo 15 — Persistência, formatos e intercâmbio

Laboratório de round-trip binário, XML, JSON FireDAC e JSON livre, persistência
automática, backup e recuperação após corrupção.

O laboratório também executa BM-06 para binário, XML e JSON FireDAC em 1, 100,
1.000, 10.000 e 100.000 linhas, com três repetições em cada arquitetura. Os arquivos
temporários ficam em `.deps`; somente o CSV bruto da evidência é versionado.

```powershell
.\scripts\validate-chapter-15.ps1
```

O executável inclui `Data.DBJson`, necessário para registrar o streamer JSON, e
inicializa COM no programa console para o DOM XML do Windows.
