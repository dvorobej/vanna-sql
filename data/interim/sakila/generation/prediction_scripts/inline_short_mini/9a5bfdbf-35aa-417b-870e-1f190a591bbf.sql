WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt ON cnt.c01 = ct.d03
),
staff_geo AS (
  SELECT
    s.o01 AS staff_id,
    cnt.c02 AS staff_country_name
  FROM stf AS s
  JOIN adr AS a ON a.e01 = s.o04
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt ON cnt.c01 = ct.d03
),
payment_monthly AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS pay_month,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS monthly_sum,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count,
    MAX(CASE WHEN sg.staff_country_name <> cg.country_name THEN 1 ELSE 0 END) AS has_foreign_staff_payment
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  JOIN staff_geo AS sg ON sg.staff_id = s.o01
  JOIN cus AS c ON c.h01 = p.p02
  JOIN customer_geo AS cg ON cg.customer_id = c.h01
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
payment_monthly_hist AS (
  SELECT
    pm.*,
    AVG(pm.monthly_sum) OVER (
      PARTITION BY pm.customer_id
      ORDER BY pm.pay_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS hist_avg_monthly_sum,
    COUNT(*) OVER (
      PARTITION BY pm.customer_id
      ORDER BY pm.pay_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS hist_month_count
  FROM payment_monthly AS pm
),
ranked AS (
  SELECT
    pmh.*,
    cg.first_name,
    cg.last_name,
    cg.country_name,
    RANK() OVER (
      ORDER BY (pmh.monthly_sum - pmh.hist_avg_monthly_sum) DESC
    ) AS excess_rank
  FROM payment_monthly_hist AS pmh
  JOIN customer_geo AS cg
    ON cg.customer_id = pmh.customer_id
)
SELECT
  pay_month AS month,
  first_name,
  last_name,
  country_name AS customer_country,
  payment_count,
  ROUND(monthly_sum, 2) AS monthly_sum,
  ROUND(hist_avg_monthly_sum, 2) AS historical_avg_monthly_sum,
  ROUND(monthly_sum - hist_avg_monthly_sum, 2) AS deviation_from_history,
  distinct_staff_count,
  distinct_store_count,
  excess_rank
FROM ranked
WHERE payment_count >= 5
  AND hist_month_count >= 1
  AND hist_avg_monthly_sum > 0
  AND monthly_sum > hist_avg_monthly_sum * 2
  AND has_foreign_staff_payment = 1
ORDER BY
  excess_rank,
  month,
  monthly_sum DESC,
  last_name,
  first_name;