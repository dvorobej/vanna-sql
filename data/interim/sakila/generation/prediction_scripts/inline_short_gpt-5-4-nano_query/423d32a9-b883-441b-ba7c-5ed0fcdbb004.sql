WITH RECURSIVE
months(month_start) AS (
  SELECT date('2005-01-01')
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < date('2006-01-01')
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    co.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
),
monthly_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS month_total_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  LEFT JOIN stf AS s ON s.o01 = p.p03
  WHERE date(p.p06, 'start of month') >= '2005-01-01'
    AND date(p.p06, 'start of month') <  '2006-01-01'
  GROUP BY p.p02, date(p.p06, 'start of month')
),
monthly_series AS (
  SELECT
    cg.customer_id,
    cg.country_name,
    cg.city_name,
    m.month_start,
    COALESCE(mp.payment_count, 0) AS payment_count,
    COALESCE(mp.month_total_amount, 0) AS month_total_amount,
    COALESCE(mp.staff_count, 0) AS staff_count,
    COALESCE(mp.store_count, 0) AS store_count
  FROM customer_geo AS cg
  CROSS JOIN months AS m
  LEFT JOIN monthly_pay AS mp
    ON mp.customer_id = cg.customer_id
   AND mp.month_start = m.month_start
),
with_prev_avg AS (
  SELECT
    ms.*,
    AVG(ms.month_total_amount) OVER (
      PARTITION BY ms.customer_id
      ORDER BY ms.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_month_total
  FROM monthly_series AS ms
),
qualifying_months AS (
  SELECT
    wpa.*,
    (wpa.month_total_amount - wpa.prev_avg_month_total) AS deviation_from_prev_avg
  FROM with_prev_avg AS wpa
  WHERE wpa.prev_avg_month_total IS NOT NULL
    AND wpa.payment_count >= 5
    AND wpa.month_total_amount >= 2.0 * wpa.prev_avg_month_total
    AND (wpa.staff_count >= 2 OR wpa.store_count >= 2)
),
customers_all_months AS (
  SELECT
    qm.customer_id
  FROM qualifying_months AS qm
  GROUP BY qm.customer_id
  HAVING COUNT(*) = 11
),
final AS (
  SELECT
    qm.customer_id,
    qm.month_start,
    qm.country_name,
    qm.city_name,
    qm.month_total_amount AS month_total_amount,
    qm.payment_count,
    qm.deviation_from_prev_avg,
    RANK() OVER (
      PARTITION BY qm.country_name, qm.month_start
      ORDER BY qm.deviation_from_prev_avg DESC
    ) AS country_month_deviation_rank
  FROM qualifying_months AS qm
  JOIN customers_all_months AS cam
    ON cam.customer_id = qm.customer_id
)
SELECT
  month_start AS month,
  customer_id,
  country_name AS country,
  city_name AS city,
  ROUND(month_total_amount, 2) AS month_total_amount,
  payment_count,
  ROUND(deviation_from_prev_avg, 2) AS deviation_from_prev_avg,
  country_month_deviation_rank
FROM final
ORDER BY
  month,
  country,
  country_month_deviation_rank,
  customer_id;