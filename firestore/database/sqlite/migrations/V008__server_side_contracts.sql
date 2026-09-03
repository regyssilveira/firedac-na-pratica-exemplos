-- SQLite não possui stored procedures, funções persistentes nem eventos de servidor.
-- O driver FireDAC oferece Events locais por conexão; isso não é uma rotina persistente.
-- A view é um contrato SQL real usado pelo adapter SQLite sem fingir equivalência.
CREATE VIEW order_total_view AS
SELECT
  o.id AS order_id,
  COALESCE(SUM(i.quantity * i.unit_price), 0) AS calculated_total
FROM sales_order o
LEFT JOIN sales_order_item i ON i.order_id = o.id
GROUP BY o.id;
