WITH daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS payment_sum,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) AS off_home_store_payments,
    COUNT(*) * 1.0 AS total_payments_for_day
  FROM pay p
  JOIN cus c
    ON c.h01 = p.p02
  JOIN stf s
    ON s.o01 = p.p03
  WHERE p.p06 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06)
),
hist AS (
  SELECT
    d.customer_id,
    d.day_date,
    d.payment_count,
    d.payment_sum,
    d.off_home_store_payments,
    d.total_payments_for_day,

    -- rolling mean/std over previous 30 days (excluding current day)
    (
      SELECT AVG(d2.payment_sum * 1.0)
      FROM daily d2
      WHERE d2.customer_id = d.customer_id
        AND d2.day_date >= date(d.day_date, '-30 day')
        AND d2.day_date < d.day_date
    ) AS mean_payment_sum_30d,

    (
      SELECT
        CASE
          WHEN COUNT(*) <= 1 THEN NULL
          ELSE
            sqrt(
              AVG( (d2.payment_sum - (AVG(d3.payment_sum * 1.0) OVER ())) * (d2.payment_sum - (AVG(d3.payment_sum * 1.0) OVER ())) ) )
        END
      FROM daily d2
      WHERE d2.customer_id = d.customer_id
        AND d2.day_date >= date(d.day_date, '-30 day')
        AND d2.day_date < d.day_date
    ) AS stddev_payment_sum_30d,

    (
      SELECT AVG(d2.payment_count * 1.0)
      FROM daily d2
      WHERE d2.customer_id = d.customer_id
        AND d2.day_date >= date(d.day_date, '-30 day')
        AND d2.day_date < d.day_date
    ) AS mean_payment_count_30d,

    (
      SELECT
        CASE
          WHEN COUNT(*) <= 1 THEN NULL
          ELSE
            sqrt(
              AVG( (d2.payment_count - (SELECT AVG(d3.payment_count * 1.0)
                                         FROM daily d3
                                         WHERE d3.customer_id = d.customer_id
                                           AND d3.day_date >= date(d.day_date, '-30 day')
                                           AND d3.day_date < d.day_date)) *
                   (d2.payment_count - (SELECT AVG(d3.payment_count * 1.0)
                                         FROM daily d3
                                         WHERE d3.customer_id = d.customer_id
                                           AND d3.day_date >= date(d.day_date, '-30 day')
                                           AND d3.day_date < d.day_date)) )
            )
        END
      FROM daily d2
      WHERE d2.customer_id = d.customer_id
        AND d2.day_date >= date(d.day_date, '-30 day')
        AND d2.day_date < d.day_date
    ) AS stddev_payment_count_30d,

    (
      SELECT COUNT(*)
      FROM daily d2
      WHERE d2.customer_id = d.customer_id
        AND d2.day_date >= date(d.day_date, '-30 day')
        AND d2.day_date < d.day_date
    ) AS history_days_count
  FROM daily d
),
flags AS (
  SELECT
    h.*,
    CASE
      WHEN h.mean_payment_sum_30d IS NULL OR h.stddev_payment_sum_30d IS NULL THEN 0
      WHEN h.payment_sum > h.mean_payment_sum_30d + 3 * h.stddev_payment_sum_30d THEN 1
      ELSE 0
    END AS is_sum_spike,
    CASE
      WHEN h.mean_payment_count_30d IS NULL OR h.stddev_payment_count_30d IS NULL THEN 0
      WHEN h.payment_count > h.mean_payment_count_30d + 3 * h.stddev_payment_count_30d THEN 1
      ELSE 0
    END AS is_count_spike
  FROM hist h
),
country_city AS (
  SELECT
    c.h01 AS customer_id,
    co.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ci ON ci.d01 = a.e05
  JOIN cnt co ON co.c01 = ci.d03
),
top_staff AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    p.p03 AS staff_id,
    SUM(CAST(p.p05 AS REAL)) AS staff_payment_sum,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06)
      ORDER BY SUM(CAST(p.p05 AS REAL)) DESC, p.p03
    ) AS rn
  FROM pay p
  GROUP BY p.p02, date(p.p06), p.p03
),
top_staff_pick AS (
  SELECT customer_id, day_date, staff_id AS most_frequent_staff_id, staff_payment_sum
  FROM top_staff
  WHERE rn = 1
),
top_category AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    ca.g02 AS category_name,
    COUNT(*) AS rent_rows,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06)
      ORDER BY COUNT(*) DESC, ca.g02
    ) AS rn
  FROM pay p
  JOIN ren r ON r.q01 = p.p04
  JOIN inv i ON i.n01 = r.q03
  JOIN flc fc ON fc.l01 = i.n02
  JOIN cat ca ON ca.g01 = fc.l02
  WHERE p.p04 IS NOT NULL
  GROUP BY p.p02, date(p.p06), ca.g02
),
top_category_pick AS (
  SELECT customer_id, day_date, category_name AS main_rented_category
  FROM top_category
  WHERE rn = 1
),
risk_ranked AS (
  SELECT
    f.customer_id,
    f.day_date,
    f.payment_count,
    f.payment_sum,
    f.mean_payment_sum_30d,
    f.stddev_payment_sum_30d,
    f.mean_payment_count_30d,
    f.stddev_payment_count_30d,
    f.is_sum_spike,
    f.is_count_spike,

    (f.off_home_store_payments * 1.0 / NULLIF(f.total_payments_for_day, 0)) AS off_home_store_payments_share,

    cc.country_name,
    cc.city_name,

    tsp.most_frequent_staff_id,
    tsp.staff_payment_sum AS most_frequent_staff_payment_sum,

    tc.main_rented_category,

    (f.is_sum_spike + f.is_count_spike) AS risk_score
  FROM flags f
  JOIN country_city cc ON cc.customer_id = f.customer_id
  LEFT JOIN top_staff_pick tsp
    ON tsp.customer_id = f.customer_id
   AND tsp.day_date = f.day_date
  LEFT JOIN top_category_pick tc
    ON tc.customer_id = f.customer_id
   AND tc.day_date = f.day_date
  WHERE f.history_days_count >= 30
    AND (f.is_sum_spike = 1 OR f.is_count_spike = 1)
)
SELECT
  RANK() OVER (PARTITION BY country_name ORDER BY risk_score DESC, payment_sum DESC, customer_id, day_date) AS risk_rank_within_country,
  r.customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  r.day_date,
  r.country_name,
  r.city_name,
  r.payment_count,
  ROUND(r.payment_sum, 2) AS payment_sum,
  ROUND(r.mean_payment_sum_30d, 2) AS mean_payment_sum_30d,
  ROUND(r.stddev_payment_sum_30d, 2) AS stddev_payment_sum_30d,
  r.is_sum_spike,
  ROUND(r.mean_payment_count_30d, 2) AS mean_payment_count_30d,
  ROUND(r.stddev_payment_count_30d, 2) AS stddev_payment_count_30d,
  r.is_count_spike,
  ROUND(r.off_home_store_payments_share, 4) AS off_home_store_payments_share,
  r.most_frequent_staff_id,
  ROUND(r.most_frequent_staff_payment_sum, 2) AS most_frequent_staff_payment_sum,
  r.main_rented_category,
  r.risk_score
FROM risk_ranked r
JOIN cus c ON c.h01 = r.customer_id
ORDER BY
  r.country_name,
  risk_rank_within_country,
  r.day_date,
  r.payment_sum DESC;