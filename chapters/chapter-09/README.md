# Capítulo 9 — fetch, recursos e experiência

- `ondemand`: mede `Open`, linhas iniciais, `FetchAll` e memória para 100 mil linhas;
- `all`: mede `fmAll` para a mesma consulta e volume, sem usar uma contagem que
  provoque fetch adicional;
- `blob`: remove `fiBlobs` e acessa depois um BLOB de 8 KiB;
- `cancel`: inicia um comando assíncrono sem result set, chama `AbortJob`, drena a
  notificação de conclusão e reutiliza a conexão;
- `feedback`: instancia controles VCL e valida cinco estados da interface.

Os modos `benchmark-blob-immediate`, `benchmark-blob-deferred` e
`benchmark-blob-stream` executam BM-05 com cem BLOBs de 64 KiB. O protocolo descarta
um aquecimento e registra cinco repetições por banco e arquitetura em
`evidence/bm-05-raw.csv`.

```powershell
.\scripts\validate-chapter-09.ps1 `
  -AdminPassword '<senha-administrativa>' `
  -AppPassword '<senha-do-laboratório>'
```

Tempos e memória são observações da execução, não metas universais. Traces, bancos,
binários e credenciais ficam em `.deps`, fora do Git. O monitor usa
`ShowTraces := False`, portanto a automação não abre caixas de diálogo ao terminar.
