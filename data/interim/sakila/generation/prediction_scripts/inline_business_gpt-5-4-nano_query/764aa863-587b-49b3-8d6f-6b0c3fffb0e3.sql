WITH RECURSIVE
months(month_start) AS (
  SELECT date(MIN(p.p06), 'start of month') FROM pay p
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < (SELECT date(MAX(p2.p06), 'start of month') FROM pay p2)
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_full_name,
    cnt.c02 AS country_name,
    ct.d02 AS city_name,
    c.h02 AS home_store_id
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = ct.d03
),
payment_enriched AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p06 AS payment_ts,
    p.p05 AS payment_amount,
    p.p03 AS staff_id,
    COALESCE(inv.n03, -1) AS issuing_store_id,
    inv.n02 AS film_id,
    flc.l02 AS category_id
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv
    ON inv.n01 = r.q03
  LEFT JOIN flc
    ON flc.l01 = inv.n02
),
customer_month AS (
  SELECT
    cg.customer_id,
    cg.country_name,
    cg.city_name,
    cg.home_store_id,
    m.month_start,
    COUNT(*) AS payment_count,
    SUM(pe.payment_amount) AS month_sum,
    MAX(pe.payment_amount) AS max_payment,
    COUNT(DISTINCT pe.staff_id) AS staff_count,
    SUM(CASE WHEN pe.issuing_store_id <> cg.home_store_id THEN 1 ELSE 0 END) * 1.0
      / NULLIF(COUNT(*), 0) AS share_not_home_store,
    COUNT(DISTINCT pe.category_id) AS distinct_category_count
  FROM customer_geo AS cg
  CROSS JOIN months AS m
  LEFT JOIN payment_enriched AS pe
    ON pe.customer_id = cg.customer_id
   AND pe.month_start = m.month_start
  GROUP BY
    cg.customer_id,
    cg.country_name,
    cg.city_name,
    cg.home_store_id,
    m.month_start
),
with_rolling_avg AS (
  SELECT
    cm.*,
    AVG(cm.month_sum) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS avg_prev_3_months_sum
  FROM customer_month AS cm
  WHERE cm.month_sum IS NOT NULL
),
ranked AS (
  SELECT
    wr.*,
    RANK() OVER (
      PARTITION BY wr.country_name, wr.month_start
      ORDER BY wr.month_sum DESC
    ) AS country_month_rank
  FROM with_rolling_avg AS wr
)
SELECT
  r.month_start AS month,
  r.country_name AS country,
  r.city_name AS city,
  ROUND(r.month_sum, 2) AS payment_sum,
  r.payment_count,
  ROUND(r.max_payment, 2) AS max_payment,
  ROUND(r.share_not_home_store, 4) AS share_not_home_store,
  r.country_month_rank
FROM ranked AS r
WHERE r.avg_prev_3_months_sum > 0
  AND r.month_sum > 3.0 * r.avg_prev_3_months_sum
  AND r.staff_count >= 2
  AND r.distinct_category_count >= 3
ORDER BY
  r.month_start,
  r.country_name,
  r.country_month_rank;