# Manifesto de exemplos

`examples.json` é a fonte pública do estado de cada exemplo. Atualizações devem ser
feitas pelo script de transição, que impede saltos de gate.

Cada evidência futura ficará em `manifest/evidence/<ID>/` e conterá ambiente,
comando, resultado e limitações. Binários e segredos não entram no Git.
