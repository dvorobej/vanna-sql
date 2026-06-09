WITH pay_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    CAST(p.p05 AS REAL) AS payment_amount,
    date(p.p06) AS payment_day,
    c.h02 AS home_store_id,
    cnt.c02 AS country_name,
    ci.d02 AS city_name
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ci ON ci.d01 = a.e05
  JOIN cnt ON cnt.c01 = ci.d03
),
daily_agg AS (
  SELECT
    customer_id,
    payment_day,
    home_store_id,
    country_name,
    city_name,
    COUNT(payment_id) AS daily_payment_count,
    SUM(payment_amount) AS daily_payment_sum,
    AVG(payment_amount) AS daily_avg_payment,
    SUM(CASE WHEN staff_id IS NOT NULL AND home_store_id IS NOT NULL AND staff_id <> staff_id THEN 0 ELSE 0 END) AS dummy
  FROM pay_base
  GROUP BY
    customer_id, payment_day, home_store_id, country_name, city_name
),
staff_most_frequent AS (
  SELECT
    pb.customer_id,
    pb.payment_day,
    pb.staff_id,
    COUNT(*) AS staff_payments_count,
    ROW_NUMBER() OVER (
      PARTITION BY pb.customer_id, pb.payment_day
      ORDER BY COUNT(*) DESC, pb.staff_id
    ) AS rn
  FROM pay_base pb
  GROUP BY pb.customer_id, pb.payment_day, pb.staff_id
),
top_category_per_day AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_day,
    ca.g02 AS category_name,
    COUNT(*) AS category_payments_count,
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
daily_with_stats AS (
  SELECT
    da.*,
    AVG(da.daily_payment_sum) OVER (
      PARTITION BY da.customer_id
      ORDER BY da.payment_day
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ) AS hist_avg_sum_30d,
    AVG(da.daily_payment_count * 1.0) OVER (
      PARTITION BY da.customer_id
      ORDER BY da.payment_day
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ) AS hist_avg_count_30d,
    CASE
      WHEN COUNT(da.payment_day) OVER (
        PARTITION BY da.customer_id
        ORDER BY da.payment_day
        ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
      ) < 30 THEN NULL
      ELSE
        sqrt(
          AVG(da.daily_payment_sum * da.daily_payment_sum) OVER (
            PARTITION BY da.customer_id
            ORDER BY da.payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
          )
          -
          AVG(da.daily_payment_sum) OVER (
            PARTITION BY da.customer_id
            ORDER BY da.payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
          ) *
          AVG(da.daily_payment_sum) OVER (
            PARTITION BY da.customer_id
            ORDER BY da.payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
          )
        )
    END AS hist_std_sum_30d
  FROM daily_agg da
),
daily_flags AS (
  SELECT
    dws.*,
    CASE
      WHEN dws.hist_avg_sum_30d IS NULL OR dws.hist_std_sum_30d IS NULL THEN 0
      WHEN dws.daily_payment_sum > dws.hist_avg_sum_30d + 3.0 * dws.hist_std_sum_30d THEN 1
      ELSE 0
    END AS sum_anomaly_flag,
    CASE
      WHEN dws.hist_avg_count_30d IS NULL THEN 0
      WHEN dws.daily_payment_count >= dws.hist_avg_count_30d * 3.0 THEN 1
      ELSE 0
    END AS count_spike_flag
  FROM daily_with_stats dws
),
daily_risk AS (
  SELECT
    df.*,
    -- доля платежей сотрудниками, не из домашнего магазина клиента
    (
      SELECT
        1.0 * SUM(CASE WHEN stf.o07 <> df.home_store_id THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0)
      FROM pay pb
      JOIN stf ON stf.o01 = pb.p03
      WHERE pb.p02 = df.customer_id
        AND date(pb.p06) = df.payment_day
    ) AS off_home_store_staff_share,
    -- наиболее частый сотрудник
    (
      SELECT staff_id
      FROM staff_most_frequent smf
      WHERE smf.customer_id = df.customer_id
        AND smf.payment_day = df.payment_day
        AND smf.rn = 1
      LIMIT 1
    ) AS most_frequent_staff_id,
    (
      SELECT s.o02 || ' ' || s.o03
      FROM stf s
      WHERE s.o01 = (
        SELECT staff_id
        FROM staff_most_frequent smf
        WHERE smf.customer_id = df.customer_id
          AND smf.payment_day = df.payment_day
          AND smf.rn = 1
        LIMIT 1
      )
      LIMIT 1
    ) AS most_frequent_staff_name,
    -- основная категория арендованных фильмов в этот день
    (
      SELECT tcp.category_name
      FROM top_category_per_day tcp
      WHERE tcp.customer_id = df.customer_id
        AND tcp.payment_day = df.payment_day
        AND tcp.rn = 1
      LIMIT 1
    ) AS top_category_name
  FROM daily_flags df
  WHERE df.hist_avg_sum_30d IS NOT NULL
    AND df.hist_std_sum_30d IS NOT NULL
    AND (df.sum_anomaly_flag = 1 OR df.count_spike_flag = 1)
),
ranked AS (
  SELECT
    dr.*,
    (
      dr.sum_anomaly_flag * 2.0 +
      dr.count_spike_flag * 1.5 +
      COALESCE(dr.off_home_store_staff_share, 0) * 1.0
    ) AS risk_score,
    DENSE_RANK() OVER (ORDER BY (
      dr.sum_anomaly_flag * 2.0 +
      dr.count_spike_flag * 1.5 +
      COALESCE(dr.off_home_store_staff_share, 0) * 1.0
    ) DESC) AS risk_rank
  FROM daily_risk dr
)
SELECT
  customer_id,
  payment_day,
  country_name,
  city_name,
  daily_payment_count AS payment_count,
  ROUND(daily_payment_sum, 2) AS payment_sum,
  ROUND(hist_avg_sum_30d, 2) AS hist_avg_sum_30d,
  ROUND(hist_std_sum_30d, 2) AS hist_std_sum_30d,
  sum_anomaly_flag,
  count_spike_flag,
  ROUND(off_home_store_staff_share, 4) AS off_home_store_staff_share,
  most_frequent_staff_id,
  most_frequent_staff_name,
  top_category_name,
  risk_score,
  risk_rank
FROM ranked
ORDER BY risk_rank, payment_day, payment_sum DESC, customer_id;