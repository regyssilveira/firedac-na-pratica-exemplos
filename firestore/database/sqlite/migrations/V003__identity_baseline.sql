-- SQLite calcula o próximo ROWID a partir da própria tabela quando AUTOINCREMENT
-- não foi solicitado. Esta consulta mantém a numeração das migrations equivalente.
SELECT MAX(id) FROM product;
