# Capítulo 13 — Array DML, Batch Move e cargas em massa

Este laboratório executável cobre os cinco contratos do capítulo:

- `array`: insere 1.000 produtos com `Params.ArraySize` e `Execute`;
- `error`: provoca SKU duplicado, captura `RowIndex` e prova o rollback integral;
- `csv`: importa CSV UTF-8 com schema e convenções numéricas explícitos;
- `transfer`: transfere duas linhas nos dois sentidos entre SQLite e Firebird;
- `benchmark line|array quantidade`: compara DML preparado linha a linha com Array DML.

O CSV usa ponto decimal e ponto e vírgula como delimitador. O exemplo configura tanto
`DecimalSeparator` quanto `ThousandSeparator`; deixar o segundo com o valor da
localidade pode remover silenciosamente o ponto antes da conversão. A coluna booleana
é normalizada no SQL do writer, pois SQLite e Firebird não possuem a mesma
representação física.

## Validação

```powershell
.\scripts\validate-chapter-13.ps1 `
  -AdminPassword '<senha-sysdba>' `
  -AppPassword '<senha-firestore-app>'
```

O script recompila e executa em SQLite e Firebird, Win32 e Win64. Por padrão realiza
três repetições de cada método para 1, 100, 1.000, 10.000 e 100.000 linhas e substitui
os CSVs de evidência. Use `-BenchmarkRepetitions 5` para uma coleta editorial maior.

Senhas, bancos descartáveis, executáveis e bibliotecas instaladas ficam sob `.deps`
ou em variáveis de ambiente e não são versionados.
