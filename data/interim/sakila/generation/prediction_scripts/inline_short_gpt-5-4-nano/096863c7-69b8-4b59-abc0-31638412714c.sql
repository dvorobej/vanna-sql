WITH daily_customer AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_day,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
customer_daily_with_avg AS (
  SELECT
    dc.*,
    (
      SELECT AVG(dc_prev.day_amount)
      FROM daily_customer AS dc_prev
      WHERE dc_prev.customer_id = dc.customer_id
        AND dc_prev.payment_day >= date(dc.payment_day, '-30 day')
        AND dc_prev.payment_day < dc.payment_day
    ) AS avg_prev_30d
  FROM daily_customer AS dc
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c02 AS country_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = ct.d03
),
country_daily_avg AS (
  SELECT
    cg.country_name,
    dce.payment_day,
    AVG(dce.day_amount) AS country_avg_daily_amount
  FROM customer_daily_with_avg AS dce
  JOIN customer_geo AS cg
    ON cg.customer_id = dce.customer_id
  GROUP BY
    cg.country_name,
    dce.payment_day
),
joined AS (
  SELECT
    dca.customer_id,
    cg.country_name,
    dca.payment_day,
    dca.payment_count,
    dca.day_amount,
    dca.staff_count,
    dca.store_count,
    cda.country_avg_daily_amount,
    (dca.day_amount / NULLIF(dca.avg_prev_30d, 0)) AS ratio_vs_personal_avg,
    (dca.day_amount / NULLIF(cda.country_avg_daily_amount, 0)) AS ratio_vs_country_avg
  FROM customer_daily_with_avg AS dca
  JOIN customer_geo AS cg
    ON cg.customer_id = dca.customer_id
  JOIN country_daily_avg AS cda
    ON cda.country_name = cg.country_name
   AND cda.payment_day = dca.payment_day
)
SELECT
  j.customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  cg.country_name AS country,
  j.payment_day AS payment_date,
  j.payment_count,
  ROUND(j.day_amount, 2) AS day_amount,
  ROUND(j.avg_prev_30d, 2) AS avg_prev_30d,
  ROUND(j.ratio_vs_personal_avg, 2) AS personal_exceed_ratio,
  ROUND(j.country_avg_daily_amount, 2) AS country_avg_daily_amount,
  ROUND(j.ratio_vs_country_avg, 2) AS country_exceed_ratio,
  RANK() OVER (
    PARTITION BY cg.country_name, j.payment_day
    ORDER BY j.day_amount DESC
  ) AS day_amount_rank_in_country
FROM joined AS j
JOIN cus AS c
  ON c.h01 = j.customer_id
JOIN customer_geo AS cg
  ON cg.customer_id = j.customer_id
WHERE
  j.avg_prev_30d IS NOT NULL
  AND j.day_amount > j.avg_prev_30d * 3
  AND j.staff_count >= 2 OR j.store_count >= 2
ORDER BY
  j.country_name,
  day_amount_rank_in_country,
  j.payment_day,
  j.day_amount DESC,
  j.customer_id;