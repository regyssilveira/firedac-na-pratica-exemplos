INSERT INTO category (id, name, active) VALUES (1, 'Bebidas', 1);
INSERT INTO category (id, name, active) VALUES (2, 'Alimentos', 1);

INSERT INTO product (id, sku, name, category_id, price, active)
VALUES (1, 'BEB-001', 'Café especial', 1, 24.90, 1);
INSERT INTO product (id, sku, name, category_id, price, active)
VALUES (2, 'BEB-002', 'Chá mate', 1, 8.50, 1);
INSERT INTO product (id, sku, name, category_id, price, active)
VALUES (3, 'ALI-001', 'Pão de queijo', 2, 18.75, 1);
