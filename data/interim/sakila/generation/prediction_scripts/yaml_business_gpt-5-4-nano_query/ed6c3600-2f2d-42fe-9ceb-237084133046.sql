WITH day_payment AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_day,
    COUNT(p.p01) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS payment_sum
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
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    co.c02 AS country_name,
    ct.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ct.d03
),
day_stats AS (
  SELECT
    dp.*,
    AVG(dp.payment_sum) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.payment_day
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ) AS avg_sum_30d,
    sqrt(
      AVG(dp.payment_sum * dp.payment_sum) OVER (
        PARTITION BY dp.customer_id
        ORDER BY dp.payment_day
        ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
      ) -
      (AVG(dp.payment_sum) OVER (
        PARTITION BY dp.customer_id
        ORDER BY dp.payment_day
        ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
      ) *
       AVG(dp.payment_sum) OVER (
        PARTITION BY dp.customer_id
        ORDER BY dp.payment_day
        ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
      ))
    ) AS std_sum_30d,
    AVG(dp.payment_count * 1.0) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.payment_day
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ) AS avg_cnt_30d,
    sqrt(
      AVG(dp.payment_count * dp.payment_count * 1.0) OVER (
        PARTITION BY dp.customer_id
        ORDER BY dp.payment_day
        ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
      ) -
      (AVG(dp.payment_count * 1.0) OVER (
        PARTITION BY dp.customer_id
        ORDER BY dp.payment_day
        ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
      ) *
       AVG(dp.payment_count * 1.0) OVER (
        PARTITION BY dp.customer_id
        ORDER BY dp.payment_day
        ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
      ))
    ) AS std_cnt_30d,
    COUNT(*) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.payment_day
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ) AS hist_days_cnt
  FROM day_payment AS dp
),
anomalies AS (
  SELECT
    ds.*,
    CASE
      WHEN ds.hist_days_cnt >= 30
       AND ds.std_sum_30d IS NOT NULL
       AND ds.payment_sum > ds.avg_sum_30d + 3 * ds.std_sum_30d
      THEN 1 ELSE 0
    END AS flag_sum_over_3std,
    CASE
      WHEN ds.hist_days_cnt >= 30
       AND ds.payment_count > ds.avg_cnt_30d + 3 * ds.std_cnt_30d
      THEN 1 ELSE 0
    END AS flag_cnt_over_3std,
    CASE
      WHEN ds.hist_days_cnt >= 30
       AND ds.std_sum_30d IS NOT NULL
       AND ds.payment_sum > ds.avg_sum_30d + 3 * ds.std_sum_30d
      THEN 2
      WHEN ds.hist_days_cnt >= 30
       AND ds.payment_count > ds.avg_cnt_30d + 3 * ds.std_cnt_30d
      THEN 1
      ELSE 0
    END AS risk_score
  FROM day_stats AS ds
),
day_staff_store_stats AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_day,
    SUM(
      CASE WHEN st.o07 <> h.home_store_id THEN 1 ELSE 0 END
    ) AS off_home_staff_pay_count,
    COUNT(*) AS total_pay_count
  FROM pay p
  JOIN customer_home_store h ON h.customer_id = p.p02
  JOIN stf st ON st.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
day_top_staff AS (
  SELECT
    x.customer_id,
    x.payment_day,
    x.staff_id,
    x.pay_count,
    ROW_NUMBER() OVER (
      PARTITION BY x.customer_id, x.payment_day
      ORDER BY x.pay_count DESC, x.staff_id
    ) AS rn
  FROM (
    SELECT
      p.p02 AS customer_id,
      date(p.p06) AS payment_day,
      p.p03 AS staff_id,
      COUNT(*) AS pay_count
    FROM pay p
    GROUP BY
      p.p02,
      date(p.p06),
      p.p03
  ) AS x
),
day_top_staff_pick AS (
  SELECT
    customer_id,
    payment_day,
    staff_id
  FROM day_top_staff
  WHERE rn = 1
),
day_top_category AS (
  SELECT
    y.customer_id,
    y.payment_day,
    y.category_name,
    ROW_NUMBER() OVER (
      PARTITION BY y.customer_id, y.payment_day
      ORDER BY y.cat_count DESC, y.category_name
    ) AS rn
  FROM (
    SELECT
      p.p02 AS customer_id,
      date(p.p06) AS payment_day,
      ca.g02 AS category_name,
      COUNT(*) AS cat_count
    FROM pay p
    JOIN ren r ON r.q01 = p.p04
    JOIN inv i ON i.n01 = r.q03
    JOIN flc fc ON fc.l01 = i.n02
    JOIN cat ca ON ca.g01 = fc.l02
    WHERE p.p04 IS NOT NULL
    GROUP BY
      p.p02,
      date(p.p06),
      ca.g02
  ) AS y
),
day_top_category_pick AS (
  SELECT
    customer_id,
    payment_day,
    category_name
  FROM day_top_category
  WHERE rn = 1
),
final_ranked AS (
  SELECT
    a.customer_id,
    a.payment_day,
    a.payment_count,
    ROUND(a.payment_sum, 2) AS payment_sum,
    ROUND(a.avg_sum_30d, 2) AS avg_sum_30d,
    ROUND(a.std_sum_30d, 2) AS std_sum_30d,
    ROUND(a.avg_cnt_30d, 2) AS avg_cnt_30d,
    ROUND(a.std_cnt_30d, 2) AS std_cnt_30d,
    a.flag_sum_over_3std,
    a.flag_cnt_over_3std,
    a.risk_score,
    g.country_name,
    g.city_name,
    ROUND(
      1.0 * ds.off_home_staff_pay_count / NULLIF(ds.total_pay_count, 0),
      4
    ) AS off_home_staff_payment_share,
    ts.o01 AS top_staff_id,
    ts.o02 || ' ' || ts.o03 AS top_staff_name,
    dcp.category_name AS top_rented_category
  FROM anomalies a
  LEFT JOIN day_staff_store_stats ds
    ON ds.customer_id = a.customer_id
   AND ds.payment_day = a.payment_day
  LEFT JOIN customer_geo g
    ON g.customer_id = a.customer_id
  LEFT JOIN day_top_staff_pick tsp
    ON tsp.customer_id = a.customer_id
   AND tsp.payment_day = a.payment_day
  LEFT JOIN stf ts
    ON ts.o01 = tsp.staff_id
  LEFT JOIN day_top_category_pick dcp
    ON dcp.customer_id = a.customer_id
   AND dcp.payment_day = a.payment_day
  WHERE a.hist_days_cnt >= 30
    AND (a.flag_sum_over_3std = 1 OR a.flag_cnt_over_3std = 1)
)
SELECT
  DENSE_RANK() OVER (ORDER BY risk_score DESC, payment_sum DESC) AS risk_rank,
  customer_id,
  payment_day,
  payment_count,
  payment_sum,
  off_home_staff_payment_share,
  country_name,
  city_name,
  top_staff_name,
  top_rented_category,
  flag_sum_over_3std,
  flag_cnt_over_3std,
  risk_score
FROM final_ranked
ORDER BY
  risk_score DESC,
  payment_sum DESC,
  payment_day,
  customer_id;