-- ============================================================
-- Olist E-commerce Analysis | 03_analysis.sql
-- Business question: Why are some orders delivered late, and how
-- does lateness affect review scores and repeat purchases?
-- Tables used: order_analysis (1 row per delivered order)
--              item_analysis  (1 row per item)
-- Run one query at a time. Write down each result.
-- ============================================================

-- ============================================================
-- RESULTS SUMMARY (from my run on the full Olist dataset)
-- Q1  Monthly revenue grew from R$111.8K (Jan 2017) to R$977.5K (May 2018);
--     Nov 2017 spiked to R$987.6K from 7,288 orders
-- Q2  Nov 2017 was +52.4% month on month, then -26.5% in Dec 2017
-- Q3a 96,470 delivered orders, 6,534 late = 6.77%; average delivery 12.6 days
-- Q3b Worst states (at least 200 orders): AL 21.41%, MA 17.43%, SE 15.22%,
--     PI 13.87%, CE 13.76%
-- Q4  Top-10 categories have late rates of 5.00% to 7.56%;
--     health_beauty leads revenue (R$1.23M)
-- Q5  56 rows: top 3 sellers by revenue in each seller state
-- Q6  Average review: on time 4.29 (89,443 orders) vs late 2.27 (6,381 orders)
-- Q7  Average review by bucket: 4.29 -> 3.29 -> 2.10 -> 1.70;
--     1-star share: 6.6% -> 25.1% -> 58.6% -> 69.8%
-- Q8  2,801 of 93,350 customers (3.00%) ordered more than once
-- Q9  Repeat rate: 4.08% after an on-time first order vs 2.87% after a late one
-- Q10 Very low retention: the Jan 2017 cohort (717 customers) returns at
--     0.14% to 0.70% per month through month 12
-- ============================================================


-- ------------------------------------------------------------
-- Q1. Monthly revenue and order count
-- Business meaning: is the business growing, and is it seasonal?
-- Note: 2016 data is tiny and the last months (Sep-Oct 2018) are
-- incomplete, so trend analysis uses Jan 2017 to Aug 2018 only.
-- ------------------------------------------------------------
SELECT
    purchase_month,
    COUNT(*)                         AS orders,
    ROUND(SUM(items_revenue), 2)     AS revenue,
    ROUND(AVG(items_revenue), 2)     AS avg_order_value
FROM order_analysis
WHERE purchase_month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01'
GROUP BY purchase_month
ORDER BY purchase_month;


-- ------------------------------------------------------------
-- Q2. Month-over-month revenue growth %
-- Business meaning: which months accelerated or dropped?
-- Skill: LAG() window function
-- ------------------------------------------------------------
WITH monthly AS (
    SELECT purchase_month, SUM(items_revenue) AS revenue
    FROM order_analysis
    WHERE purchase_month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01'
    GROUP BY purchase_month
)
SELECT
    purchase_month,
    ROUND(revenue, 2) AS revenue,
    ROUND(LAG(revenue) OVER (ORDER BY purchase_month), 2) AS prev_month_revenue,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY purchase_month))
          / LAG(revenue) OVER (ORDER BY purchase_month), 1) AS mom_growth_pct
FROM monthly
ORDER BY purchase_month;


-- ------------------------------------------------------------
-- Q3a. Overall late-delivery rate
-- Business meaning: how big is the problem?
-- ------------------------------------------------------------
SELECT
    COUNT(*)                        AS delivered_orders,
    SUM(is_late)                    AS late_orders,
    ROUND(100.0 * AVG(is_late), 2)  AS pct_late,
    ROUND(AVG(delivery_days), 1)    AS avg_delivery_days
FROM order_analysis;

