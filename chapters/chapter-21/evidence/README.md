# Evidência do capítulo 21

EX-21-01, 02 e 05 foram executados em SQLite/Firebird e Win32/Win64. No Firebird, o
validador encerrou a attachment da aplicação por uma conexão administrativa. Com
`AutoReconnect=True` e `faRetry`, a consulta voltou em outra attachment e observamos
`OnRecover=1`, `OnRestored=1`, `OnLost=0`. O caminho recuperado não dispara todos os
eventos imaginados pelo rascunho.

O retry repetiu uma inserção com chave idempotente, classificou a violação e consultou
o resultado existente: uma única linha, ID 211001. A política marcou a repetição sem
chave como insegura.

EX-21-03 comprovou `IBAdvanced=wire_crypt=Required`; `MON$WIRE_CRYPT_PLUGIN` reportou
`ChaCha64`, e senha errada falhou. Isso é wire encryption do Firebird, não TLS X.509.
SQLite é embarcado e retornou `integrity_check=ok`. O gate TLS com CA/hostname em
PostgreSQL/MySQL continua pendente; por isso EX-21-03 fica em `EC`.

EX-21-04 montou pacotes Win32/Win64 com executável, cliente Firebird, runtime,
plugin ChaCha e licenças, todos inventariados por SHA-256 em
`deployment-manifest.json`. O smoke isolado passou, mas o host possui RAD Studio;
o estado permanece `EC` até execução em VM limpa.

EX-21-05 confirmou oito migrations, três produtos e rollback de estoque. O Firebird
foi copiado por `gbak`, restaurado em outro arquivo e o mesmo smoke test passou sobre
a restauração. Senhas foram fornecidas por ambiente, não pela linha de comando.
