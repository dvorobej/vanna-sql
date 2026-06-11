WITH daily_payments AS (
  SELECT
    p.p02 AS customer_id,
    DATE(p.p06) AS payment_day,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(*) AS day_payment_count
  FROM pay AS p
  GROUP BY
    p.p02,
    DATE(p.p06)
),
joined_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    cnt.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = ci.d03
),
daily_with_rolling AS (
  SELECT
    dp.customer_id,
    dp.payment_day,
    dp.day_amount,
    dp.day_payment_count,
    SUM(dp.day_amount) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.payment_day
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS window_amount_7d,
    SUM(dp.day_payment_count) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.payment_day
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS window_payment_count_7d,
    AVG(dp.day_amount) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.payment_day
      ROWS BETWEEN 30 PRECEDING AND 7 PRECEDING
    ) AS hist_avg_day_amount_30d,
    AVG(dp.day_payment_count) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.payment_day
      ROWS BETWEEN 30 PRECEDING AND 7 PRECEDING
    ) AS hist_avg_day_count_30d,
    COUNT(*) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.payment_day
      ROWS BETWEEN 30 PRECEDING AND 7 PRECEDING
    ) AS hist_days_count_30d
  FROM daily_payments AS dp
),
suspicious AS (
  SELECT
    dwr.*,
    ROW_NUMBER() OVER (
      ORDER BY dwr.customer_id
    ) AS dummy
  FROM daily_with_rolling AS dwr
  WHERE dwr.hist_days_count_30d >= 24
    AND dwr.window_payment_count_7d >= 5
    AND dwr.window_amount_7d >= 3.0 * dwr.hist_avg_day_amount_30d
),
window_details AS (
  SELECT
    s.customer_id,
    s.payment_day,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    GROUP_CONCAT(DISTINCT CAST(p.p03 AS TEXT)) AS staff_ids,
    GROUP_CONCAT(DISTINCT CAST(p.p04 AS TEXT)) AS rental_ids,
    COUNT(DISTINCT inv.n03) AS distinct_store_count,
    GROUP_CONCAT(DISTINCT CAST(inv.n03 AS TEXT)) AS store_ids,
    COUNT(DISTINCT i.n02) AS distinct_rented_films_count
  FROM suspicious AS s
  JOIN pay AS p
    ON p.p02 = s.customer_id
   AND DATE(p.p06) BETWEEN DATE(s.payment_day, '-6 days') AND s.payment_day
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS inv
    ON inv.n01 = r.q03
  LEFT JOIN flm AS i
    ON i.i01 = inv.n02
  GROUP BY
    s.customer_id,
    s.payment_day
),
ranked AS (
  SELECT
    s.customer_id,
    s.payment_day,
    s.window_amount_7d,
    s.window_payment_count_7d,
    RANK() OVER (
      ORDER BY s.window_amount_7d DESC
    ) AS suspicious_customer_amount_rank
  FROM suspicious AS s
)
SELECT
  r.suspicious_customer_amount_rank AS customer_rank,
  g.customer_first_name,
  g.customer_last_name,
  g.country_name,
  g.city_name,
  r.payment_day,
  ROUND(r.window_amount_7d, 2) AS window_amount_7d,
  r.window_payment_count_7d AS window_payment_count_7d,
  wd.distinct_staff_count,
  wd.staff_ids,
  wd.distinct_store_count,
  wd.store_ids,
  wd.distinct_rented_films_count
FROM ranked AS r
JOIN joined_geo AS g
  ON g.customer_id = r.customer_id
LEFT JOIN window_details AS wd
  ON wd.customer_id = r.customer_id
 AND wd.payment_day = r.payment_day
ORDER BY
  customer_rank,
  r.payment_day,
  r.customer_id;