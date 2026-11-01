-- ============================================================
-- Olist E-commerce Analysis | 01_schema.sql
-- Run in pgAdmin Query Tool, connected to database: olist
-- ============================================================

DROP TABLE IF EXISTS order_reviews, order_payments, order_items, orders,
                     products, sellers, customers, geolocation,
                     category_translation CASCADE;

CREATE TABLE customers (
    customer_id              VARCHAR(50) PRIMARY KEY,   -- changes per order
    customer_unique_id       VARCHAR(50) NOT NULL,      -- the REAL customer
    customer_zip_code_prefix VARCHAR(10),
    customer_city            VARCHAR(100),
    customer_state           CHAR(2)
);

CREATE TABLE sellers (
    seller_id              VARCHAR(50) PRIMARY KEY,
    seller_zip_code_prefix VARCHAR(10),
    seller_city            VARCHAR(100),
    seller_state           CHAR(2)
);

CREATE TABLE products (
    product_id                 VARCHAR(50) PRIMARY KEY,
    product_category_name      VARCHAR(100),
    product_name_lenght        INT,      -- spelling is as in the source CSV
    product_description_lenght INT,
    product_photos_qty         INT,
    product_weight_g           INT,
    product_length_cm          INT,
    product_height_cm          INT,
    product_width_cm           INT
);

CREATE TABLE category_translation (
    product_category_name         VARCHAR(100) PRIMARY KEY,
    product_category_name_english VARCHAR(100)
);

-- No keys here: zip prefixes repeat many times and are not unique.
CREATE TABLE geolocation (
    geolocation_zip_code_prefix VARCHAR(10),
    geolocation_lat             DOUBLE PRECISION,
    geolocation_lng             DOUBLE PRECISION,
    geolocation_city            VARCHAR(100),
    geolocation_state           CHAR(2)
);

CREATE TABLE orders (
    order_id                      VARCHAR(50) PRIMARY KEY,
    customer_id                   VARCHAR(50) REFERENCES customers(customer_id),
    order_status                  VARCHAR(20),
    order_purchase_timestamp      TIMESTAMP,
    order_approved_at             TIMESTAMP,
    order_delivered_carrier_date  TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);

CREATE TABLE order_items (
    order_id            VARCHAR(50) REFERENCES orders(order_id),
    order_item_id       INT,
    product_id          VARCHAR(50) REFERENCES products(product_id),
    seller_id           VARCHAR(50) REFERENCES sellers(seller_id),
    shipping_limit_date TIMESTAMP,
    price               NUMERIC(10,2),
    freight_value       NUMERIC(10,2),
    PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE order_payments (
    order_id             VARCHAR(50) REFERENCES orders(order_id),
    payment_sequential   INT,
    payment_type         VARCHAR(20),
    payment_installments INT,
    payment_value        NUMERIC(10,2),
    PRIMARY KEY (order_id, payment_sequential)
);

-- review_id is NOT unique in this dataset, so no primary key.
CREATE TABLE order_reviews (
    review_id               VARCHAR(50),
    order_id                VARCHAR(50) REFERENCES orders(order_id),
    review_score            INT,
    review_comment_title    TEXT,
    review_comment_message  TEXT,
    review_creation_date    TIMESTAMP,
    review_answer_timestamp TIMESTAMP
);

CREATE INDEX idx_reviews_order   ON order_reviews(order_id);
CREATE INDEX idx_items_seller    ON order_items(seller_id);
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_cust_unique     ON customers(customer_unique_id);

-- ============================================================
-- LOAD DATA
-- Easiest: pgAdmin > right-click table > Import/Export Data
--   Format: csv | Header: ON | Delimiter: , | Encoding: UTF8
-- LOAD IN THIS ORDER (parents before children):
--   1 customers, 2 sellers, 3 products, 4 category_translation,
--   5 geolocation, 6 orders, 7 order_items, 8 order_payments,
--   9 order_reviews
--
-- Or with psql (run from the folder holding the CSVs):
--   \copy customers FROM 'olist_customers_dataset.csv' CSV HEADER
--   \copy sellers FROM 'olist_sellers_dataset.csv' CSV HEADER
--   \copy products FROM 'olist_products_dataset.csv' CSV HEADER
--   \copy category_translation FROM 'product_category_name_translation.csv' CSV HEADER
--   \copy geolocation FROM 'olist_geolocation_dataset.csv' CSV HEADER
--   \copy orders FROM 'olist_orders_dataset.csv' CSV HEADER
--   \copy order_items FROM 'olist_order_items_dataset.csv' CSV HEADER
--   \copy order_payments FROM 'olist_order_payments_dataset.csv' CSV HEADER
--   \copy order_reviews FROM 'olist_order_reviews_dataset.csv' CSV HEADER
-- ============================================================

-- ============================================================
-- VERIFY AFTER LOADING
-- Expected rows: customers 99441 | sellers 3095 | products 32951
-- translation 71 | geolocation 1000163 | orders 99441
-- order_items 112650 | order_payments 103886 | order_reviews 99224
-- ============================================================
SELECT 'customers' AS tbl, COUNT(*) FROM customers
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'category_translation', COUNT(*) FROM category_translation
UNION ALL SELECT 'geolocation', COUNT(*) FROM geolocation
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews;

-- Data quality checks (note the results for your README)
SELECT order_status, COUNT(*) FROM orders GROUP BY order_status ORDER BY 2 DESC;

SELECT COUNT(*) AS delivered_without_date
FROM orders
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL;

SELECT COUNT(*) AS orders_with_multiple_reviews
FROM (SELECT order_id FROM order_reviews GROUP BY order_id HAVING COUNT(*) > 1) t;

SELECT COUNT(*) AS products_missing_category FROM products WHERE product_category_name IS NULL;

SELECT COUNT(DISTINCT customer_id) AS customer_ids,
       COUNT(DISTINCT customer_unique_id) AS real_customers
FROM customers;

-- ============================================================
-- DATA QUALITY RESULTS FROM MY RUN
-- Order status : delivered 96,478 | shipped 1,107 | canceled 625 |
--                unavailable 609 | invoiced 314 | processing 301 |
--                created 5 | approved 2
-- Delivered orders with no delivery date : 8
-- Orders with more than one review       : 547
-- Products with no category              : 610
-- customer_id vs real customers          : 99,441 vs 96,096
-- ============================================================
