# Capítulo 21 — FireDAC em uma aplicação profissional

O laboratório cobre recovery por nova attachment Firebird, retry idempotente,
WireCrypt, TLS PostgreSQL com `verify-full`, falhas de hostname e CA, pacote nativo
por arquitetura, restore e smoke test.

```powershell
.\scripts\validate-chapter-21.ps1 -AdminPassword '<senha>' -AppPassword '<senha>'
.\scripts\validate-chapter-21-tls.ps1
```

Os pacotes são gerados em `.deps` e não são versionados. O manifesto de hashes e
licenças é público. Executá-los neste host prova isolamento do diretório, mas não
substitui o gate de uma VM sem RAD Studio.
