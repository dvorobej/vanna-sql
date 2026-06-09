WITH pay_day AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(*) AS day_payment_count
  FROM pay AS p
  GROUP BY
    p.p02,
    date(p.p06)
),
customer_stats AS (
  SELECT
    pd.customer_id,
    pd.day_date,
    pd.day_amount,
    pd.day_payment_count,
    AVG(pd_prev.day_amount) AS mean_amount_30d,
    -- population stddev approximation
    sqrt(
      AVG(pd_prev.day_amount * pd_prev.day_amount) - AVG(pd_prev.day_amount) * AVG(pd_prev.day_amount)
    ) AS stddev_amount_30d,
    AVG(pd_prev.day_payment_count) AS mean_count_30d,
    sqrt(
      AVG(pd_prev.day_payment_count * pd_prev.day_payment_count) - AVG(pd_prev.day_payment_count) * AVG(pd_prev.day_payment_count)
    ) AS stddev_count_30d,
    COUNT(*) AS days_prev_30d
  FROM pay_day AS pd
  JOIN pay_day AS pd_prev
    ON pd_prev.customer_id = pd.customer_id
   AND pd_prev.day_date >= date(pd.day_date, '-30 days')
   AND pd_prev.day_date < pd.day_date
  GROUP BY
    pd.customer_id,
    pd.day_date,
    pd.day_amount,
    pd.day_payment_count
),
geo_customer AS (
  SELECT
    c.h01 AS customer_id,
    co.c02 AS country_name,
    ct.d02 AS city_name,
    c.h02 AS home_store_id
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ct.d03
),
day_staff AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    SUM(
      CASE WHEN stf.o07 <> c.h02 THEN 1 ELSE 0 END
    ) AS off_home_staff_count,
    COUNT(*) AS day_payment_count_total,
    stf.o01 AS staff_id
  FROM pay AS p
  JOIN cus AS c ON c.h01 = p.p02
  JOIN stf ON stf.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06),
    stf.o01
),
day_staff_main AS (
  SELECT
    ds.customer_id,
    ds.day_date,
    ds.staff_id,
    ROW_NUMBER() OVER (
      PARTITION BY ds.customer_id, ds.day_date
      ORDER BY COUNT(*) DESC
    ) AS rn_main
  FROM pay AS p
  JOIN stf ON stf.o01 = p.p03
  GROUP BY ds.customer_id, ds.day_date, ds.staff_id
),
day_staff_shares AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    SUM(CASE WHEN stf.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS share_off_home_staff
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  JOIN stf ON stf.o01 = p.p03
  GROUP BY p.p02, date(p.p06)
),
day_category AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    ca.g02 AS category_name,
    COUNT(*) AS category_payment_count
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
),
day_category_main AS (
  SELECT
    dc.customer_id,
    dc.day_date,
    dc.category_name,
    ROW_NUMBER() OVER (
      PARTITION BY dc.customer_id, dc.day_date
      ORDER BY dc.category_payment_count DESC
    ) AS rn_cat
  FROM day_category dc
),
risk_rank AS (
  SELECT
    cs.customer_id,
    cs.day_date,
    cs.day_amount,
    cs.day_payment_count,
    cs.mean_amount_30d,
    cs.stddev_amount_30d,
    cs.mean_count_30d,
    cs.stddev_count_30d,
    geo.country_name,
    geo.city_name,
    ds.share_off_home_staff,
    dsm.staff_id,
    stf2.o02 || ' ' || stf2.o03 AS most_freq_staff_name,
    dcm.category_name AS main_category,
    CASE
      WHEN cs.stddev_amount_30d IS NOT NULL
       AND cs.stddev_amount_30d > 0
       AND cs.day_amount > cs.mean_amount_30d + 3.0 * cs.stddev_amount_30d
      THEN 2 ELSE 0
    END AS amount_anomaly_flag,
    CASE
      WHEN cs.stddev_count_30d IS NOT NULL
       AND cs.stddev_count_30d > 0
       AND cs.day_payment_count > cs.mean_count_30d + 3.0 * cs.stddev_count_30d
      THEN 2 ELSE 0
    END AS count_anomaly_flag
  FROM customer_stats cs
  JOIN geo_customer geo ON geo.customer_id = cs.customer_id
  LEFT JOIN day_staff_shares ds
    ON ds.customer_id = cs.customer_id AND ds.day_date = cs.day_date
  LEFT JOIN (
    SELECT
      p2.p02 AS customer_id,
      date(p2.p06) AS day_date,
      p2.p03 AS staff_id
    FROM pay p2
  ) dummy ON 1=0
  LEFT JOIN (
    SELECT
      p.p02 AS customer_id,
      date(p.p06) AS day_date,
      p.p03 AS staff_id,
      ROW_NUMBER() OVER (
        PARTITION BY p.p02, date(p.p06)
        ORDER BY COUNT(*) DESC
      ) AS rn
    FROM pay p
    GROUP BY p.p02, date(p.p06), p.p03
  ) dsm
    ON dsm.customer_id = cs.customer_id
   AND dsm.day_date = cs.day_date
   AND dsm.rn = 1
  LEFT JOIN stf AS stf2 ON stf2.o01 = dsm.staff_id
  LEFT JOIN day_category_main dcm
    ON dcm.customer_id = cs.customer_id
   AND dcm.day_date = cs.day_date
   AND dcm.rn_cat = 1
  WHERE cs.days_prev_30d >= 10
)
SELECT
  r.customer_id,
  r.day_date,
  ROUND(r.day_amount, 2) AS day_amount,
  r.day_payment_count,
  ROUND(r.mean_amount_30d, 2) AS mean_amount_prev_30d,
  ROUND(r.stddev_amount_30d, 2) AS stddev_amount_prev_30d,
  ROUND(r.mean_count_30d, 2) AS mean_count_prev_30d,
  ROUND(r.stddev_count_30d, 2) AS stddev_count_prev_30d,
  r.country_name,
  r.city_name,
  ROUND(COALESCE(r.share_off_home_staff, 0), 4) AS share_off_home_staff,
  r.most_freq_staff_name,
  COALESCE(r.main_category, '(unknown)') AS main_category,
  (r.amount_anomaly_flag + r.count_anomaly_flag) AS risk_score,
  RANK() OVER (
    PARTITION BY r.day_date
    ORDER BY (r.amount_anomaly_flag + r.count_anomaly_flag) DESC,
             r.day_amount DESC,
             r.day_payment_count DESC
  ) AS risk_rank_within_day
FROM risk_rank r
WHERE
  (r.stddev_amount_30d IS NOT NULL AND r.stddev_amount_30d > 0 AND r.day_amount > r.mean_amount_30d + 3.0 * r.stddev_amount_30d)
  OR
  (r.stddev_count_30d IS NOT NULL AND r.stddev_count_30d > 0 AND r.day_payment_count > r.mean_count_30d + 3.0 * r.stddev_count_30d)
ORDER BY
  r.day_date,
  risk_score DESC,
  r.day_amount DESC,
  r.customer_id;