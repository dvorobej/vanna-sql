WITH payment_details AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS amount,
    p.p03 AS staff_id,
    s.o07 AS staff_store_id,
    cn.c02 AS country_name,
    ci.d02 AS city_name
  FROM pay AS p
  JOIN cus AS c ON c.h01 = p.p02
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS cn ON cn.c01 = ci.d03
  JOIN stf AS s ON s.o01 = p.p03
),
monthly_activity AS (
  SELECT
    customer_id,
    month_start,
    COUNT(payment_id) AS payment_count,
    SUM(amount) AS total_amount,
    MAX(amount) AS max_payment,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    COUNT(DISTINCT staff_store_id) AS distinct_store_count,
    MAX(country_name) AS country_name,
    MAX(city_name) AS city_name
  FROM payment_details
  GROUP BY
    customer_id,
    month_start
),
with_history AS (
  SELECT
    ma.*,
    AVG(total_amount) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev_avg_month_amount
  FROM monthly_activity AS ma
),
ranked AS (
  SELECT
    wh.*,
    RANK() OVER (
      PARTITION BY country_name, month_start
      ORDER BY total_amount DESC
    ) AS customer_country_month_rank
  FROM with_history AS wh
)
SELECT
  c.h03 AS first_name,
  c.h04 AS last_name,
  r.country_name AS country,
  r.city_name AS city,
  r.month_start AS payment_month,
  r.payment_count,
  ROUND(r.total_amount, 2) AS total_amount,
  ROUND(r.max_payment, 2) AS max_payment,
  ROUND(r.max_payment / NULLIF(r.total_amount, 0), 4) AS max_payment_share,
  r.distinct_staff_count AS distinct_staff_count,
  r.distinct_store_count AS distinct_store_count,
  r.customer_country_month_rank AS customer_rank_in_country
FROM ranked AS r
JOIN cus AS c ON c.h01 = r.customer_id
WHERE r.prev_avg_month_amount IS NOT NULL
  AND r.payment_count >= 3
  AND r.total_amount >= 3.0 * r.prev_avg_month_amount
  AND (r.distinct_staff_count >= 2 OR r.distinct_store_count >= 2)
ORDER BY
  r.country_name,
  r.month_start,
  r.customer_country_month_rank,
  r.total_amount DESC;