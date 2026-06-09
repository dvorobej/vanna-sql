SELECT AVG(dbc2.daily_sum)
      FROM daily_by_customer AS dbc2
      WHERE dbc2.customer_id = dbc.customer_id
        AND dbc2.payment_date >= date(dbc.payment_date, '-30 days')
        AND dbc2.payment_date < dbc.payment_date
    ) AS avg_prev_30d_daily_sum
  FROM daily_by_customer AS dbc
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    ci.d02 AS city,
    cnt.c02 AS country
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt ON cnt.c01 = ci.d03
),
daily_with_staff_store AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT COALESCE(i.n03, -1)) AS distinct_store_count
  FROM pay AS p
  LEFT JOIN ren r ON r.q01 = p.p04
  LEFT JOIN inv i ON i.n01 = r.q03
  GROUP BY p.p02, date(p.p06)
),
daily_r_ratings_share AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    SUM(CASE WHEN ca.r_rating IN ('R','NC-17') THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS r_or_nc17_pay_share
  FROM pay AS p
  LEFT JOIN ren r ON r.q01 = p.p04
  LEFT JOIN inv i ON i.n01 = r.q03
  LEFT JOIN flm f ON f.i01 = i.n02
  LEFT JOIN (
    SELECT i01 AS film_id, i11 AS r_rating FROM flm
  ) ca ON ca.film_id = f.i01
  GROUP BY p.p02, date(p.p06)
),
daily_enriched AS (
  SELECT
    d.*,
    cg.city,
    cg.country,
    ds.distinct_staff_count,
    ds.distinct_store_count,
    rr.r_or_nc17_pay_share,
    (d.daily_sum - d.avg_prev_30d_daily_sum) AS deviation_from_prev_avg
  FROM daily_with_prev_avg AS d
  JOIN customer_geo AS cg ON cg.customer_id = d.customer_id
  JOIN daily_with_staff_store AS ds
    ON ds.customer_id = d.customer_id
   AND ds.payment_date = d.payment_date
  LEFT JOIN daily_r_ratings_share AS rr
    ON rr.customer_id = d.customer_id
   AND rr.payment_date = d.payment_date
)
SELECT
  customer_id,
  city,
  country,
  payment_date,
  payment_count,
  ROUND(daily_sum, 2) AS daily_sum,
  ROUND(max_payment, 2) AS max_payment,
  ROUND(r_or_nc17_pay_share, 4) AS r_or_nc17_rental_pay_share,
  DENSE_RANK() OVER (
    PARTITION BY country
    ORDER BY daily_sum DESC
  ) AS country_day_rank
FROM daily_enriched
WHERE avg_prev_30d_daily_sum IS NOT NULL
  AND avg_prev_30d_daily_sum > 0
  AND daily_sum >= 3 * avg_prev_30d_daily_sum
  AND payment_count >= 3
  AND (distinct_staff_count >= 2 OR distinct_store_count >= 2)
ORDER BY
  country,
  country_day_rank,
  payment_date,
  customer_id;