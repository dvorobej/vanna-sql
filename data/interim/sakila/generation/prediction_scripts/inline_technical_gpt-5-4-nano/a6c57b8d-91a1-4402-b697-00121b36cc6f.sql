WITH monthly AS (
  SELECT
    p.p02 AS customer_id,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    cty.d02 AS city_name,
    strftime('%Y-%m', p.p06) AS month_ym,
    SUM(p.p05) AS month_amount,
    COUNT(*) AS month_payments
  FROM pay p
  JOIN ren r
    ON r.q01 = p.p04
  JOIN cus c
    ON c.h01 = p.p02
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    cnt.c01,
    cnt.c02,
    cty.d02,
    strftime('%Y-%m', p.p06)
),
customer_baseline AS (
  SELECT
    m.*,
    AVG(m.month_amount) OVER (
      PARTITION BY m.customer_id
    ) AS personal_avg_month_amount
  FROM monthly m
),
country_p10_threshold AS (
  SELECT
    m.country_id,
    m.month_ym,
    m.country_name,
    m.city_name,
    -- upper 10% threshold by "month_amount" within each country+month
    (SELECT
       x.month_amount
     FROM (
       SELECT
         m2.month_amount,
         NTILE(10) OVER (PARTITION BY m2.country_id, m2.month_ym ORDER BY m2.month_amount) AS dec
       FROM monthly m2
       WHERE m2.country_id = m.country_id
         AND m2.month_ym = m.month_ym
     ) x
     WHERE x.dec = 10
     LIMIT 1
    ) AS country_top10_threshold
  FROM monthly m
  GROUP BY
    m.country_id, m.month_ym, m.country_name, m.city_name
),
selected AS (
  SELECT
    cb.*,
    (cb.month_amount / NULLIF(cb.personal_avg_month_amount, 0)) AS personal_multiplier,
    ROW_NUMBER() OVER (
      PARTITION BY cb.country_id, cb.month_ym
      ORDER BY cb.month_amount DESC
    ) AS customer_rank_in_country
  FROM customer_baseline cb
  JOIN country_p10_threshold t
    ON t.country_id = cb.country_id
   AND t.month_ym = cb.month_ym
),
top_employee AS (
  SELECT
    p.p02 AS customer_id,
    cnt.c01 AS country_id,
    strftime('%Y-%m', p.p06) AS month_ym,
    stf.o01 AS staff_id,
    SUM(p.p05) AS staff_month_amount,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, cnt.c01, strftime('%Y-%m', p.p06)
      ORDER BY SUM(p.p05) DESC
    ) AS rn
  FROM pay p
  JOIN ren r
    ON r.q01 = p.p04
  JOIN cus c
    ON c.h01 = p.p02
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
  JOIN stf
    ON stf.o01 = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    cnt.c01,
    strftime('%Y-%m', p.p06),
    stf.o01
)
SELECT
  s.customer_id AS h01,
  s.country_id,
  s.country_name,
  s.city_name,
  s.month_ym AS month,
  ROUND(s.month_amount, 2) AS month_amount,
  s.month_payments AS month_payments,
  ROUND(s.month_amount - s.personal_avg_month_amount, 2) AS deviation_from_personal_avg,
  s.customer_rank_in_country AS customer_rank_in_country,
  te.staff_id AS top_staff_id,
  stf.f01 AS staff_first_name,
  stf.f02 AS staff_last_name
FROM selected s
JOIN top_employee te
  ON te.customer_id = s.customer_id
 AND te.country_id = s.country_id
 AND te.month_ym = s.month_ym
 AND te.rn = 1
LEFT JOIN stf
  ON stf.o01 = te.staff_id
WHERE s.personal_multiplier > 2
  AND s.month_amount >= (SELECT t2.country_top10_threshold
                          FROM country_p10_threshold t2
                          WHERE t2.country_id = s.country_id
                            AND t2.month_ym = s.month_ym
                          LIMIT 1)
ORDER BY
  s.country_id,
  s.month_ym,
  s.customer_rank_in_country;