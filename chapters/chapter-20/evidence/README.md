# Evidência do capítulo 20

EX-20-01–05 foram executados em SQLite/Firebird e Win32/Win64. No SQLite, o FireDAC
retornou um catálogo, nenhum schema, oito tabelas/views, doze campos de `product`, uma
chave e três índices. Não anunciou procedure nem generator persistente.

No Firebird, o usuário restrito precisou de `[osMy, osOther]`: ele não é proprietário
dos objetos aos quais recebeu acesso. Foram visíveis sete tabelas, doze campos, uma
chave, cinco índices e cinco rotinas; `GET_ORDER_STATE` expôs três argumentos. A view
`ORDER_TOTAL_VIEW` não apareceu porque não recebeu `GRANT`, comprovando que resultado
vazio também pode significar visibilidade insuficiente. Catálogo e schema vieram
vazios, o que é uma resposta válida para esse namespace, não falha do driver.

O explorer materializou snapshots e só abriu preview de `PRODUCT` depois de encontrá-la
na allowlist, com limite de duas linhas. No Firebird, evento após commit chegou e
evento de transação revertida não chegou. No SQLite, `Signal` local chegou mesmo com
rollback da transação de dados: os mecanismos não têm a mesma fronteira transacional.
Em ambos, o listener offline não recuperou o alerta transitório, enquanto a linha
outbox foi encontrada por polling.
