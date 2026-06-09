WITH daily_payments AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_day,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_sum_amount
  FROM pay AS p
  GROUP BY
    p.p02,
    date(p.p06)
),
customer_history AS (
  SELECT
    dp.*,
    AVG(dp.payment_count) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.payment_day
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ) AS cnt_mean_30d,
    AVG(dp.day_sum_amount) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.payment_day
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ) AS sum_mean_30d,
    (
      AVG(dp.day_sum_amount * dp.day_sum_amount) OVER (
        PARTITION BY dp.customer_id
        ORDER BY dp.payment_day
        ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
      )
      - AVG(dp.day_sum_amount) OVER (
        PARTITION BY dp.customer_id
        ORDER BY dp.payment_day
        ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
      )
      * AVG(dp.day_sum_amount) OVER (
        PARTITION BY dp.customer_id
        ORDER BY dp.payment_day
        ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
      )
    ) AS sum_var_30d,
    (
      AVG(dp.payment_count * dp.payment_count) OVER (
        PARTITION BY dp.customer_id
        ORDER BY dp.payment_day
        ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
      )
      - AVG(dp.payment_count) OVER (
        PARTITION BY dp.customer_id
        ORDER BY dp.payment_day
        ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
      )
      * AVG(dp.payment_count) OVER (
        PARTITION BY dp.customer_id
        ORDER BY dp.payment_day
        ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
      )
    ) AS cnt_var_30d,
    COUNT(*) OVER (
      PARTITION BY dp.customer_id
      ORDER BY dp.payment_day
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ) AS hist_days_30d
  FROM daily_payments AS dp
),
customer_std AS (
  SELECT
    ch.*,
    CASE
      WHEN ch.sum_var_30d < 0 THEN 0
      ELSE sqrt(ch.sum_var_30d)
    END AS sum_std_30d,
    CASE
      WHEN ch.cnt_var_30d < 0 THEN 0
      ELSE sqrt(ch.cnt_var_30d)
    END AS cnt_std_30d
  FROM customer_history AS ch
),
customer_base AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    co.c02 AS country_name,
    ct.d02 AS city_name,
    c.h02 AS home_store_id
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ct.d03
),
daily_staff_store_share AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_day,
    SUM(CASE WHEN st.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 AS off_home_staff_payments_cnt,
    COUNT(*) AS total_payments_cnt
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  JOIN stf st ON st.o01 = p.p03
  GROUP BY p.p02, date(p.p06)
),
top_staff_per_day AS (
  SELECT
    x.customer_id,
    x.payment_day,
    x.staff_id,
    x.staff_payment_sum,
    ROW_NUMBER() OVER (
      PARTITION BY x.customer_id, x.payment_day
      ORDER BY x.staff_payment_sum DESC, x.staff_id
    ) AS rn
  FROM (
    SELECT
      p.p02 AS customer_id,
      date(p.p06) AS payment_day,
      p.p03 AS staff_id,
      SUM(CAST(p.p05 AS REAL)) AS staff_payment_sum
    FROM pay p
    GROUP BY p.p02, date(p.p06), p.p03
  ) AS x
),
top_staff_join AS (
  SELECT
    ts.customer_id,
    ts.payment_day,
    ts.staff_id,
    st.o02 || ' ' || st.o03 AS staff_name
  FROM top_staff_per_day ts
  JOIN stf st ON st.o01 = ts.staff_id
  WHERE ts.rn = 1
),
daily_top_category AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_day,
    ca.g02 AS category_name,
    SUM(CAST(p.p05 AS REAL)) AS category_payment_sum,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06)
      ORDER BY SUM(CAST(p.p05 AS REAL)) DESC
    ) AS rn
  FROM pay p
  JOIN ren r ON r.q01 = p.p04
  JOIN inv i ON i.n01 = r.q03
  JOIN flc fc ON fc.l01 = i.n02
  JOIN cat ca ON ca.g01 = fc.l02
  GROUP BY p.p02, date(p.p06), ca.g02
)
SELECT
  cs.customer_id,
  cb.customer_name,
  cb.country_name,
  cb.city_name,
  cs.payment_day,
  cs.payment_count,
  ROUND(cs.day_sum_amount, 2) AS day_sum_amount,
  ROUND(cs.sum_mean_30d, 2) AS sum_mean_30d,
  ROUND(cs.sum_std_30d, 2) AS sum_std_30d,
  ROUND(cs.cnt_mean_30d, 2) AS cnt_mean_30d,
  ROUND(cs.cnt_std_30d, 2) AS cnt_std_30d,

  ROUND(
    dfs.off_home_staff_payments_cnt / NULLIF(dfs.total_payments_cnt, 0),
    4
  ) AS share_off_home_staff_payments,

  ts.staff_name AS most_frequent_staff,

  tcat.category_name AS main_rented_category,

  CASE
    WHEN cs.hist_days_30d < 30 OR cs.sum_std_30d IS NULL OR cs.cnt_std_30d IS NULL THEN NULL
    WHEN cs.day_sum_amount > cs.sum_mean_30d + 3 * cs.sum_std_30d
      OR cs.payment_count > cs.cnt_mean_30d + 3 * cs.cnt_std_30d
    THEN 1 ELSE 0
  END AS is_suspicious,

  RANK() OVER (
    PARTITION BY cb.country_name
    ORDER BY
      (
        CASE
          WHEN cs.day_sum_amount > cs.sum_mean_30d + 3 * cs.sum_std_30d THEN
            2.0 * (cs.day_sum_amount - (cs.sum_mean_30d + 3 * cs.sum_std_30d))
          ELSE 0.0
        END
        +
        CASE
          WHEN cs.payment_count > cs.cnt_mean_30d + 3 * cs.cnt_std_30d THEN
            1.0 * (cs.payment_count - (cs.cnt_mean_30d + 3 * cs.cnt_std_30d))
          ELSE 0.0
        END
      ) DESC
  ) AS risk_rank_in_country
FROM customer_std cs
JOIN customer_base cb
  ON cb.customer_id = cs.customer_id
LEFT JOIN daily_staff_store_share dfs
  ON dfs.customer_id = cs.customer_id
 AND dfs.payment_day = cs.payment_day
LEFT JOIN top_staff_join ts
  ON ts.customer_id = cs.customer_id
 AND ts.payment_day = cs.payment_day
LEFT JOIN (
  SELECT customer_id, payment_day, category_name
  FROM daily_top_category
  WHERE rn = 1
) tcat
  ON tcat.customer_id = cs.customer_id
 AND tcat.payment_day = cs.payment_day
WHERE
  cs.hist_days_30d >= 30
  AND (
    cs.day_sum_amount > cs.sum_mean_30d + 3 * cs.sum_std_30d
    OR cs.payment_count > cs.cnt_mean_30d + 3 * cs.cnt_std_30d
  )
ORDER BY
  cb.country_name,
  risk_rank_in_country,
  cs.day_sum_amount DESC,
  cs.payment_count DESC,
  cs.customer_id,
  cs.payment_day;