# Evidência — capítulo 13

Validação realizada localmente com RAD Studio 13/Delphi 37.0 e Firebird 5 em bancos
M0 descartáveis, nas arquiteturas Win32 e Win64.

## Resultado funcional

- EX-13-01: 1.000 linhas confirmadas por Array DML;
- EX-13-02: duplicidade na posição 2 reportada como `RowIndex=2` nos dois drivers e
  nenhuma linha persistida após rollback;
- EX-13-03: três linhas de CSV UTF-8 preservaram acento, decimal e contagem;
- EX-13-04: SQLite→Firebird e Firebird→SQLite preservaram texto, decimal e contagem;
- EX-13-05: 120 medições concluídas (2 bancos × 2 arquiteturas × 2 métodos ×
  5 volumes × 3 repetições).

## Dados brutos

- `bm-01-raw.csv`: DML preparado linha a linha;
- `bm-07-raw.csv`: Array DML;
- colunas: driver, arquitetura, método, quantidade, milissegundos, linhas/s e repetição.

Para 100.000 linhas, a mediana de Array DML foi 1,69× e 1,75× mais rápida que o loop
no SQLite Win32 e Win64; no Firebird, 2,74× e 2,98×. Esses números descrevem apenas
esta máquina e este cenário local. O ganho não deve ser generalizado sem repetir o
protocolo no ambiente-alvo.

O custo fixo dominou os lotes mínimos: em uma linha, o loop chegou a empatar ou vencer.
Isso confirma que batching é uma decisão de volume e não uma regra absoluta.
