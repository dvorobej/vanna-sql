WITH
payment_monthly AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS month_payment_sum,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT st.o07) AS store_count
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  JOIN stf st ON st.o01 = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
with_prev_avg AS (
  SELECT
    pm.*,
    AVG(pm.month_payment_sum) OVER (
      PARTITION BY pm.customer_id
      ORDER BY pm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_payment_sum,
    COUNT(*) OVER (
      PARTITION BY pm.customer_id
      ORDER BY pm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_count
  FROM payment_monthly pm
),
qualifying AS (
  SELECT
    wpa.*,
    (wpa.month_payment_sum - wpa.prev_avg_payment_sum) AS deviation_from_prev_avg
  FROM with_prev_avg wpa
  WHERE wpa.prev_months_count > 0
    AND wpa.prev_avg_payment_sum > 0
    AND wpa.month_payment_sum >= 2.0 * wpa.prev_avg_payment_sum
    AND wpa.payment_count >= 5
    AND (wpa.staff_count >= 2 OR wpa.store_count >= 2)
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c02 AS country_name,
    cty.d02 AS city_name
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ON cty.d01 = a.e05
  JOIN cnt ON cnt.c01 = cty.d03
),
client_all_months AS (
  SELECT
    customer_id,
    COUNT(*) AS qualifying_months_cnt,
    COUNT(*) FILTER (WHERE 1=1) AS total_months_cnt
  FROM (
    SELECT
      customer_id,
      month_start
    FROM payment_monthly
  )
  GROUP BY customer_id
),
final_months AS (
  SELECT
    q.customer_id,
    q.month_start,
    q.month_payment_sum,
    q.payment_count,
    q.prev_avg_payment_sum,
    q.deviation_from_prev_avg,
    cg.country_name,
    cg.city_name
  FROM qualifying q
  JOIN customer_geo cg ON cg.customer_id = q.customer_id
)
SELECT
  fm.month_start AS month,
  fm.customer_id,
  fm.country_name AS country,
  fm.city_name AS city,
  fm.month_payment_sum AS month_payment_sum,
  fm.payment_count AS payment_count,
  fm.deviation_from_prev_avg AS deviation_from_prev_avg,
  RANK() OVER (
    PARTITION BY fm.country_name, fm.month_start
    ORDER BY fm.deviation_from_prev_avg DESC
  ) AS country_deviation_rank
FROM final_months fm
WHERE fm.customer_id IN (
  SELECT
    q.customer_id
  FROM qualifying q
  WHERE q.month_start >= '2005-01-01'
    AND q.month_start <  '2006-01-01'
  GROUP BY q.customer_id
  HAVING COUNT(*) = 11
)
ORDER BY
  month,
  country,
  country_deviation_rank,
  customer_id;