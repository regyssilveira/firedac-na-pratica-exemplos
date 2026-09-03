# Capítulo 6 — parâmetros, macros e tipos

O projeto executa cinco contratos independentes:

- `optional`: quatro combinações de filtros, incluindo parâmetros `NULL` tipados;
- `allowlist`: macro estrutural alimentada somente por enumeração validada;
- `datetime`: instante com deslocamento no Firebird e UTC canônico no SQLite;
- `blob`: round-trip por stream conferido byte a byte e por SHA-256;
- `types`: matriz concreta de chave, decimal, booleano, UUID textual e nulos.

O mesmo fonte é compilado para Win32 e Win64 e executado contra SQLite e Firebird.
As alterações são revertidas ao fim de cada modo.

```powershell
.\scripts\validate-chapter-06.ps1 `
  -AdminPassword '<senha-administrativa>' `
  -AppPassword '<senha-do-laboratório>'
```

Credenciais e bancos descartáveis não são versionados.
