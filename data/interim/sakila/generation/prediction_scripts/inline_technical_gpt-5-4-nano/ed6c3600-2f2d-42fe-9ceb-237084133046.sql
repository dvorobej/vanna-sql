WITH pay_daily AS (
  SELECT
    c.h01 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(p.p01) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_sum,
    AVG(CAST(p.p05 AS REAL)) AS avg_payment_amount_day,
    c.h02 AS customer_store_id
  FROM cus AS c
  JOIN pay AS p
    ON p.p02 = c.h01
  WHERE c.h07 = 'Y' OR c.h07 = '1'
  GROUP BY
    c.h01,
    date(p.p06),
    c.h02
),
history_stats AS (
  SELECT
    pd.customer_id,
    pd.payment_date,
    pd.payment_count,
    pd.day_sum,
    pd.avg_payment_amount_day,
    pd.customer_store_id,
    (
      SELECT AVG(prev.day_sum)
      FROM pay_daily AS prev
      WHERE prev.customer_id = pd.customer_id
        AND prev.payment_date >= date(pd.payment_date, '-30 days')
        AND prev.payment_date < pd.payment_date
    ) AS avg_day_sum_prev_30,
    (
      SELECT
        CASE
          WHEN COUNT(*) < 2 THEN NULL
          ELSE sqrt(
            AVG(prev.day_sum * prev.day_sum) - AVG(prev.day_sum) * AVG(prev.day_sum)
          )
        END
      FROM pay_daily AS prev
      WHERE prev.customer_id = pd.customer_id
        AND prev.payment_date >= date(pd.payment_date, '-30 days')
        AND prev.payment_date < pd.payment_date
    ) AS std_day_sum_prev_30,
    (
      SELECT AVG(prev.payment_count)
      FROM pay_daily AS prev
      WHERE prev.customer_id = pd.customer_id
        AND prev.payment_date >= date(pd.payment_date, '-30 days')
        AND prev.payment_date < pd.payment_date
    ) AS avg_payment_count_prev_30,
    (
      SELECT
        CASE
          WHEN COUNT(*) < 2 THEN NULL
          ELSE sqrt(
            AVG(prev.payment_count * prev.payment_count) - AVG(prev.payment_count) * AVG(prev.payment_count)
          )
        END
      FROM pay_daily AS prev
      WHERE prev.customer_id = pd.customer_id
        AND prev.payment_date >= date(pd.payment_date, '-30 days')
        AND prev.payment_date < pd.payment_date
    ) AS std_payment_count_prev_30,
    (
      SELECT COUNT(*)
      FROM pay_daily AS prev
      WHERE prev.customer_id = pd.customer_id
        AND prev.payment_date >= date(pd.payment_date, '-30 days')
        AND prev.payment_date < pd.payment_date
    ) AS prev_days_count
  FROM pay_daily AS pd
),
anomaly_flags AS (
  SELECT
    hs.*,
    CASE
      WHEN hs.std_day_sum_prev_30 IS NOT NULL
       AND hs.day_sum > hs.avg_day_sum_prev_30 + 3.0 * hs.std_day_sum_prev_30
      THEN 1 ELSE 0
    END AS sum_anomaly,
    CASE
      WHEN hs.std_payment_count_prev_30 IS NOT NULL
       AND hs.payment_count > hs.avg_payment_count_prev_30 + 3.0 * hs.std_payment_count_prev_30
      THEN 1 ELSE 0
    END AS count_anomaly,
    CASE
      WHEN hs.avg_day_sum_prev_30 IS NULL OR hs.avg_day_sum_prev_30 = 0 THEN NULL
      ELSE (hs.day_sum - hs.avg_day_sum_prev_30) / hs.avg_day_sum_prev_30
    END AS sum_deviation_ratio
  FROM history_stats AS hs
  WHERE hs.prev_days_count >= 30
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c02 AS customer_country,
    cty.d02 AS customer_city,
    c.h02 AS customer_store_id
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS cty
    ON cty.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = cty.d03
),
per_day_staff_store_share AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    SUM(CASE WHEN s.o07 <> c.h02 THEN CAST(p.p05 AS REAL) ELSE 0 END) AS foreign_store_sum,
    SUM(CAST(p.p05 AS REAL)) AS total_sum,
    COUNT(*) AS total_payments,
    SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) AS foreign_payments_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
