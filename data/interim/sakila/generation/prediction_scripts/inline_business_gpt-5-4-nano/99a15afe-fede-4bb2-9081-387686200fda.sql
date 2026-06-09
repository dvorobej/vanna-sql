WITH customer_base AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    c.h06 AS address_id,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    ci.d02 AS city_name,
    sto.j01 AS home_store_id
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt ON cnt.c01 = ci.d03
  JOIN sto ON sto.j01 = c.h02
),
payments_enriched AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p06 AS payment_ts,
    p.p05 AS amount,
    p.p03 AS staff_id,
    s.o07 AS store_id,
    rb.q01 AS rental_id,
    rb.q02 AS rental_ts,
    rb.q03 AS inventory_id,
    rb.q05 AS return_ts,
    rb.q07 AS rental_updated_ts,
    cb.country_id,
    cb.country_name,
    cb.city_name,
    cb.home_store_id
  FROM pay AS p
  JOIN customer_base AS cb ON cb.customer_id = p.p02
  JOIN ren AS rb ON rb.q01 = p.p04
  JOIN stf AS s ON s.o01 = p.p03
),
monthly_customer AS (
  SELECT
    pe.customer_id,
    pe.month_start,
    MAX(pe.country_id) AS country_id,
    MAX(pe.country_name) AS country_name,
    MAX(pe.city_name) AS city_name,
    MAX(pe.home_store_id) AS home_store_id,
    SUM(pe.amount) AS month_total_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT pe.staff_id) AS distinct_staff_count,
    COUNT(*) AS month_payment_rows
  FROM payments_enriched AS pe
  GROUP BY
    pe.customer_id,
    pe.month_start
),
monthly_customer_prev_avg AS (
  SELECT
    mc.*,
    AVG(mc.month_total_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_month_total_amount
  FROM monthly_customer AS mc
),
monthly_store_country AS (
  SELECT
    ce.store_id,
    ce.country_id,
    ce.month_start,
    SUM(ce.amount) AS store_country_month_total_amount
  FROM payments_enriched AS ce
  GROUP BY
    ce.store_id,
    ce.country_id,
    ce.month_start
),
store_country_month_customer_amounts AS (
  SELECT
    pe.store_id,
    pe.country_id,
    pe.month_start,
    pe.customer_id,
    SUM(pe.amount) AS customer_month_total_amount
  FROM payments_enriched AS pe
  GROUP BY
    pe.store_id,
    pe.country_id,
    pe.month_start,
    pe.customer_id
),
store_country_p95 AS (
  SELECT
    scmca.store_id,
    scmca.country_id,
    scmca.month_start,
    scmca.customer_month_total_amount,
    PERCENT_RANK OVER () AS dummy
  FROM store_country_month_customer_amounts AS scmca
),
ranked_store_country_customers AS (
  SELECT
    scmca.*,
    COUNT(*) OVER (PARTITION BY scmca.store_id, scmca.country_id, scmca.month_start) AS cnt,
    ROW_NUMBER() OVER (PARTITION BY scmca.store_id, scmca.country_id, scmca.month_start ORDER BY scmca.customer_month_total_amount) AS rn_asc
  FROM store_country_month_customer_amounts AS scmca
),
store_country_p95_bound AS (
  SELECT
    store_id,
    country_id,
    month_start,
    MAX(CASE
      WHEN rn_asc = CAST(0.95 * (cnt - 1) + 1 AS INTEGER) THEN customer_month_total_amount
      ELSE NULL
    END) AS p95_amount
  FROM ranked_store_country_customers
  GROUP BY
    store_id,
    country_id,
    month_start
),
late_return_payments AS (
  SELECT
    pe.customer_id,
    pe.store_id,
    pe.month_start,
    SUM(CASE
      WHEN pe.return_ts IS NOT NULL
       AND pe.return_ts > datetime(pe.rental_ts, '+' || flm.i07 || ' days')
      THEN 1 ELSE 0
    END) AS late_return_payment_count,
    COUNT(*) AS total_payment_count
  FROM payments_enriched AS pe
  JOIN inv AS inv ON inv.n01 = pe.inventory_id
  JOIN flm ON flm.i01 = inv.n02
  GROUP BY
    pe.customer_id,
    pe.store_id,
    pe.month_start
),
final_rank_customer_in_store AS (
  SELECT
    pe.store_id,
    pe.country_id,
    pe.month_start,
    pe.customer_id,
    RANK() OVER (
      PARTITION BY pe.store_id, pe.country_id, pe.month_start
      ORDER BY SUM(pe.amount) DESC
    ) AS customer_store_month_rank
  FROM payments_enriched AS pe
  GROUP BY
    pe.store_id,
    pe.country_id,
    pe.month_start,
    pe.customer_id
)
SELECT
  cb.customer_id,
  cb.customer_name,
  cb.address_id,
  cb.city_name,
  cb.country_name,
  pe.store_id AS store_id,
  strftime('%Y-%m', pe.month_start) AS payment_month,
  ROUND(mc.month_total_amount, 2) AS month_total_amount,
  mc.payment_count,
  mc.distinct_staff_count,
  ROUND(1.0 * lrp.late_return_payment_count / NULLIF(lrp.total_payment_count, 0), 4) AS late_return_payment_share,
  f.rank AS customer_store_month_rank
FROM monthly_customer_prev_avg AS mc
JOIN customer_base AS cb ON cb.customer_id = mc.customer_id
JOIN payments_enriched AS pe
  ON pe.customer_id = mc.customer_id
 AND pe.month_start = mc.month_start
LEFT JOIN late_return_payments AS lrp
  ON lrp.customer_id = mc.customer_id
 AND lrp.store_id = pe.store_id
 AND lrp.month_start = mc.month_start
JOIN final_rank_customer_in_store AS f
  ON f.customer_id = mc.customer_id
 AND f.store_id = pe.store_id
 AND f.month_start = mc.month_start
 AND f.country_id = mc.country_id
JOIN store_country_p95_bound AS p95
  ON p95.store_id = pe.store_id
 AND p95.country_id = mc.country_id
 AND p95.month_start = mc.month_start
WHERE mc.prev_avg_month_total_amount IS NOT NULL
  AND mc.prev_avg_month_total_amount > 0
  AND mc.month_total_amount >= 3.0 * mc.prev_avg_month_total_amount
  AND p95.p95_amount IS NOT NULL
  AND mc.month_total_amount > p95.p95_amount
ORDER BY
  cb.country_name,
  pe.store_id,
  payment_month,
  month_total_amount DESC,
  cb.customer_id;