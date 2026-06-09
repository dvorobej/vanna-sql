WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    adr_cty.d02 AS city_name,
    cnt.c02 AS country_name,
    c.h02 AS home_store_id
  FROM cus AS c
  JOIN adr AS a_cus ON a_cus.e01 = c.h06
  JOIN cty AS adr_cty ON adr_cty.d01 = a_cus.e05
  JOIN cnt ON cnt.c01 = adr_cty.d03
),
payments_base AS (
  SELECT
    p.p02 AS customer_id,
    p.p06 AS payment_date,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p01 AS payment_id,
    p.p03 AS staff_id,
    r.q01 AS rental_id,
    r.q05 AS return_date,
    rg.country_name,
    rg.city_name,
    rg.home_store_id,
    COALESCE(i.n03, rg.home_store_id) AS store_id
  FROM pay AS p
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
  JOIN customer_geo AS rg
    ON rg.customer_id = p.p02
),
monthly_customer_store AS (
  SELECT
    store_id,
    country_name,
    city_name,
    month_start,
    COUNT(payment_id) AS payment_count,
    SUM(payment_amount) AS month_payment_sum,
    COUNT(DISTINCT staff_id) AS staff_count,
    AVG(
      CASE
        WHEN return_date IS NOT NULL AND return_date > payment_date THEN 1.0
        WHEN return_date IS NULL THEN NULL
        ELSE 0.0
      END
    ) AS avg_overdue_return_share
  FROM payments_base
  GROUP BY
    store_id, country_name, city_name, month_start
),
store_country_p95 AS (
  SELECT
    store_id,
    country_name,
    month_start,
    month_payment_sum,
    PERCENT_RANK() OVER (
      PARTITION BY store_id, country_name, month_start
      ORDER BY month_payment_sum
    ) AS pr_asc
  FROM monthly_customer_store
),
monthly_ranked AS (
  SELECT
    m.*,
    AVG(m.month_payment_sum) OVER (
      PARTITION BY m.store_id, m.country_name, m.city_name
      ORDER BY m.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS avg_prev_amount,
    PERCENT_RANK() OVER (
      PARTITION BY m.store_id, m.country_name
      ORDER BY m.month_payment_sum DESC
    ) AS payment_sum_rank_pct
  FROM monthly_customer_store AS m
)
SELECT
  mr.country_name,
  mr.city_name,
  mr.store_id AS store_id,
  strftime('%Y-%m', mr.month_start) AS payment_month,
  ROUND(mr.month_payment_sum, 2) AS month_payment_sum,
  mr.payment_count,
  mr.staff_count AS staff_count,
  ROUND(COALESCE(mr.avg_overdue_return_share, 0.0), 4) AS overdue_return_share,
  mr.payment_sum_rank_pct AS payment_sum_rank
FROM monthly_ranked AS mr
LEFT JOIN store_country_p95 AS p95
  ON p95.store_id = mr.store_id
 AND p95.country_name = mr.country_name
 AND p95.month_start = mr.month_start
 AND p95.month_payment_sum = mr.month_payment_sum
WHERE
  mr.avg_prev_amount IS NOT NULL
  AND mr.avg_prev_amount > 0
  AND mr.month_payment_sum > 3.0 * mr.avg_prev_amount
  AND mr.month_payment_sum >= (
    SELECT
      MAX(m2.month_payment_sum)
    FROM store_country_p95 AS m2
    WHERE m2.store_id = mr.store_id
      AND m2.country_name = mr.country_name
      AND m2.month_start = mr.month_start
      AND m2.pr_asc >= 0.95
  )
ORDER BY
  mr.country_name,
  mr.store_id,
  mr.month_start,
  mr.month_payment_sum DESC;