per_day_top_staff AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    s.o01 AS top_staff_id,
    SUM(CAST(p.p05 AS REAL)) AS top_staff_sum
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06),
    s.o01
),
top_staff_pick AS (
  SELECT
    t.customer_id,
    t.payment_date,
    t.top_staff_id,
    t.top_staff_sum
  FROM (
    SELECT
      pts.*,
      ROW_NUMBER() OVER (
        PARTITION BY pts.customer_id, pts.payment_date
        ORDER BY pts.top_staff_sum DESC, pts.top_staff_id
      ) AS rn
    FROM per_day_top_staff AS pts
  ) AS t
  WHERE t.rn = 1
),
per_day_top_category AS (
  SELECT
    x.customer_id,
    x.payment_date,
    x.category_name
  FROM (
    SELECT
      p.p02 AS customer_id,
      date(p.p06) AS payment_date,
      cat.g02 AS category_name,
      ROW_NUMBER() OVER (
        PARTITION BY p.p02, date(p.p06)
        ORDER BY COUNT(*) DESC, cat.g02
      ) AS rn
    FROM pay AS p
    JOIN ren AS r
      ON r.q01 = p.p04
    JOIN inv AS i
      ON i.n01 = r.q03
    JOIN flm AS f
      ON f.i01 = i.n02
    JOIN flc AS fc
      ON fc.l01 = f.i01
    JOIN cat
      ON cat.g01 = fc.l02
    GROUP BY
      p.p02,
      date(p.p06),
      cat.g02
  ) AS x
  WHERE x.rn = 1
),
per_day_risk AS (
  SELECT
    a.customer_id,
    a.payment_date,
    a.day_sum,
    a.payment_count,
    a.avg_day_sum_prev_30,
    a.std_day_sum_prev_30,
    a.avg_payment_count_prev_30,
    a.std_payment_count_prev_30,
    a.sum_anomaly,
    a.count_anomaly,
    a.sum_deviation_ratio,
    ps.foreign_store_sum,
    ps.total_sum,
    CASE
      WHEN ps.total_sum IS NULL OR ps.total_sum = 0 THEN NULL
      ELSE ps.foreign_store_sum / ps.total_sum
    END AS foreign_store_share_by_sum,
    ps.foreign_payments_count,
    ps.total_payments,
    CASE
      WHEN ps.total_payments IS NULL OR ps.total_payments = 0 THEN NULL
      ELSE 1.0 * ps.foreign_payments_count / ps.total_payments
    END AS foreign_store_share_by_count
  FROM anomaly_flags AS a
  LEFT JOIN per_day_staff_store_share AS ps
    ON ps.customer_id = a.customer_id
   AND ps.payment_date = a.payment_date
),
ranked AS (
  SELECT
    pr.*,
    DENSE_RANK() OVER (
      ORDER BY
        (COALESCE(pr.sum_anomaly, 0) * 2 + COALESCE(pr.count_anomaly, 0)) DESC,
        pr.sum_deviation_ratio DESC,
        pr.day_sum DESC,
        pr.customer_id,
        pr.payment_date
    ) AS risk_rank_global,
    RANK() OVER (
      PARTITION BY pr.customer_id
      ORDER BY
        (COALESCE(pr.sum_anomaly, 0) * 2 + COALESCE(pr.count_anomaly, 0)) DESC,
        pr.sum_deviation_ratio DESC
    ) AS risk_rank_within_customer
  FROM per_day_risk AS pr
)
SELECT
  r.customer_id AS h01_customer_id,
  cg.customer_country,
  cg.customer_city,
  r.payment_date AS p06_day,
  r.payment_count,
  ROUND(r.day_sum, 2) AS day_sum_p05,
  ROUND(r.avg_day_sum_prev_30, 2) AS avg_day_sum_prev_30,
  ROUND(r.std_day_sum_prev_30, 2) AS std_day_sum_prev_30,
  ROUND(r.sum_deviation_ratio, 4) AS deviation_ratio_from_avg,
  r.sum_anomaly,
  r.count_anomaly,
  r.foreign_store_share_by_sum,
  r.foreign_store_share_by_count,
  tsp.top_staff_id,
  st.o02 || ' ' || st.o03 AS top_staff_name,
  tsp.top_staff_sum AS top_staff_sum_p05,
  tcat.category_name AS top_major_category_for_day,
  r.risk_rank_global,
  r.risk_rank_within_customer
FROM ranked AS r
JOIN customer_geo AS cg
  ON cg.customer_id = r.customer_id
LEFT JOIN top_staff_pick AS tsp
  ON tsp.customer_id = r.customer_id
 AND tsp.payment_date = r.payment_date
LEFT JOIN stf AS st
  ON st.o01 = tsp.top_staff_id
LEFT JOIN per_day_top_category AS tcat
  ON tcat.customer_id = r.customer_id
 AND tcat.payment_date = r.payment_date
WHERE (r.sum_anomaly = 1 OR r.count_anomaly = 1)
ORDER BY
  r.risk_rank_global,
  r.payment_date,
  r.customer_id;