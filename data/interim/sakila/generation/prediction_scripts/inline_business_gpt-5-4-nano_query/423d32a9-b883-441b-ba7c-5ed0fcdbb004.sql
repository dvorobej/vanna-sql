WITH
payments AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    s.o07 AS staff_store_id,
    co.c01 AS country_id,
    co.c02 AS country_name,
    ct.d01 AS city_id,
    ct.d02 AS city_name
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ct.d03
  JOIN stf AS s
    ON s.o01 = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
),
monthly AS (
  SELECT
    customer_id,
    month_start,
    country_id,
    country_name,
    city_id,
    city_name,
    SUM(payment_amount) AS month_payment_sum,
    COUNT(*) AS month_payment_count,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    COUNT(DISTINCT staff_store_id) AS distinct_store_count
  FROM payments
  GROUP BY
    customer_id, month_start, country_id, country_name, city_id, city_name
),
monthly_with_prev_avg AS (
  SELECT
    m.*,
    AVG(month_payment_sum) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_payment_sum
  FROM monthly AS m
),
candidates AS (
  SELECT
    mw.*,
    (mw.month_payment_sum - mw.prev_avg_payment_sum) AS deviation_from_prev_avg,
    RANK() OVER (
      PARTITION BY mw.country_id, mw.month_start
      ORDER BY (mw.month_payment_sum - mw.prev_avg_payment_sum) DESC
    ) AS country_deviation_rank
  FROM monthly_with_prev_avg AS mw
  WHERE mw.prev_avg_payment_sum IS NOT NULL
    AND mw.month_payment_count >= 5
    AND (mw.distinct_staff_count >= 2 OR mw.distinct_store_count >= 2)
    AND mw.month_payment_sum >= 2.0 * mw.prev_avg_payment_sum
),
clients_all_months AS (
  SELECT
    customer_id,
    COUNT(*) AS qualifying_months_count
  FROM candidates
  GROUP BY customer_id
)
SELECT
  c.customer_id,
  cu.h03 AS first_name,
  cu.h04 AS last_name,
  strftime('%Y-%m', cand.month_start) AS payment_month,
  cand.country_name AS country,
  cand.city_name AS city,
  ROUND(cand.month_payment_sum, 2) AS total_payment_amount,
  cand.month_payment_count AS payment_count,
  ROUND(cand.deviation_from_prev_avg, 2) AS deviation_from_prev_avg,
  cand.country_deviation_rank AS country_deviation_rank
FROM clients_all_months c
JOIN cus cu ON cu.h01 = c.customer_id
JOIN candidates cand ON cand.customer_id = c.customer_id
WHERE c.qualifying_months_count = 11
ORDER BY
  cand.country_name,
  cand.month_start,
  cand.country_deviation_rank,
  cand.customer_id;