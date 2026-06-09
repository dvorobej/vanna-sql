WITH monthly AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_key,
    SUM(p.p05) AS month_sum,
    COUNT(*) AS month_payment_count,
    COUNT(DISTINCT p.p03) AS staff_count_distinct,
    COUNT(DISTINCT s.o07) AS store_count_distinct
  FROM pay p
  JOIN stf s
    ON s.o01 = p.p03
  WHERE p.p06 >= '2004-01-01' AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
monthly_with_prev3 AS (
  SELECT
    m.*,
    AVG(m2.month_sum) AS avg_prev3_month_sum
  FROM monthly m
  LEFT JOIN monthly m2
    ON m2.customer_id = m.customer_id
   AND m2.month_key < m.month_key
   AND m2.month_key >= strftime('%Y-%m', date(m.month_key || '-01', '-3 months'))
   AND m2.month_key <  strftime('%Y-%m', date(m.month_key || '-01', '-0 months'))
  GROUP BY
    m.customer_id,
    m.month_key,
    m.month_sum,
    m.month_payment_count,
    m.staff_count_distinct,
    m.store_count_distinct
),
monthly_country_rank AS (
  SELECT
    m.*,
    c.h01 AS customer_id_check
  FROM monthly m
  JOIN cus c
    ON c.h01 = m.customer_id
),
monthly_with_country_median AS (
  WITH country_month_sums AS (
    SELECT
      c.h01 AS customer_id,
      m.month_key,
      cnt.c01 AS country_id,
      m.month_sum
    FROM monthly m
    JOIN cus c ON c.h01 = m.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty city ON city.d01 = a.e05
    JOIN cnt ON cnt.c01 = city.d03
  )
  SELECT
    cms.customer_id,
    cms.month_key,
    cms.country_id,
    cms.month_sum,
    -- median for the month in the country (average of two middle values when even)
    AVG(t.month_sum) AS median_month_sum_country
  FROM (
    SELECT
      cms.*,
      ROW_NUMBER() OVER (
        PARTITION BY cms.country_id, cms.month_key
        ORDER BY cms.month_sum
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY cms.country_id, cms.month_key
      ) AS cntn
    FROM country_month_sums cms
  ) t
  WHERE
    t.rn IN ( (t.cntn + 1) / 2, (t.cntn + 2) / 2 )
  GROUP BY
    cms.customer_id,
    cms.month_key,
    cms.country_id,
    cms.month_sum
),
monthly_final AS (
  SELECT
    m.customer_id,
    m.month_key,
    m.month_sum,
    m.month_payment_count,
    m.staff_count_distinct,
    m.store_count_distinct,
    np.avg_prev3_month_sum,
    cm.median_month_sum_country,
    cm2.country_id,
    RANK() OVER (
      PARTITION BY cm2.country_id, m.month_key
      ORDER BY m.month_sum DESC
    ) AS country_month_risk_rank,
    COUNT(*) OVER (
      PARTITION BY cm2.country_id, m.month_key
    ) AS country_month_customer_count
  FROM monthly m
  LEFT JOIN monthly_with_prev3 np
    ON np.customer_id = m.customer_id
   AND np.month_key = m.month_key
  JOIN cus c
    ON c.h01 = m.customer_id
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty city
    ON city.d01 = a.e05
  JOIN cnt cm2
    ON cm2.c01 = city.d03
  LEFT JOIN monthly_with_country_median cm
    ON cm.customer_id = m.customer_id
   AND cm.month_key = m.month_key
   AND cm.country_id = cm2.c01
)
SELECT
  mf.customer_id,
  cus.h03 AS customer_first_name,
  cus.h04 AS customer_last_name,
  cnt.c02 AS customer_country,
  mf.month_key AS month,
  ROUND(mf.month_sum, 2) AS month_sum,
  mf.month_payment_count,
  mf.staff_count_distinct,
  mf.store_count_distinct,
  ROUND(mf.avg_prev3_month_sum, 2) AS avg_prev3_month_sum,
  ROUND(mf.median_month_sum_country, 2) AS median_month_sum_country,
  ROUND(mf.month_sum / NULLIF(mf.avg_prev3_month_sum, 0), 2) AS growth_vs_avg_prev3,
  ROUND(mf.month_sum / NULLIF(mf.median_month_sum_country, 0), 2) AS ratio_vs_country_median,
  mf.country_month_risk_rank,
  mf.country_month_customer_count
FROM monthly_final mf
JOIN cus
  ON cus.h01 = mf.customer_id
JOIN adr a
  ON a.e01 = cus.h06
JOIN cty city
  ON city.d01 = a.e05
JOIN cnt
  ON cnt.c01 = city.d03
WHERE
  mf.avg_prev3_month_sum IS NOT NULL
  AND mf.avg_prev3_month_sum > 0
  AND mf.median_month_sum_country IS NOT NULL
  AND mf.median_month_sum_country > 0
  AND mf.month_sum >= 3 * mf.avg_prev3_month_sum
  AND mf.month_sum >= 2 * mf.median_month_sum_country
  AND mf.country_month_risk_rank <= CAST(0.05 * mf.country_month_customer_count AS INT) + 1
ORDER BY
  mf.month_key,
  customer_country,
  ratio_vs_country_median DESC,
  growth_vs_avg_prev3 DESC,
  mf.customer_id;