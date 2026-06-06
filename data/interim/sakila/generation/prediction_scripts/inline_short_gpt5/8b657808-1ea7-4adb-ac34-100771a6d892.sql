WITH customer_month AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c01 AS country_id,
    cnt.c02 AS country,
    cty.d02 AS city,
    strftime('%Y-%m', p.p06) AS payment_month,
    SUM(CAST(p.p05 AS REAL)) AS monthly_sum,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT COALESCE(inv.n03, stf.o07)) AS store_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS adr
    ON adr.e01 = c.h06
  JOIN cty AS cty
    ON cty.d01 = adr.e05
  JOIN cnt AS cnt
    ON cnt.c01 = cty.d03
  JOIN stf AS stf
    ON stf.o01 = p.p03
  LEFT JOIN ren AS ren
    ON ren.q01 = p.p04
  LEFT JOIN inv AS inv
    ON inv.n01 = ren.q03
  GROUP BY
    c.h01,
    c.h03,
    c.h04,
    cnt.c01,
    cnt.c02,
    cty.d02,
    strftime('%Y-%m', p.p06)
),
customer_month_with_prev AS (
  SELECT
    cm.*,
    (
      SELECT AVG(cm2.monthly_sum)
      FROM customer_month AS cm2
      WHERE cm2.customer_id = cm.customer_id
        AND cm2.payment_month >= strftime('%Y-%m', date(cm.payment_month || '-01', '-3 months'))
        AND cm2.payment_month < cm.payment_month
    ) AS prev_3m_avg_sum,
    (
      SELECT AVG(cm2.payment_count * 1.0)
      FROM customer_month AS cm2
      WHERE cm2.customer_id = cm.customer_id
        AND cm2.payment_month >= strftime('%Y-%m', date(cm.payment_month || '-01', '-3 months'))
        AND cm2.payment_month < cm.payment_month
    ) AS prev_3m_avg_payment_count
  FROM customer_month AS cm
),
country_month_avg AS (
  SELECT
    country_id,
    payment_month,
    AVG(monthly_sum) AS country_avg_monthly_sum,
    AVG(payment_count * 1.0) AS country_avg_payment_count
  FROM customer_month
  GROUP BY
    country_id,
    payment_month
),
scored AS (
  SELECT
    cmp.customer_id,
    cmp.first_name,
    cmp.last_name,
    cmp.country,
    cmp.city,
    cmp.payment_month,
    cmp.monthly_sum,
    cmp.payment_count,
    cmp.staff_count,
    cmp.store_count,
    cmp.prev_3m_avg_sum,
    cmp.prev_3m_avg_payment_count,
    cma.country_avg_monthly_sum,
    cma.country_avg_payment_count,
    cmp.monthly_sum / NULLIF(cmp.prev_3m_avg_sum, 0) AS ratio_to_prev_3m_avg,
    cmp.monthly_sum / NULLIF(cma.country_avg_monthly_sum, 0) AS ratio_to_country_avg
  FROM customer_month_with_prev AS cmp
  JOIN country_month_avg AS cma
    ON cma.country_id = cmp.country_id
   AND cma.payment_month = cmp.payment_month
  WHERE cmp.prev_3m_avg_sum IS NOT NULL
    AND cmp.prev_3m_avg_sum > 0
    AND cmp.monthly_sum >= cmp.prev_3m_avg_sum * 3
    AND cmp.monthly_sum > cma.country_avg_monthly_sum
    AND cmp.payment_count > cma.country_avg_payment_count
    AND (cmp.staff_count > 1 OR cmp.store_count > 1)
)
SELECT
  customer_id,
  first_name,
  last_name,
  country,
  city,
  payment_month,
  payment_count,
  ROUND(monthly_sum, 2) AS monthly_sum,
  ROUND(prev_3m_avg_sum, 2) AS prev_3m_avg_sum,
  ROUND(country_avg_monthly_sum, 2) AS country_avg_monthly_sum,
  ROUND(ratio_to_prev_3m_avg, 2) AS ratio_to_prev_3m_avg,
  ROUND(ratio_to_country_avg, 2) AS ratio_to_country_avg,
  staff_count,
  store_count,
  RANK() OVER (
    ORDER BY
      ratio_to_prev_3m_avg DESC,
      ratio_to_country_avg DESC,
      monthly_sum DESC
  ) AS suspicion_rank
FROM scored
ORDER BY
  suspicion_rank,
  payment_month,
  country,
  customer_id;