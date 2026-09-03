# Capítulo 2 — Como o FireDAC funciona

Os exemplos separam apresentação, dataset, conexão e driver sem criar abstrações que
o capítulo ainda não ensinou.

## Projetos

- `Chapter02Checks.dpr`: percorre a cadeia de componentes, reutiliza o núcleo em
  console, verifica os drivers e imprime capacidades físicas observadas.
- `Chapter02Vcl.dpr`: cria dois formulários que possuem datasources independentes,
  ambos ligados ao mesmo `TFDQuery` pertencente a `TCatalogData`.
- `Chapter02.CatalogData.pas`: DataModule sem dependência VCL, compartilhado pelos
  dois programas.

O DFM do DataModule conserva as ligações estruturais, mas não armazena senha nem abre
conexão ou query. O caminho `CH02_AUTORUN=1` permite validar a composição VCL sem
interação; o modo normal mostra os dois formulários.

## Validação

```powershell
.\scripts\validate-chapter-02.ps1 `
  -AdminPassword '<senha administrativa local>' `
  -AppPassword '<senha descartável para FIRESTORE_APP>'
```

O script provisiona bancos descartáveis, recompila console e VCL para Win32 e Win64,
executa cada núcleo contra SQLite e Firebird e inspeciona o DFM. Dependências e
resultados transitórios ficam em `.deps`.
