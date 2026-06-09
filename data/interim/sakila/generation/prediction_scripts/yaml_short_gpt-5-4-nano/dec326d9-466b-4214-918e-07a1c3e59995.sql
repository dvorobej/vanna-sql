WITH daily_payments AS (
  SELECT
    p.p02 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    co.c02 AS country_name,
    ci.d02 AS city_name,
    date(p.p06) AS payment_day,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT COALESCE(i.n03, s.o07)) AS distinct_store_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
  JOIN stf AS s
    ON s.o01 = p.p03
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
  GROUP BY
    p.p02,
    c.h03,
    c.h04,
    co.c02,
    ci.d02,
    date(p.p06)
),
daily_with_film_counts AS (
  SELECT
    dp.*,
    (
      SELECT COUNT(DISTINCT i2.n02)
      FROM pay AS p2
      LEFT JOIN ren AS r2
        ON r2.q01 = p2.p04
      LEFT JOIN inv AS i2
        ON i2.n01 = r2.q03
      WHERE p2.p02 = dp.customer_id
        AND date(p2.p06) = dp.payment_day
    ) AS distinct_rented_film_count
  FROM daily_payments AS dp
),
scored AS (
  SELECT
    d.*,
    -- avg daily amount in previous 30 days (excluding current day)
    (
      SELECT AVG(CAST(p3.p05 AS REAL))
      FROM pay AS p3
      WHERE p3.p02 = d.customer_id
        AND date(p3.p06) >= date(d.payment_day, '-30 day')
        AND date(p3.p06) < d.payment_day
    ) AS avg_daily_amount_prev_30d,
    -- total in 7-day window ending at current day
    SUM(d2.day_amount) OVER (
      PARTITION BY d.customer_id
      ORDER BY d.payment_day
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS sum_amount_7d,
    COUNT(d2.payment_count) OVER (
      PARTITION BY d.customer_id
      ORDER BY d.payment_day
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS days_in_window
  FROM daily_with_film_counts AS d
  LEFT JOIN daily_with_film_counts AS d2
    ON d2.customer_id = d.customer_id
   AND d2.payment_day BETWEEN date(d.payment_day, '-6 day') AND d.payment_day
)
SELECT
  s.customer_id,
  s.customer_name,
  s.country_name,
  s.city_name,
  s.payment_day,
  ROUND(s.day_amount, 2) AS payment_day_amount,
  s.payment_count,
  s.distinct_staff_count,
  s.distinct_store_count,
  s.distinct_rented_film_count,
  ROUND(s.avg_daily_amount_prev_30d, 2) AS avg_daily_amount_prev_30d,
  ROUND(s.sum_amount_7d, 2) AS sum_amount_7d,
  RANK() OVER (
    PARTITION BY s.country_name, s.city_name
    ORDER BY s.sum_amount_7d DESC, s.day_amount DESC, s.customer_id
  ) AS suspicious_rank_in_city
FROM scored AS s
WHERE s.avg_daily_amount_prev_30d IS NOT NULL
  AND s.avg_daily_amount_prev_30d > 0
  AND s.sum_amount_7d > 3.0 * (s.avg_daily_amount_prev_30d * 7)
ORDER BY
  s.country_name,
  s.city_name,
  suspicious_rank_in_city,
  s.payment_day,
  s.customer_id;