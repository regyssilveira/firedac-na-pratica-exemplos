# Evidência do capítulo 18

A validação executa EX-18-01–05 em SQLite e Firebird, Win32 e Win64. Os arquivos
`bm-10-raw.csv` e `bm-02-raw.csv` são gerados pelo script com dez repetições por
combinação. O relatório de ambiente publicado é sanitizado e não contém senha,
usuário ou caminho do banco.

As durações dependem da máquina, caches e topologia. A evidência forte é o contrato:
N+1 emite cem comandos contra um comando em lote com o mesmo checksum; fetch sob
demanda materializa uma janela antes das cem mil linhas; e cada SGBD confirma acesso
por índice no plano.

Na matriz registrada, BM-10 contém 80 linhas: dez repetições das duas variantes em
quatro combinações. As medianas N+1/lote foram 2.094,5/268,5 µs (Win32 SQLite),
67.266,5/4.561 µs (Win32 Firebird), 2.044,5/246,5 µs (Win64 SQLite) e
78.653,5/5.272,5 µs (Win64 Firebird). Elas demonstram esta massa e esta topologia,
não uma razão universal.

BM-02 contém 40 linhas. Para cem mil registros e `RowsetSize=64`, a mediana até a
primeira janela/total foi 313/74.352,5 µs (Win32 SQLite),
5.464/645.044,5 µs (Win32 Firebird), 341/59.972,5 µs (Win64 SQLite) e
6.494,5/652.701 µs (Win64 Firebird). `memory_delta` é variação do working set do
processo, uma aproximação influenciada pelo alocador e não memória exclusiva do dataset.

O trace funcional fica em `.deps` porque contém caminhos e detalhes da conexão. O
validador exige que ele contenha as assinaturas N+1 e lote, mas publica somente CSV
sanitizado e relatórios que removem usuário, senha, caminho da DLL/banco e hostname.
