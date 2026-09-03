SET TERM ^;

CREATE FUNCTION order_total (p_order_id BIGINT)
RETURNS NUMERIC(18, 2)
AS
DECLARE VARIABLE v_total NUMERIC(18, 2);
BEGIN
  SELECT COALESCE(SUM(quantity * unit_price), 0)
    FROM sales_order_item
    WHERE order_id = :p_order_id
    INTO :v_total;
  RETURN v_total;
END^

CREATE PROCEDURE get_order_state (p_order_id BIGINT)
RETURNS (
  p_status VARCHAR(20) CHARACTER SET ASCII,
  p_total NUMERIC(18, 2)
)
AS
BEGIN
  SELECT order_status, total
    FROM sales_order
    WHERE id = :p_order_id
    INTO :p_status, :p_total;
END^

CREATE PROCEDURE order_lines (p_order_id BIGINT)
RETURNS (
  p_line_no INTEGER,
  p_product_id BIGINT,
  p_quantity INTEGER,
  p_unit_price NUMERIC(18, 2)
)
AS
BEGIN
  FOR SELECT line_no, product_id, quantity, unit_price
      FROM sales_order_item
      WHERE order_id = :p_order_id
      ORDER BY line_no
      INTO :p_line_no, :p_product_id, :p_quantity, :p_unit_price
  DO
    SUSPEND;
END^

CREATE PROCEDURE close_order (
  p_order_id BIGINT,
  p_operation_key VARCHAR(50) CHARACTER SET ASCII
)
RETURNS (
  p_status VARCHAR(20) CHARACTER SET ASCII,
  p_total NUMERIC(18, 2),
  p_changed SMALLINT
)
AS
BEGIN
  SELECT order_status
    FROM sales_order
    WHERE id = :p_order_id
    INTO :p_status;

  p_total = order_total(:p_order_id);
  p_changed = 0;
  IF (p_status <> 'CLOSED') THEN
  BEGIN
    UPDATE sales_order
      SET order_status = 'CLOSED', total = :p_total
      WHERE id = :p_order_id;
    INSERT INTO outbox_event
      (aggregate_type, aggregate_id, event_type, payload)
      VALUES ('SALES_ORDER', :p_order_id, 'ORDER_CLOSED', :p_operation_key);
    p_status = 'CLOSED';
    p_changed = 1;
  END
END^

CREATE TRIGGER sales_order_closed_event
FOR sales_order
ACTIVE AFTER UPDATE POSITION 0
AS
BEGIN
  IF (NEW.order_status = 'CLOSED' AND OLD.order_status <> 'CLOSED') THEN
    POST_EVENT 'ORDER_CLOSED';
END^

SET TERM ;^
