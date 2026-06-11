WITH base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    cus.h02 AS home_store_id
  FROM pay p
  JOIN cus
    ON cus.h01 = p.p02
),
daily AS (
  SELECT
    b.customer_id,
    b.day_date,
    COUNT(*) AS payment_count,
    SUM(b.payment_amount) AS day_sum,
    COUNT(DISTINCT b.staff_id) AS distinct_staff_count,
    SUM(CASE WHEN b.staff_id IS NOT NULL AND (SELECT home_store_id FROM cus WHERE h01 = b.customer_id) IS NOT NULL
             AND (SELECT home_store_id FROM cus WHERE h01 = b.customer_id) <> (SELECT h02 FROM cus WHERE h01 = b.customer_id)
             THEN 1 ELSE 0 END) AS dummy
  FROM base b
  GROUP BY b.customer_id, b.day_date
),
daily_staff_share AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    COUNT(*) AS payment_count_day,
    SUM(CASE WHEN cus.h02 <> p2home.home_store_id THEN 1 ELSE 0 END) AS off_home_store_count
  FROM pay p
  JOIN cus ON cus.h01 = p.p02
  LEFT JOIN (
    SELECT h01 AS customer_id, h02 AS home_store_id
    FROM cus
  ) p2home ON p2home.customer_id = p.p02
  GROUP BY p.p02, date(p.p06)
),
cust_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    co.c02 AS country_name,
    ct.d02 AS city_name
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt co ON co.c01 = ct.d03
),
daily_staff_top AS (
  SELECT
    x.customer_id,
    x.day_date,
    x.staff_id AS top_staff_id,
    COUNT(*) AS top_staff_payments,
    ROW_NUMBER() OVER (
      PARTITION BY x.customer_id, x.day_date
      ORDER BY COUNT(*) DESC, x.staff_id
    ) AS rn
  FROM (
    SELECT
      p.p02 AS customer_id,
      date(p.p06) AS day_date,
      p.p03 AS staff_id
    FROM pay p
  ) x
  GROUP BY x.customer_id, x.day_date, x.staff_id
),
daily_staff_top_pick AS (
  SELECT customer_id, day_date, top_staff_id, top_staff_payments
  FROM daily_staff_top
  WHERE rn = 1
),
daily_action_category_top AS (
  SELECT
    t.customer_id,
    t.day_date,
    t.category_name AS top_category_name,
    ROW_NUMBER() OVER (
      PARTITION BY t.customer_id, t.day_date
      ORDER BY t.category_payment_count DESC, t.category_name
    ) AS rn
  FROM (
    SELECT
      p.p02 AS customer_id,
      date(p.p06) AS day_date,
      ca.g02 AS category_name,
      COUNT(*) AS category_payment_count
    FROM pay p
    JOIN ren r ON r.q01 = p.p04
    JOIN inv i ON i.n01 = r.q03
    JOIN flc fc ON fc.l01 = i.n02
    JOIN cat ca ON ca.g01 = fc.l02
    WHERE ca.g02 IS NOT NULL
    GROUP BY p.p02, date(p.p06), ca.g02
  ) t
),
daily_action_category_pick AS (
  SELECT
    customer_id,
    day_date,
    top_category_name
  FROM daily_action_category_top
  WHERE rn = 1
),
window_stats AS (
  SELECT
    d.customer_id,
    d.day_date,
    d.payment_count,
    d.day_sum,
    AVG(d2.day_sum) AS hist_avg_sum,
    AVG(d2.payment_count * 1.0) AS hist_avg_count,
    -- population stddev (SQLite): sqrt(avg(x^2) - avg(x)^2)
    sqrt(AVG(d2.day_sum * d2.day_sum) - AVG(d2.day_sum) * AVG(d2.day_sum)) AS hist_std_sum,
    sqrt(AVG(d2.payment_count * d2.payment_count * 1.0) - AVG(d2.payment_count * 1.0) * AVG(d2.payment_count * 1.0)) AS hist_std_count,
    COUNT(d2.day_date) AS hist_days_cnt
  FROM daily d
  LEFT JOIN daily d2
    ON d2.customer_id = d.customer_id
   AND d2.day_date >= date(d.day_date, '-30 days')
   AND d2.day_date < d.day_date
  GROUP BY d.customer_id, d.day_date, d.payment_count, d.day_sum
),
risk_rank AS (
  SELECT
    ws.*,
    CASE
      WHEN ws.hist_std_sum > 0 AND ws.day_sum > ws.hist_avg_sum + 3 * ws.hist_std_sum THEN 1
      ELSE 0
    END AS is_sum_outlier,
    CASE
      WHEN ws.hist_std_count > 0 AND ws.payment_count > ws.hist_avg_count + 3 * ws.hist_std_count THEN 1
      ELSE 0
    END AS is_count_outlier
  FROM window_stats ws
  WHERE ws.hist_days_cnt >= 30
),
joined AS (
  SELECT
    rr.customer_id,
    cg.customer_name,
    cg.country_name,
    cg.city_name,
    rr.day_date,
    rr.payment_count,
    rr.day_sum,
    rr.hist_avg_sum,
    rr.hist_std_sum,
    rr.hist_avg_count,
    rr.hist_std_count,
    (1.0 * dsh.off_home_store_count / NULLIF(dsh.payment_count_day, 0)) AS off_home_store_payment_share,
    st.top_staff_id,
    stp.o02 || ' ' || stp.o03 AS top_staff_name,
    catp.top_category_name
  FROM risk_rank rr
  JOIN cust_geo cg
    ON cg.customer_id = rr.customer_id
  LEFT JOIN daily_staff_share dsh
    ON dsh.customer_id = rr.customer_id
   AND dsh.day_date = rr.day_date
  LEFT JOIN daily_staff_top_pick st
    ON st.customer_id = rr.customer_id
   AND st.day_date = rr.day_date
  LEFT JOIN stf stp
    ON stp.o01 = st.top_staff_id
  LEFT JOIN daily_action_category_pick catp
    ON catp.customer_id = rr.customer_id
   AND catp.day_date = rr.day_date
)
SELECT
  joined.*,
  (joined.is_sum_outlier + joined.is_count_outlier) AS risk_score,
  RANK() OVER (ORDER BY (joined.is_sum_outlier + joined.is_count_outlier) DESC, joined.day_sum DESC) AS risk_rank
