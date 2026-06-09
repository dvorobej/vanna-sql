WITH daily_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_sum
  FROM pay AS p
  GROUP BY
    p.p02,
    date(p.p06)
),
customer_home_store AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS home_store_id
  FROM cus AS c
),
daily_enriched AS (
  SELECT
    dp.customer_id,
    dp.day_date,
    dp.payment_count,
    dp.day_sum,
    chs.home_store_id
  FROM daily_pay AS dp
  JOIN customer_home_store AS chs
    ON chs.customer_id = dp.customer_id
),
daily_stats AS (
  SELECT
    de.*,
    (
      SELECT AVG(dp2.day_sum)
      FROM daily_pay AS dp2
      WHERE dp2.customer_id = de.customer_id
        AND dp2.day_date >= date(de.day_date, '-30 days')
        AND dp2.day_date < de.day_date
    ) AS mean_sum_prev_30d,
    (
      SELECT
        CASE
          WHEN COUNT(*) = 0 THEN NULL
          ELSE
            sqrt(
              AVG(dp2.day_sum * dp2.day_sum) - AVG(dp2.day_sum) * AVG(dp2.day_sum)
            )
        END
      FROM daily_pay AS dp2
      WHERE dp2.customer_id = de.customer_id
        AND dp2.day_date >= date(de.day_date, '-30 days')
        AND dp2.day_date < de.day_date
    ) AS std_sum_prev_30d,
    (
      SELECT AVG(dp2.payment_count * 1.0)
      FROM daily_pay AS dp2
      WHERE dp2.customer_id = de.customer_id
        AND dp2.day_date >= date(de.day_date, '-30 days')
        AND dp2.day_date < de.day_date
    ) AS mean_cnt_prev_30d,
    (
      SELECT
        CASE
          WHEN COUNT(*) = 0 THEN NULL
          ELSE
            sqrt(
              AVG(dp2.payment_count * 1.0 * dp2.payment_count * 1.0) - AVG(dp2.payment_count * 1.0) * AVG(dp2.payment_count * 1.0)
            )
        END
      FROM daily_pay AS dp2
      WHERE dp2.customer_id = de.customer_id
        AND dp2.day_date >= date(de.day_date, '-30 days')
        AND dp2.day_date < de.day_date
    ) AS std_cnt_prev_30d,
    (
      SELECT COUNT(*) 
      FROM daily_pay AS dp2
      WHERE dp2.customer_id = de.customer_id
        AND dp2.day_date >= date(de.day_date, '-30 days')
        AND dp2.day_date < de.day_date
    ) AS prev_days_count
  FROM daily_enriched AS de
),
daily_flags AS (
  SELECT
    ds.*,
    CASE
      WHEN ds.mean_sum_prev_30d IS NULL OR ds.std_sum_prev_30d IS NULL OR ds.std_sum_prev_30d = 0
        THEN 0
      WHEN ds.day_sum > ds.mean_sum_prev_30d + 3 * ds.std_sum_prev_30d
        THEN 1
      ELSE 0
    END AS flag_sum_gt_3std,
    CASE
      WHEN ds.mean_cnt_prev_30d IS NULL OR ds.std_cnt_prev_30d IS NULL OR ds.std_cnt_prev_30d = 0
        THEN 0
      WHEN ds.day_sum > 0
           AND ds.payment_count > ds.mean_cnt_prev_30d + 3 * ds.std_cnt_prev_30d
        THEN 1
      ELSE 0
    END AS flag_cnt_gt_3std
  FROM daily_stats AS ds
  WHERE ds.prev_days_count >= 30
),
daily_staff_home_share AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    SUM(CASE WHEN st.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(*), 0) AS share_off_home_staff_payments
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN stf AS st
    ON st.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_top_staff AS (
  SELECT
    customer_id,
    day_date,
    staff_id
  FROM (
    SELECT
      p.p02 AS customer_id,
      date(p.p06) AS day_date,
      p.p03 AS staff_id,
      SUM(CAST(p.p05 AS REAL)) AS staff_day_sum,
      ROW_NUMBER() OVER (
        PARTITION BY p.p02, date(p.p06)
        ORDER BY SUM(CAST(p.p05 AS REAL)) DESC, COUNT(*) DESC, p.p03
      ) AS rn
    FROM pay AS p
    GROUP BY
      p.p02,
      date(p.p06),
      p.p03
  )
  WHERE rn = 1
),
daily_top_category AS (
  SELECT
    x.customer_id,
    x.day_date,
    x.category_name
  FROM (
    SELECT
      p.p02 AS customer_id,
      date(p.p06) AS day_date,
      ca.g02 AS category_name,
      SUM(CAST(p.p05 AS REAL)) AS cat_day_amount,
      ROW_NUMBER() OVER (
        PARTITION BY p.p02, date(p.p06)
        ORDER BY SUM(CAST(p.p05 AS REAL)) DESC, COUNT(*) DESC, ca.g02
      ) AS rn
    FROM pay AS p
    JOIN ren r
      ON r.q01 = p.p04
    JOIN inv i
      ON i.n01 = r.q03
    JOIN flc fc
      ON fc.l01 = i.n02
    JOIN cat ca
      ON ca.g01 = fc.l02
    GROUP BY
      p.p02,
      date(p.p06),
      ca.g02
  ) AS x
  WHERE x.rn = 1
),
daily_risk AS (
  SELECT
    df.customer_id,
    df.day_date,
    df.payment_count,
    df.day_sum,
    df.flag_sum_gt_3std,
    df.flag_cnt_gt_3std,
    (df.flag_sum_gt_3std + df.flag_cnt_gt_3std) AS risk_score
  FROM daily_flags AS df
)
SELECT
  dr.day_date,
  dr.customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  cnt.c02 AS country,
  ct.d02 AS city,
  dr.payment_count,
  ROUND(dr.day_sum, 2) AS day_payment_sum,
  ROUND(ds.mean_sum_prev_30d, 2) AS mean_sum_prev_30d,
  ROUND(ds.std_sum_prev_30d, 2) AS std_sum_prev_30d,
  ROUND(ds.mean_cnt_prev_30d, 2) AS mean_cnt_prev_30d,
  ROUND(ds.std_cnt_prev_30d, 2) AS std_cnt_prev_30d,
  CASE
    WHEN dr.flag_sum_gt_3std = 1 OR dr.flag_cnt_gt_3std = 1
      THEN 1
    ELSE 0
  END AS is_suspicious,
  ROUND(COALESCE(sh.share_off_home_staff_payments, 0.0), 4) AS share_off_home_staff_payments,
  st_top.o02 || ' ' || st_top.o03 AS top_staff_name,
  tc.category_name AS main_rented_category,
  dr.risk_score AS risk_level,
  RANK() OVER (
    PARTITION BY cnt.c01, dr.day_date
    ORDER BY dr.risk_score DESC, dr.day_sum DESC, dr.payment_count DESC, dr.customer_id
  ) AS risk_rank_in_country_for_day
FROM daily_risk AS dr
JOIN daily_stats AS ds
  ON ds.customer_id = dr.customer_id
 AND ds.day_date = dr.day_date
JOIN cus AS c
  ON c.h01 = dr.customer_id
JOIN adr AS a
  ON a.e01 = c.h06
JOIN cty AS ct
  ON ct.d01 = a.e05
JOIN cnt
  ON cnt.c01 = ct.d03
LEFT JOIN daily_staff_home_share AS sh
  ON sh.customer_id = dr.customer_id
 AND sh.day_date = dr.day_date
LEFT JOIN daily_top_staff AS ts
  ON ts.customer_id = dr.customer_id
 AND ts.day_date = dr.day_date
LEFT JOIN stf AS st_top
  ON st_top.o01 = ts.staff_id
LEFT JOIN daily_top_category AS tc
  ON tc.customer_id = dr.customer_id
 AND tc.day_date = dr.day_date
WHERE dr.flag_sum_gt_3std = 1 OR dr.flag_cnt_gt_3std = 1
ORDER BY
  cnt.c02,
  dr.day_date,
  risk_level DESC,
  dr.day_sum DESC,
  dr.payment_count DESC,
  dr.customer_id;