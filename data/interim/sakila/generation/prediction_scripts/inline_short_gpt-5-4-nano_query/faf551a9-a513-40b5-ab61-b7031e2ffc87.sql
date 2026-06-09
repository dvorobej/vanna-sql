WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    ct.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS ct ON ct.c01 = ci.d03
),
daily_staff_store AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    p.p04 AS rental_id,
    p.p03 AS staff_id,
    COALESCE(st.o07, NULL) AS staff_store_id,
    p.p05 AS payment_amount
  FROM pay AS p
  JOIN stf AS st ON st.o01 = p.p03
),
daily_payments AS (
  SELECT
    ds.customer_id,
    cg.first_name,
    cg.last_name,
    cg.country_name,
    cg.city_name,
    ds.payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(ds.payment_amount AS REAL)) AS day_amount,
    MAX(CASE WHEN ds.staff_store_id IS NOT NULL THEN ds.staff_store_id END) AS any_store_id
  FROM daily_staff_store AS ds
  JOIN customer_geo AS cg ON cg.customer_id = ds.customer_id
  GROUP BY
    ds.customer_id,
    cg.first_name,
    cg.last_name,
    cg.country_name,
    cg.city_name,
    ds.payment_date
),
daily_with_personal_avg AS (
  SELECT
    dp.*,
    (
      SELECT AVG(dp2.day_amount)
      FROM daily_payments AS dp2
      WHERE dp2.customer_id = dp.customer_id
        AND dp2.payment_date >= date(dp.payment_date, '-30 day')
        AND dp2.payment_date < dp.payment_date
    ) AS personal_avg_30d
  FROM daily_payments AS dp
),
country_day_ranks AS (
  SELECT
    dwpa.customer_id,
    dwpa.country_name,
    dwpa.payment_date,
    dwpa.day_amount,
    (
      SELECT COUNT(*)
      FROM daily_payments AS dp3
      WHERE dp3.country_name = dwpa.country_name
    ) AS country_total_days,
    ROW_NUMBER() OVER (
      PARTITION BY dwpa.country_name
      ORDER BY dwpa.day_amount DESC
    ) AS rn_desc
  FROM daily_with_personal_avg AS dwpa
),
thresholded AS (
  SELECT
    dwpa.*,
    cd.rn_desc,
    cd.country_total_days,
    CAST(CEIL(0.95 * cd.country_total_days) AS INT) AS p95_min_rank_desc
  FROM daily_with_personal_avg AS dwpa
  JOIN country_day_ranks AS cd
    ON cd.customer_id = dwpa.customer_id
   AND cd.payment_date = dwpa.payment_date
   AND cd.country_name = dwpa.country_name
)
SELECT
  t.payment_date AS splash_date,
  t.first_name,
  t.last_name,
  t.country_name,
  t.city_name,
  s.j01 AS store_id,
  t.payment_count,
  ROUND(t.day_amount, 2) AS day_amount,
  ROUND(t.personal_avg_30d, 2) AS avg_prev_30_days,
  ROUND(t.day_amount - t.personal_avg_30d, 2) AS deviation_from_avg,
  RANK() OVER (
    PARTITION BY t.country_name
    ORDER BY t.day_amount DESC
  ) AS customer_splash_rank_within_country
FROM thresholded AS t
JOIN pay AS p
  ON p.p02 = t.customer_id
 AND date(p.p06) = t.payment_date
JOIN stf AS st
  ON st.o01 = p.p03
JOIN sto AS s
  ON s.j01 = st.o07
WHERE t.personal_avg_30d IS NOT NULL
  AND t.personal_avg_30d > 0
  AND t.day_amount >= 3.0 * t.personal_avg_30d
  AND t.day_amount IS NOT NULL
  AND t.rn_desc <= t.p95_min_rank_desc
GROUP BY
  t.payment_date,
  t.first_name,
  t.last_name,
  t.country_name,
  t.city_name,
  s.j01,
  t.payment_count,
  t.day_amount,
  t.personal_avg_30d,
  t.rn_desc,
  t.p95_min_rank_desc
ORDER BY
  t.country_name,
  customer_splash_rank_within_country,
  t.payment_date,
  t.customer_id;