# Evidência — FireStore M0

**Data:** 3 de setembro de 2026

**RAD Studio:** 13 Florence, compilador 37.0.57242.3601

**Servidor:** Firebird 5.0.4.1812, TCP 3050

O bootstrap foi compilado como Win32 e Win64 e validado com os seguintes cenários:

- criação e reabertura de bancos SQLite independentes;
- aplicação ordenada das migrations `V001` e `V002`;
- segunda execução sem reaplicar migrations;
- rejeição de checksum divergente;
- criação e reset de um banco Firebird descartável;
- seed determinístico com duas categorias e três produtos, incluindo UTF-8;
- smoke test Firebird autenticado como `FIRESTORE_APP`, sem usar `SYSDBA`;
- repetição do smoke test com clientes Firebird nativos Win32 e Win64.

Resultado: todos os testes passaram. Credenciais e bancos gerados permaneceram fora
do repositório. A execução reproduzível está em `scripts/validate-firestore-m0.ps1`.
