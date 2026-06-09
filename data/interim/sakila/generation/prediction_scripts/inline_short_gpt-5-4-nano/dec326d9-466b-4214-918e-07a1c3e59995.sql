WITH
daily_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_day,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT i.n03) AS distinct_store_count,
    COUNT(DISTINCT i.n02) AS distinct_rented_films_count
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  GROUP BY
    p.p02,
    date(p.p06)
),
window_7d AS (
  SELECT
    d1.customer_id,
    d1.payment_day,
    SUM(d2.day_amount) AS amount_7d,
    SUM(d2.payment_count) AS payment_count_7d,
    MAX(d2.distinct_staff_count) AS staff_count_7d_max,
    MAX(d2.distinct_store_count) AS store_count_7d_max,
    MAX(d2.distinct_rented_films_count) AS rented_films_count_7d_max
  FROM daily_pay AS d1
  JOIN daily_pay AS d2
    ON d2.customer_id = d1.customer_id
   AND d2.payment_day >= date(d1.payment_day, '-6 day')
   AND d2.payment_day <= d1.payment_day
  GROUP BY
    d1.customer_id,
    d1.payment_day
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    co.c01 AS country_id,
    co.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
),
window_30d AS (
  SELECT
    w7.customer_id,
    w7.payment_day,
    AVG(w30.amount_30d) AS avg_amount_30d
  FROM window_7d AS w7
  LEFT JOIN (
    SELECT
      d1.customer_id,
      d1.payment_day,
      SUM(d2.day_amount) AS amount_30d
    FROM daily_pay AS d1
    JOIN daily_pay AS d2
      ON d2.customer_id = d1.customer_id
     AND d2.payment_day >= date(d1.payment_day, '-29 day')
     AND d2.payment_day <= date(d1.payment_day, '-7 day')
    GROUP BY
      d1.customer_id,
      d1.payment_day
  ) AS w30
    ON w30.customer_id = w7.customer_id
   AND w30.payment_day = w7.payment_day
  GROUP BY
    w7.customer_id,
    w7.payment_day
),
scored AS (
  SELECT
    w7.customer_id,
    cg.country_id,
    cg.country_name,
    cg.city_name,
    w7.payment_day,
    w7.amount_7d,
    w7.payment_count_7d,
    w7.staff_count_7d_max,
    w7.store_count_7d_max,
    w7.rented_films_count_7d_max,
    w30.avg_amount_30d,
    CASE
      WHEN w30.avg_amount_30d IS NULL OR w30.avg_amount_30d = 0 THEN NULL
      ELSE w7.amount_7d / w30.avg_amount_30d
    END AS ratio_7d_to_avg_30d
  FROM window_7d AS w7
  JOIN customer_geo AS cg
    ON cg.customer_id = w7.customer_id
  LEFT JOIN window_30d AS w30
    ON w30.customer_id = w7.customer_id
   AND w30.payment_day = w7.payment_day
)
SELECT
  s.customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  s.country_name,
  s.city_name,
  s.payment_day AS window_end_date,
  ROUND(s.amount_7d, 2) AS amount_7d,
  s.payment_count_7d AS payment_count_7d,
  s.staff_count_7d_max AS staff_count_7d_max,
  s.store_count_7d_max AS store_count_7d_max,
  s.rented_films_count_7d_max AS rented_films_count_7d_max,
  ROUND(s.avg_amount_30d, 2) AS avg_amount_30d_prev_window,
  ROUND(s.ratio_7d_to_avg_30d, 3) AS ratio_7d_to_avg_30d,
  RANK() OVER (
    PARTITION BY s.country_id
    ORDER BY s.amount_7d DESC
  ) AS risk_rank_in_country
FROM scored AS s
JOIN cus AS c
  ON c.h01 = s.customer_id
WHERE s.avg_amount_30d IS NOT NULL
  AND s.avg_amount_30d > 0
  AND s.amount_7d > 3 * s.avg_amount_30d
ORDER BY
  s.country_name,
  risk_rank_in_country,
  s.payment_day,
  s.customer_id;