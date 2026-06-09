WITH payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    co.c02 AS country_name,
    ci.d02 AS city_name,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    s.o07 AS staff_store_id
  FROM pay p
  JOIN cus c
    ON c.h01 = p.p02
  JOIN adr ca
    ON ca.e01 = c.h06
  JOIN cty ci
    ON ci.d01 = ca.e05
  JOIN cnt co
    ON co.c01 = ci.d03
  JOIN stf s
    ON s.o01 = p.p03
),
monthly AS (
  SELECT
    customer_id,
    first_name,
    last_name,
    country_name,
    city_name,
    month_start,
    COUNT(*) AS payment_count,
    SUM(payment_amount) AS month_sum,
    AVG(payment_amount) AS avg_payment,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    COUNT(DISTINCT staff_store_id) AS distinct_store_count
  FROM payment_base
  GROUP BY
    customer_id, first_name, last_name, country_name, city_name, month_start
),
with_prev_avg AS (
  SELECT
    m.*,
    AVG(month_sum) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_month_sum
  FROM monthly m
),
candidates AS (
  SELECT
    w.*,
    (w.month_sum - w.prev_avg_month_sum) AS deviation_from_prev_avg,
    RANK() OVER (
      PARTITION BY w.country_name, w.month_start
      ORDER BY (w.month_sum - w.prev_avg_month_sum) DESC
    ) AS country_deviation_rank
  FROM with_prev_avg w
  WHERE w.prev_avg_month_sum IS NOT NULL
    AND w.payment_count >= 5
    AND (w.distinct_staff_count >= 2 OR w.distinct_store_count >= 2)
    AND w.month_sum >= 2.0 * w.prev_avg_month_sum
),
qualifying_clients AS (
  -- for each client, require that ALL months in 2005 satisfy the condition above
  SELECT
    customer_id
  FROM (
    SELECT
      customer_id,
      COUNT(*) AS ok_month_count,
      COUNT(CASE WHEN month_start IS NOT NULL THEN 1 END) AS total_months
    FROM candidates
    WHERE month_start >= '2005-01-01' AND month_start < '2006-01-01'
    GROUP BY customer_id
  ) x
  WHERE ok_month_count = 12
)
SELECT
  c.month_start AS month,
  c.customer_id,
  c.first_name,
  c.last_name,
  c.country_name,
  c.city_name,
  ROUND(c.month_sum, 2) AS month_payment_sum,
  c.payment_count,
  ROUND(c.deviation_from_prev_avg, 2) AS deviation_from_prev_avg,
  c.country_deviation_rank
FROM candidates c
JOIN qualifying_clients q
  ON q.customer_id = c.customer_id
WHERE c.month_start >= '2005-01-01' AND c.month_start < '2006-01-01'
ORDER BY c.customer_id, c.month_start;