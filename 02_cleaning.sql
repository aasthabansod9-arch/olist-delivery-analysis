-- ============================================================
-- Olist E-commerce Analysis | 02_cleaning.sql
-- Builds two analysis-ready tables from the raw ones:
--   order_analysis : one row per delivered order (main table)
--   item_analysis  : one row per order item (for category/seller work)
-- ============================================================

-- ------------------------------------------------------------
-- 0. CLEANING LOG: what are we dropping, and why? (save for README)
-- ------------------------------------------------------------
SELECT
    COUNT(*)                                                        AS total_orders,
    COUNT(*) FILTER (WHERE order_status = 'delivered')              AS delivered,
    COUNT(*) FILTER (WHERE order_status = 'delivered'
                     AND order_delivered_customer_date IS NULL)     AS delivered_missing_date,
    COUNT(*) FILTER (WHERE order_status <> 'delivered')             AS not_delivered_dropped
FROM orders;

-- ------------------------------------------------------------
-- 1. ORDER-LEVEL TABLE
-- Aggregate items and reviews BEFORE joining, so rows never multiply.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS item_analysis;
DROP TABLE IF EXISTS order_analysis;

CREATE TABLE order_analysis AS
WITH items_agg AS (
    SELECT
        order_id,
        COUNT(*)                  AS n_items,
        COUNT(DISTINCT seller_id) AS n_sellers,
        SUM(price)                AS items_revenue,
        SUM(freight_value)        AS freight_value
    FROM order_items
    GROUP BY order_id
),
reviews_dedup AS (
    -- Some orders have several reviews: keep the most recent one per order
    SELECT DISTINCT ON (order_id)
        order_id,
        review_score
    FROM order_reviews
    ORDER BY order_id, review_answer_timestamp DESC NULLS LAST, review_id
)
SELECT
    o.order_id,
    o.customer_id,
    c.customer_unique_id,                       -- the real customer
    c.customer_state,
    c.customer_city,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    DATE_TRUNC('month', o.order_purchase_timestamp)::date          AS purchase_month,

    -- delivery metrics
    ROUND(EXTRACT(EPOCH FROM (o.order_delivered_customer_date
                              - o.order_purchase_timestamp)) / 86400.0, 1) AS delivery_days,
    (o.order_delivered_customer_date::date
        - o.order_estimated_delivery_date::date)                   AS delay_days,   -- >0 means late
    CASE WHEN o.order_delivered_customer_date::date
              > o.order_estimated_delivery_date::date
         THEN 1 ELSE 0 END                                         AS is_late,
    CASE
        WHEN o.order_delivered_customer_date::date
             <= o.order_estimated_delivery_date::date THEN '1. On time'
        WHEN o.order_delivered_customer_date::date
             - o.order_estimated_delivery_date::date <= 3 THEN '2. 1-3 days late'
        WHEN o.order_delivered_customer_date::date
             - o.order_estimated_delivery_date::date <= 7 THEN '3. 4-7 days late'
        ELSE '4. 8+ days late'
    END                                                            AS delay_bucket,

    -- order value
    i.n_items,
    i.n_sellers,
    i.items_revenue,
    i.freight_value,
    (i.items_revenue + i.freight_value)                            AS total_order_value,

    -- customer feedback
    r.review_score
FROM orders o
JOIN customers c        ON c.customer_id = o.customer_id
LEFT JOIN items_agg i   ON i.order_id = o.order_id
LEFT JOIN reviews_dedup r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL;

ALTER TABLE order_analysis ADD PRIMARY KEY (order_id);
CREATE INDEX idx_oa_unique_cust ON order_analysis(customer_unique_id);
CREATE INDEX idx_oa_month       ON order_analysis(purchase_month);

-- ------------------------------------------------------------
-- 2. ITEM-LEVEL TABLE (delivered orders only)
-- Categories and sellers live at item level, so category/seller
-- questions use this table.
-- ------------------------------------------------------------
CREATE TABLE item_analysis AS
SELECT
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    s.seller_state,
    COALESCE(t.product_category_name_english,
             p.product_category_name,
             'unknown')                 AS category,
    oi.price,
    oi.freight_value,
    oa.customer_state,
    oa.purchase_month,
    oa.is_late,
    oa.delay_days,
    oa.review_score
FROM order_items oi
JOIN order_analysis oa           ON oa.order_id = oi.order_id
JOIN products p                  ON p.product_id = oi.product_id
JOIN sellers s                   ON s.seller_id = oi.seller_id
LEFT JOIN category_translation t ON t.product_category_name = p.product_category_name;

CREATE INDEX idx_ia_seller   ON item_analysis(seller_id);
CREATE INDEX idx_ia_category ON item_analysis(category);

-- ============================================================
-- 3. VALIDATION: run each and check the result makes sense
-- ============================================================

-- 3a. Row count (about 96,470) and no duplicate orders (should return 0 rows)
SELECT COUNT(*) AS rows_in_order_analysis FROM order_analysis;

SELECT order_id, COUNT(*) FROM order_analysis GROUP BY order_id HAVING COUNT(*) > 1;

-- 3b. Impossible values (each count should be 0 or tiny)
SELECT
    COUNT(*) FILTER (WHERE delivery_days < 0)       AS delivered_before_purchase,
    COUNT(*) FILTER (WHERE delivery_days > 100)     AS extreme_delivery_over_100d,
    COUNT(*) FILTER (WHERE items_revenue IS NULL)   AS orders_without_items,
    COUNT(*) FILTER (WHERE review_score IS NULL)    AS orders_without_review
FROM order_analysis;

-- 3c. Summary stats: look for oddities
SELECT
    ROUND(AVG(delivery_days), 1)             AS avg_delivery_days,
    MIN(delivery_days)                       AS min_days,
    MAX(delivery_days)                       AS max_days,
    ROUND(100.0 * AVG(is_late), 2)           AS pct_late,
    ROUND(AVG(review_score), 2)              AS avg_review
FROM order_analysis;

-- 3d. Sanity check on the headline hypothesis
SELECT is_late, COUNT(*) AS orders, ROUND(AVG(review_score), 2) AS avg_review
FROM order_analysis
GROUP BY is_late
ORDER BY is_late;

-- 3e. Item table should have about 110,000 rows (delivered orders only)
SELECT COUNT(*) AS rows_in_item_analysis,
       COUNT(*) FILTER (WHERE category = 'unknown') AS unknown_category_items
FROM item_analysis;

-- ============================================================
-- RESULTS FROM MY RUN
-- Cleaning log   : 99,441 orders | 96,478 delivered | 8 delivered without a
--                  delivery date | 2,963 not delivered (dropped)
-- order_analysis : 96,470 rows (97.0% of all orders)
-- item_analysis  : 110,189 rows (1,537 with unknown category)
-- Summary        : average delivery 12.6 days (min 0.5, max 209.6);
--                  6.77% late; average review 4.16
-- Sanity check   : on time = 89,936 orders, average review 4.29
--                  late    =  6,534 orders, average review 2.27
-- ============================================================
