-- FIRESTORE:SINGLE-COMMAND
CREATE OR ALTER PROCEDURE benchmark_product_rows(p_row_count INTEGER)
RETURNS (
  id INTEGER,
  category_id INTEGER,
  name VARCHAR(30) CHARACTER SET UTF8
)
AS
BEGIN
  id = 1;
  WHILE (id <= p_row_count) DO
  BEGIN
    category_id = MOD(id, 10);
    name = 'Product ' || id;
    SUSPEND;
    id = id + 1;
  END
END