-- Q3b. Late rate by customer state (ignore states with tiny volume)
-- Business meaning: where is delivery failing? Targets for carrier fixes.
SELECT
    customer_state,
    COUNT(*)                         AS orders,
    ROUND(100.0 * AVG(is_late), 2)   AS pct_late,
    ROUND(AVG(delivery_days), 1)     AS avg_delivery_days,
    ROUND(AVG(review_score), 2)      AS avg_review
FROM order_analysis
GROUP BY customer_state
HAVING COUNT(*) >= 200
ORDER BY pct_late DESC;


-- ------------------------------------------------------------
-- Q4. Top 10 categories by revenue, with their late rate
-- Business meaning: do the biggest categories also have delivery risk?
-- Skill: CTE + joins. Late rate here is per item, so a multi-item
-- late order counts once per item.
-- ------------------------------------------------------------
WITH category_stats AS (
    SELECT
        category,
        COUNT(*)                        AS items_sold,
        SUM(price)                      AS revenue,
        100.0 * AVG(is_late)            AS pct_late,
        AVG(review_score)               AS avg_review
    FROM item_analysis
    GROUP BY category
)
SELECT
    category,
    items_sold,
    ROUND(revenue, 2)     AS revenue,
    ROUND(pct_late, 2)    AS pct_late,
    ROUND(avg_review, 2)  AS avg_review
FROM category_stats
ORDER BY revenue DESC
LIMIT 10;


-- ------------------------------------------------------------
-- Q5. Top 3 sellers by revenue in each state
-- Business meaning: who are the key sellers, and are they reliable?
-- Skill: RANK() with PARTITION BY
-- ------------------------------------------------------------
WITH seller_stats AS (
    SELECT
        seller_state,
        seller_id,
        COUNT(DISTINCT order_id)        AS orders,
        SUM(price)                      AS revenue,
        100.0 * AVG(is_late)            AS pct_late,
        AVG(review_score)               AS avg_review
    FROM item_analysis
    GROUP BY seller_state, seller_id
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY seller_state ORDER BY revenue DESC) AS rank_in_state
    FROM seller_stats
)
SELECT
    seller_state,
    rank_in_state,
    seller_id,
    orders,
    ROUND(revenue, 2)    AS revenue,
    ROUND(pct_late, 2)   AS pct_late,
    ROUND(avg_review, 2) AS avg_review
FROM ranked
WHERE rank_in_state <= 3
ORDER BY seller_state, rank_in_state;


-- ------------------------------------------------------------
-- Q6. Average review score: on time vs late
-- Business meaning: the headline comparison. Does lateness hurt reviews?
-- ------------------------------------------------------------
SELECT
    CASE WHEN is_late = 1 THEN 'Late' ELSE 'On time' END AS delivery_status,
    COUNT(*)                     AS orders,
    ROUND(AVG(review_score), 2)  AS avg_review_score
FROM order_analysis
WHERE review_score IS NOT NULL
GROUP BY is_late
ORDER BY is_late;


-- ------------------------------------------------------------
-- Q7. Review score by delay bucket (your headline chart)
-- Business meaning: how bad does it get as delay grows? Where is
-- the tipping point for proactive customer messaging?
-- ------------------------------------------------------------
SELECT
    delay_bucket,
    COUNT(*)                                                AS orders,
    ROUND(AVG(review_score), 2)                             AS avg_review_score,
    ROUND(100.0 * AVG((review_score = 1)::int), 1)          AS pct_1_star,
    ROUND(100.0 * AVG((review_score >= 4)::int), 1)         AS pct_4_5_star
FROM order_analysis
WHERE review_score IS NOT NULL
GROUP BY delay_bucket
ORDER BY delay_bucket;


-- ------------------------------------------------------------
-- Q8. Share of customers who ordered more than once
-- Business meaning: how loyal is the base? Uses customer_unique_id,
-- NOT customer_id (customer_id changes with every order).
-- ------------------------------------------------------------
WITH customer_orders AS (
    SELECT customer_unique_id, COUNT(*) AS n_orders
    FROM order_analysis
    GROUP BY customer_unique_id
)
SELECT
    COUNT(*)                                          AS customers,
    COUNT(*) FILTER (WHERE n_orders > 1)              AS repeat_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE n_orders > 1) / COUNT(*), 2) AS pct_repeat
