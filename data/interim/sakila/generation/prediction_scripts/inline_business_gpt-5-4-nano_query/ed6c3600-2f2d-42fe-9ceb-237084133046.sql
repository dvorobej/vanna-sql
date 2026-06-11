WITH daily_payments AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    COUNT(p.p01) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS payment_sum
  FROM pay AS p
  GROUP BY
    p.p02,
    date(p.p06)
),
customer_daily_stats AS (
  SELECT
    dp.customer_id,
    dp.day_date,
    dp.payment_sum,
    dp.payment_count,

    AVG(dp.payment_sum) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.day_date
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ) AS mean_payment_sum_30d,

    AVG(dp.payment_count * 1.0) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.day_date
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ) AS mean_payment_count_30d,

    -- population stddev approximation: sqrt(E[x^2] - (E[x])^2)
    (AVG(dp.payment_sum * dp.payment_sum * 1.0) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.day_date
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ) - 
    (AVG(dp.payment_sum * 1.0) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.day_date
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    )) *
    (AVG(dp.payment_sum * 1.0) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.day_date
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ))) AS var_payment_sum_30d,

    (AVG(dp.payment_count * dp.payment_count * 1.0) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.day_date
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ) -
    (AVG(dp.payment_count * 1.0) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.day_date
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    )) *
    (AVG(dp.payment_count * 1.0) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.day_date
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ))) AS var_payment_count_30d,

    COUNT(*) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.day_date
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ) AS history_days_available_30d
  FROM daily_payments AS dp
),
alerts_base AS (
  SELECT
    cs.customer_id,
    cs.day_date,
    cs.payment_sum,
    cs.payment_count,

    cs.mean_payment_sum_30d,
    cs.mean_payment_count_30d,

    CASE
      WHEN cs.var_payment_sum_30d < 0 THEN 0
      ELSE sqrt(cs.var_payment_sum_30d)
    END AS std_payment_sum_30d,

    CASE
      WHEN cs.var_payment_count_30d < 0 THEN 0
      ELSE sqrt(cs.var_payment_count_30d)
    END AS std_payment_count_30d,

    cs.history_days_available_30d,

    CASE
      WHEN cs.mean_payment_sum_30d IS NULL OR cs.std_payment_sum_30d IS NULL THEN 0
      WHEN cs.payment_sum > cs.mean_payment_sum_30d + 3 * cs.std_payment_sum_30d THEN 1
      ELSE 0
    END AS sum_amount_is_anomalous,

    CASE
      WHEN cs.mean_payment_count_30d IS NULL OR cs.std_payment_count_30d IS NULL THEN 0
      WHEN cs.payment_count > cs.mean_payment_count_30d + 3 * cs.std_payment_count_30d THEN 1
      ELSE 0
    END AS count_is_anomalous
  FROM customer_daily_stats AS cs
),
customer_geo AS (
  SELECT
    cus.h01 AS customer_id,
    cnt.c02 AS country_name,
    cty.d02 AS city_name
  FROM cus
  JOIN adr ON adr.e01 = cus.h06
  JOIN cty ON cty.d01 = adr.e05
  JOIN cnt ON cnt.c01 = cty.d03
),
daily_offhome_share AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    SUM(CASE WHEN stf.o07 <> cus.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_home_staff_payment_share
  FROM pay AS p
  JOIN cus ON cus.h01 = p.p02
  JOIN stf ON stf.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
top_staff_daily AS (
  SELECT
    t.customer_id,
    t.day_date,
    t.staff_id,
    t.staff_payment_sum,
    ROW_NUMBER() OVER (
      PARTITION BY t.customer_id, t.day_date
      ORDER BY t.staff_payment_sum DESC, t.staff_payment_count DESC, t.staff_id
    ) AS rn
  FROM (
    SELECT
      p.p02 AS customer_id,
      date(p.p06) AS day_date,
      p.p03 AS staff_id,
      SUM(CAST(p.p05 AS REAL)) AS staff_payment_sum,
      COUNT(*) AS staff_payment_count
    FROM pay AS p
    GROUP BY
      p.p02,
      date(p.p06),
      p.p03
  ) AS t
),
top_staff_daily_pick AS (
  SELECT
    customer_id,
    day_date,
    staff_id
  FROM top_staff_daily
  WHERE rn = 1
),
top_staff_name AS (
  SELECT
    tsp.customer_id,
    tsp.day_date,
    s.o02 || ' ' || s.o03 AS most_frequent_staff_name
  FROM top_staff_daily_pick AS tsp
  JOIN stf AS s ON s.o01 = tsp.staff_id
),
daily_top_category AS (
  SELECT
    x.customer_id,
    x.day_date,
    x.category_name,
    ROW_NUMBER() OVER (
      PARTITION BY x.customer_id, x.day_date
      ORDER BY x.category_payment_amount DESC
    ) AS rn
  FROM (
    SELECT
      p.p02 AS customer_id,
      date(p.p06) AS day_date,
      ca.g02 AS category_name,
      SUM(CAST(p.p05 AS REAL)) AS category_payment_amount
    FROM pay AS p
    JOIN ren r ON r.q01 = p.p04
    JOIN inv i ON i.n01 = r.q03
    JOIN flc fc ON fc.l01 = i.n02
    JOIN cat ca ON ca.g01 = fc.l02
    WHERE p.p04 IS NOT NULL
    GROUP BY
      p.p02,
      date(p.p06),
      ca.g02
  ) AS x
),
daily_top_category_pick AS (
  SELECT
    customer_id,
    day_date,
    category_name AS main_category_rented_films
  FROM daily_top_category
  WHERE rn = 1
),
risk_rank AS (
  SELECT
    ab.customer_id,
    ab.day_date,
    ab.payment_sum,
    ab.payment_count,
    ab.sum_amount_is_anomalous,
    ab.count_is_anomalous,

    (COALESCE(ab.payment_sum,0) / NULLIF(ab.mean_payment_sum_30d,0)) AS sum_ratio_to_mean,
    (COALESCE(ab.payment_count,0) / NULLIF(ab.mean_payment_count_30d,0)) AS count_ratio_to_mean,

    (CASE WHEN ab.sum_amount_is_anomalous=1 THEN 2 ELSE 0 END) +
    (CASE WHEN ab.count_is_anomalous=1 THEN 1 ELSE 0 END) AS risk_points
  FROM alerts_base AS ab
)
SELECT
  rr.day_date AS payment_day,
  rr.customer_id,
  cg.country_name,
  cg.city_name,
  ROUND(rr.payment_sum, 2) AS daily_payment_sum,
  rr.payment_count AS daily_payment_count,

  ROUND((dos.off_home_staff_payment_share * 100.0), 2) AS off_home_staff_payment_share_pct,

  ts.most_frequent_staff_name AS top_staff_by_sum,

  dtc.main_category_rented_films AS main_rented_films_category,

  rr.sum_amount_is_anomalous AS anomalous_sum_flag,
  rr.count_is_anomalous AS anomalous_count_flag,
  rr.risk_points AS risk_score,

  DENSE_RANK() OVER (
    ORDER BY rr.risk_points DESC, rr.payment_sum DESC, rr.customer_id, rr.day_date
  ) AS risk_rank_overall
FROM risk_rank AS rr
JOIN alerts_base AS ab
  ON ab.customer_id = rr.customer_id
 AND ab.day_date = rr.day_date
JOIN customer_geo AS cg
  ON cg.customer_id = rr.customer_id
LEFT JOIN daily_offhome_share AS dos
  ON dos.customer_id = rr.customer_id
 AND dos.day_date = rr.day_date
LEFT JOIN top_staff_name AS ts
  ON ts.customer_id = rr.customer_id
 AND ts.day_date = rr.day_date
LEFT JOIN daily_top_category_pick AS dtc
  ON dtc.customer_id = rr.customer_id
 AND dtc.day_date = rr.day_date
WHERE
  ab.history_days_available_30d >= 30
  AND (ab.sum_amount_is_anomalous = 1 OR ab.count_is_anomalous = 1)
ORDER BY
  rr.risk_score DESC,
  rr.payment_sum DESC,
  rr.customer_id,
  rr.day_date;