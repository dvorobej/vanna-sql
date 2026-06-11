WITH pay_daily AS (
  SELECT
    p.p02 AS customer_id,
    DATE(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_amount
  FROM pay AS p
  GROUP BY
    p.p02,
    DATE(p.p06)
),
pay_daily_details AS (
  SELECT
    p.p02 AS customer_id,
    DATE(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    p.p02,
    DATE(p.p06)
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c02 AS country,
    cty.d02 AS city
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
),
daily_with_personal_avg AS (
  SELECT
    pdd.*,
    cg.country,
    cg.city,
    (
      SELECT AVG(pdd_prev.day_amount)
      FROM pay_daily_details AS pdd_prev
      WHERE pdd_prev.customer_id = pdd.customer_id
        AND pdd_prev.payment_date >= DATE(pdd.payment_date, '-30 days')
        AND pdd_prev.payment_date < pdd.payment_date
    ) AS personal_avg_prev_30d
  FROM pay_daily_details AS pdd
  JOIN customer_geo AS cg
    ON cg.customer_id = pdd.customer_id
),
country_daily_avg AS (
  SELECT
    dwp.country,
    dwp.payment_date,
    AVG(dwp.day_amount) AS country_avg_day_amount
  FROM daily_with_personal_avg AS dwp
  GROUP BY
    dwp.country,
    dwp.payment_date
),
scored AS (
  SELECT
    dwp.customer_id,
    dwp.city,
    dwp.country,
    dwp.payment_date,
    dwp.payment_count,
    dwp.day_amount,
    dwp.staff_count,
    dwp.store_count,
    dwp.day_amount - dwp.personal_avg_prev_30d AS deviation_personal_avg,
    dwp.day_amount - cda.country_avg_day_amount AS deviation_country_avg,
    cda.country_avg_day_amount
  FROM daily_with_personal_avg AS dwp
  JOIN country_daily_avg AS cda
    ON cda.country = dwp.country
   AND cda.payment_date = dwp.payment_date
  WHERE dwp.personal_avg_prev_30d IS NOT NULL
    AND cda.country_avg_day_amount IS NOT NULL
)
SELECT
  s.customer_id,
  s.country,
  s.city,
  s.payment_date AS date,
  ROUND(s.day_amount, 2) AS daily_sum,
  s.payment_count,
  ROUND(s.deviation_personal_avg, 2) AS deviation_from_personal_avg,
  ROUND(s.deviation_country_avg, 2) AS deviation_from_country_avg,
  s.staff_count AS distinct_staff_count,
  s.store_count AS distinct_store_count,
  DENSE_RANK() OVER (
    PARTITION BY s.country
    ORDER BY s.day_amount DESC
  ) AS country_suspicious_rank
FROM scored AS s
WHERE s.day_amount > 3 * s.personal_avg_prev_30d
  AND s.day_amount > s.country_avg_day_amount
  AND (s.staff_count >= 2 OR s.store_count >= 2)
ORDER BY
  s.country,
  country_suspicious_rank,
  s.payment_date,
  s.customer_id;