# Evidência do capítulo 19

EX-19-01–05 são repetidos em SQLite/Firebird e Win32/Win64. O teste não compartilha
conexões ou queries entre workers: cada `TTask` cria e destrói os próprios componentes.
O pool é registrado antes das tasks, limitado a quatro leases no teste concorrente e
a dois no teste de saturação. O terceiro lease é rejeitado e uma nova aquisição passa
depois da devolução.

`bm-08-raw.csv` e `bm-09-raw.csv` contêm dez repetições por combinação. Durações são
resultados do laboratório, não garantias. BM-09 mantém cem mil linhas nas variantes;
o tempo de retorno mede responsividade do chamador e o total mede conclusão.

Medianas BM-08, dez leases novos/aquecidos no pool, em microssegundos: Win32 SQLite
4.227/672,5; Win32 Firebird 656.590,5/37.897; Win64 SQLite 3.378,5/595,5; Win64
Firebird 627.540,5/35.986. O ensaio mede ciclos sequenciais de lease; a saturação é
validada separadamente pelo contrato funcional.

Medianas BM-09, bloqueante/retorno async/total async, em microssegundos: Win32 SQLite
90.463/1.096,5/116.575; Win32 Firebird 650.580/2.106/690.311,5; Win64 SQLite
67.698,5/1.037/105.165,5; Win64 Firebird 670.545,5/2.163/699.878. O retorno rápido
prova responsividade do chamador; o total maior em todas as combinações confirma que
`amAsync` não acelerou a carga medida.
