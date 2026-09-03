CREATE TABLE sales_order (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  idempotency_key VARCHAR(50) NOT NULL UNIQUE,
  order_status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
  total NUMERIC(18, 2) NOT NULL CHECK (total >= 0),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sales_order_item (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id INTEGER NOT NULL,
  line_no INTEGER NOT NULL,
  product_id INTEGER NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC(18, 2) NOT NULL CHECK (unit_price >= 0),
  CONSTRAINT uq_sales_order_item_line UNIQUE (order_id, line_no),
  CONSTRAINT fk_sales_order_item_order FOREIGN KEY (order_id)
    REFERENCES sales_order (id) ON DELETE CASCADE,
  CONSTRAINT fk_sales_order_item_product FOREIGN KEY (product_id)
    REFERENCES product (id)
);

CREATE TABLE inventory (
  product_id INTEGER PRIMARY KEY,
  quantity INTEGER NOT NULL CHECK (quantity >= 0),
  CONSTRAINT fk_inventory_product FOREIGN KEY (product_id)
    REFERENCES product (id)
);

CREATE TABLE outbox_event (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  aggregate_type VARCHAR(40) NOT NULL,
  aggregate_id INTEGER NOT NULL,
  event_type VARCHAR(80) NOT NULL,
  payload TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX ix_sales_order_item_order ON sales_order_item (order_id);
CREATE INDEX ix_outbox_event_aggregate ON outbox_event (aggregate_type, aggregate_id);