FROM (
  SELECT
    r.customer_id,
    cg.customer_name,
    cg.country_name,
    cg.city_name,
    r.day_date,
    r.payment_count,
    r.day_sum,
    r.hist_avg_sum,
    r.hist_std_sum,
    r.hist_avg_count,
    r.hist_std_count,
    (1.0 * dsh.off_home_store_count / NULLIF(dsh.payment_count_day, 0)) AS off_home_store_payment_share,
    st.top_staff_id,
    stp.o02 || ' ' || stp.o03 AS top_staff_name,
    catp.top_category_name,
    r.is_sum_outlier,
    r.is_count_outlier
  FROM risk_rank r
  JOIN cust_geo cg
    ON cg.customer_id = r.customer_id
  LEFT JOIN daily_staff_share dsh
    ON dsh.customer_id = r.customer_id
   AND dsh.day_date = r.day_date
  LEFT JOIN daily_staff_top_pick st
    ON st.customer_id = r.customer_id
   AND st.day_date = r.day_date
  LEFT JOIN stf stp
    ON stp.o01 = st.top_staff_id
  LEFT JOIN daily_action_category_pick catp
    ON catp.customer_id = r.customer_id
   AND catp.day_date = r.day_date
) joined
WHERE joined.is_sum_outlier = 1 OR joined.is_count_outlier = 1
ORDER BY risk_score DESC, day_sum DESC, customer_id, day_date;