FROM customer_orders;


-- ------------------------------------------------------------
-- Q9. Do customers whose FIRST order was late reorder less?
-- Business meaning: your key insight. Puts a price on bad delivery.
-- Skill: ROW_NUMBER() + CTEs
-- Only first orders placed before Feb 2018 are used, so every
-- customer has at least ~6 months to come back.
-- ------------------------------------------------------------
WITH ranked_orders AS (
    SELECT
        customer_unique_id,
        order_id,
        is_late,
        delay_bucket,
        review_score,
        order_purchase_timestamp,
        ROW_NUMBER() OVER (PARTITION BY customer_unique_id
                           ORDER BY order_purchase_timestamp) AS order_number
    FROM order_analysis
),
customer_totals AS (
    SELECT customer_unique_id, COUNT(*) AS total_orders
    FROM order_analysis
    GROUP BY customer_unique_id
),
first_orders AS (
    SELECT r.*, t.total_orders
    FROM ranked_orders r
    JOIN customer_totals t USING (customer_unique_id)
    WHERE r.order_number = 1
      AND r.order_purchase_timestamp < TIMESTAMP '2018-02-01'
)
-- 9a. By late vs on time
SELECT
    CASE WHEN is_late = 1 THEN 'First order late' ELSE 'First order on time' END AS first_order,
    COUNT(*)                                                      AS customers,
    COUNT(*) FILTER (WHERE total_orders > 1)                      AS reordered,
    ROUND(100.0 * COUNT(*) FILTER (WHERE total_orders > 1) / COUNT(*), 2) AS repeat_rate_pct
FROM first_orders
GROUP BY is_late
ORDER BY is_late;

-- 9b. Same question by delay bucket (run the CTE above again with this SELECT)
-- SELECT delay_bucket, COUNT(*) AS customers,
--        ROUND(100.0 * COUNT(*) FILTER (WHERE total_orders > 1) / COUNT(*), 2) AS repeat_rate_pct
-- FROM first_orders GROUP BY delay_bucket ORDER BY delay_bucket;


-- ------------------------------------------------------------
-- Q10. Monthly cohort retention (2017 cohorts, first 12 months)
-- Business meaning: of the customers who joined in month X, what %
-- bought again N months later?
-- Skill: window function MIN() OVER + cohort logic
-- ------------------------------------------------------------
WITH customer_months AS (
    SELECT
        customer_unique_id,
        purchase_month,
        MIN(purchase_month) OVER (PARTITION BY customer_unique_id) AS cohort_month
    FROM order_analysis
),
activity AS (
    SELECT
        cohort_month,
        ((EXTRACT(YEAR  FROM purchase_month) - EXTRACT(YEAR  FROM cohort_month)) * 12
         + EXTRACT(MONTH FROM purchase_month) - EXTRACT(MONTH FROM cohort_month))::int AS month_number,
        COUNT(DISTINCT customer_unique_id) AS active_customers
    FROM customer_months
    GROUP BY cohort_month, month_number
),
cohort_size AS (
    SELECT cohort_month, active_customers AS cohort_customers
    FROM activity
    WHERE month_number = 0
)
SELECT
    a.cohort_month,
    a.month_number,
    a.active_customers,
    c.cohort_customers,
    ROUND(100.0 * a.active_customers / c.cohort_customers, 2) AS retention_pct
FROM activity a
JOIN cohort_size c ON c.cohort_month = a.cohort_month
WHERE a.cohort_month BETWEEN DATE '2017-01-01' AND DATE '2017-12-01'
  AND a.month_number BETWEEN 0 AND 12
ORDER BY a.cohort_month, a.month_number;
