WITH monthly_payments AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS pay_month,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS monthly_sum,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT stf.o07) AS store_count
  FROM pay AS p
  JOIN stf AS stf
    ON stf.o01 = p.p03
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c01 AS country_id,
    cnt.c02 AS country,
    cty.d02 AS city
  FROM cus AS c
  JOIN adr AS adr
    ON adr.e01 = c.h06
  JOIN cty AS cty
    ON cty.d01 = adr.e05
  JOIN cnt AS cnt
    ON cnt.c01 = cty.d03
),
monthly_with_prev3 AS (
  SELECT
    mp.*,
    AVG(mp.monthly_sum) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.pay_month
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS avg_prev_3m_sum
  FROM monthly_payments AS mp
),
country_month_stats AS (
  SELECT
    cg.country_id,
    m.pay_month,
    AVG(m.monthly_sum) AS country_avg_sum
  FROM monthly_payments AS m
  JOIN customer_geo AS cg
    ON cg.customer_id = m.customer_id
  GROUP BY
    cg.country_id,
    m.pay_month
),
ranked AS (
  SELECT
    m.customer_id,
    cg.first_name,
    cg.last_name,
    cg.country,
    cg.city,
    m.pay_month,
    m.payment_count,
    m.monthly_sum,
    m.avg_prev_3m_sum,
    m.staff_count,
    m.store_count,
    cms.country_avg_sum,
    RANK() OVER (
      PARTITION BY cg.country_id, m.pay_month
      ORDER BY m.monthly_sum DESC
    ) AS country_month_rank
  FROM monthly_with_prev3 AS m
  JOIN customer_geo AS cg
    ON cg.customer_id = m.customer_id
  JOIN country_month_stats AS cms
    ON cms.country_id = cg.country_id
   AND cms.pay_month = m.pay_month
)
SELECT
  customer_id,
  first_name,
  last_name,
  country,
  city,
  pay_month AS month,
  payment_count,
  ROUND(monthly_sum, 2) AS monthly_sum,
  ROUND(avg_prev_3m_sum, 2) AS avg_prev_3m_sum,
  ROUND(country_avg_sum, 2) AS country_avg_sum,
  staff_count,
  store_count,
  country_month_rank
FROM ranked
WHERE avg_prev_3m_sum IS NOT NULL
  AND monthly_sum > avg_prev_3m_sum * 2
  AND monthly_sum > country_avg_sum * 1.5
  AND (payment_count >= 5 OR staff_count > 1 OR store_count > 1)
ORDER BY
  pay_month,
  country,
  country_month_rank,
  customer_id;