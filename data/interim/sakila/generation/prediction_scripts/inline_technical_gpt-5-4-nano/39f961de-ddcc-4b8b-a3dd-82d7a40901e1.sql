WITH daily_payments AS (
  SELECT
    c.h01 AS customer_id,
    a_city.d02 AS city_name,
    co.c02 AS country_name,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_sum,
    MAX(CAST(p.p05 AS REAL)) AS max_payment,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.j01) AS distinct_store_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS a_city
    ON a_city.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = a_city.d03
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN sto AS s
    ON s.j01 = i.n03
  WHERE date(p.p06) IS NOT NULL
  GROUP BY
    c.h01, a_city.d02, co.c02, date(p.p06)
),
daily_with_avg AS (
  SELECT
    dp.*,
    (
      SELECT AVG(dp2.day_sum)
      FROM daily_payments AS dp2
      WHERE dp2.customer_id = dp.customer_id
        AND dp2.payment_date >= date(dp.payment_date, '-30 day')
        AND dp2.payment_date < dp.payment_date
    ) AS avg_prev_30d
  FROM daily_payments AS dp
),
daily_with_rating_share AS (
  SELECT
    dp.customer_id,
    dp.city_name,
    dp.country_name,
    dp.payment_date,
    dp.payment_count,
    dp.day_sum,
    dp.max_payment,
    dp.distinct_staff_count,
    dp.distinct_store_count,
    AVG(CASE
          WHEN i.film_id_rating IN ('R', 'NC-17') THEN 1.0
          ELSE 0.0
        END) AS dummy
  FROM daily_with_avg dp
  LEFT JOIN pay p
    ON p.p02 = dp.customer_id
   AND date(p.p06) = dp.payment_date
  LEFT JOIN ren r
    ON r.q01 = p.p04
  LEFT JOIN inv i
    ON i.n01 = r.q03
  GROUP BY
    dp.customer_id, dp.city_name, dp.country_name, dp.payment_date,
    dp.payment_count, dp.day_sum, dp.max_payment,
    dp.distinct_staff_count, dp.distinct_store_count
),
filtered_days AS (
  SELECT
    dwa.customer_id,
    dwa.city_name,
    dwa.country_name,
    dwa.payment_date,
    dwa.payment_count,
    dwa.day_sum,
    dwa.max_payment,
    1.0 * (dwa.day_sum) / NULLIF(dwa.day_sum, 0) AS dummy2,
    CASE
      WHEN dwa.avg_prev_30d IS NOT NULL AND dwa.avg_prev_30d > 0 THEN (dwa.day_sum / dwa.avg_prev_30d)
      ELSE NULL
    END AS ratio_to_prev,
    (
      SELECT
        1.0 * SUM(CASE WHEN flm.i11 IN ('R', 'NC-17') THEN 1 ELSE 0 END) / COUNT(*)
      FROM pay p
      JOIN ren r ON r.q01 = p.p04
      JOIN inv i ON i.n01 = r.q03
      JOIN flm ON flm.i01 = i.n02
      WHERE p.p02 = dwa.customer_id
        AND date(p.p06) = dwa.payment_date
    ) AS rating_R_NC17_payment_share
  FROM daily_with_avg dwa
  WHERE dwa.payment_count >= 3
    AND dwa.avg_prev_30d IS NOT NULL
    AND dwa.avg_prev_30d > 0
    AND dwa.day_sum >= 3.0 * dwa.avg_prev_30d
    AND (dwa.distinct_staff_count > 1 OR dwa.distinct_store_count > 1)
),
ranked_days AS (
  SELECT
    fd.*,
    RANK() OVER (
      PARTITION BY fd.country_name
      ORDER BY fd.day_sum DESC, fd.customer_id
    ) AS day_rank_in_country
  FROM filtered_days fd
)
SELECT
  customer_id,
  city_name AS d02,
  country_name AS c02,
  payment_date,
  payment_count,
  ROUND(day_sum, 2) AS day_sum,
  ROUND(max_payment, 2) AS max_payment,
  ROUND(rating_R_NC17_payment_share, 4) AS rating_R_NC17_payment_share,
  day_rank_in_country
FROM ranked_days
ORDER BY
  country_name,
  day_rank_in_country,
  day_sum DESC,
  customer_id,
  payment_date;