# Manifesto de exemplos

`examples.json` é a fonte pública do estado de cada exemplo. Atualizações devem ser
feitas pelo script de transição, que impede saltos de gate.

As evidências atualmente referenciadas ficam nos diretórios de cada capítulo, no
FireStore ou em `manifest/evidence/`. Elas registram, conforme o caso, ambiente,
comando, resultado e limitações. Binários e segredos não entram no Git.

Estados possíveis:

- `PL`: planejado;
- `IM`: implementado;
- `CP`: compilado;
- `EX`: executado;
- `EC`: evidência condicionada por um gate externo declarado;
- `RV`: revisado tecnicamente e sincronizado com a edição do livro.

O manifesto deve ser validado com `..\scripts\validate-manifest.ps1` depois de
qualquer atualização de estado ou de evidência.
