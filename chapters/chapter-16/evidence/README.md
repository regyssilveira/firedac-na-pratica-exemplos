# Evidência — capítulo 16

Validação executada com FireDAC 37 em SQLite e Firebird 5, Win32 e Win64:

- EX-16-01: modificação, exclusão e inserção apareceram no journal; `CancelUpdates`
  restaurou a base;
- EX-16-02: `UndoLastChange` removeu somente a última inserção, `SavePoint` restaurou
  o marcador e `CancelUpdates` descartou a edição posterior;
- EX-16-03: update otimista com valor original afetou zero linhas, retornou erro,
  associou `RowError`, preservou a intenção e não sobrescreveu o concorrente;
- EX-16-04: apply seguido de rollback manteve o journal; novo apply, commit do banco
  e `CommitUpdates` persistiram duas mudanças e encerraram o delta;
- EX-16-05: falha no detalhe reverteu a alteração do mestre, não persistiu o filho e
  preservou os dois journals no `TFDSchemaAdapter`.

São vinte execuções funcionais. Mensagens textuais do driver não são usadas como
assertion; os testes conferem contagem de erros, `RowError`, banco e journal.
