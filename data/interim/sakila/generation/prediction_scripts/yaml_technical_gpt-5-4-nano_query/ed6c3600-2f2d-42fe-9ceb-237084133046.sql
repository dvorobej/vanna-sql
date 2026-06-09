with window aggregates */
    SQRT(
      MAX(0.0,
        AVG(pd.day_sum_amount * pd.day_sum_amount) OVER (
          PARTITION BY pd.customer_id
          ORDER BY pd.day_dt
          ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        )
        - (
          AVG(pd.day_sum_amount) OVER (
            PARTITION BY pd.customer_id
            ORDER BY pd.day_dt
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
          )
          * AVG(pd.day_sum_amount) OVER (
            PARTITION BY pd.customer_id
            ORDER BY pd.day_dt
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
          )
        )
      )
    ) AS stddev_sum_30d,
    COUNT(*) OVER (
      PARTITION BY pd.customer_id
      ORDER BY pd.day_dt
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ) AS hist_days_cnt
  FROM pay_daily AS pd
),
anomaly_days AS (
  SELECT
    ds.*,
    CASE
      WHEN ds.stddev_sum_30d > 0
       AND ds.day_sum_amount > ds.avg_sum_30d + 3.0 * ds.stddev_sum_30d
      THEN 1 ELSE 0
    END AS flag_sum_over_3std,
    CASE
      /* "резко выросло количество операций": > (avg + 3*std) for count as well */
      WHEN ds.avg_count_30d IS NOT NULL
       AND ds.payment_count > ds.avg_count_30d + 3.0 * (
          SQRT(
            MAX(0.0,
              AVG((1.0*ds.payment_count)*(1.0*ds.payment_count)) OVER (
                PARTITION BY ds.customer_id
                ORDER BY ds.day_dt
                ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
              )
              - (
                AVG(1.0*ds.payment_count) OVER (
                  PARTITION BY ds.customer_id
                  ORDER BY ds.day_dt
                  ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
                )
                * AVG(1.0*ds.payment_count) OVER (
                  PARTITION BY ds.customer_id
                  ORDER BY ds.day_dt
                  ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
                )
              )
            )
          )
        )
      THEN 1 ELSE 0
    END AS flag_count_spike
  FROM daily_stats AS ds
  WHERE ds.hist_days_cnt >= 30
),
day_payout_staff_share AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_dt,
    SUM(CASE WHEN c.h02 <> st.o07 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_home_staff_payment_share,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06)
      ORDER BY COUNT(*) DESC, p.p03
    ) AS rn
  FROM pay AS p
  JOIN cus AS c ON c.h01 = p.p02
  JOIN stf AS st ON st.o01 = p.p03
  GROUP BY p.p02, date(p.p06), p.p03
),
top_staff AS (
  SELECT
    x.customer_id,
    x.day_dt,
    x.staff_id
  FROM (
    SELECT
      p.p02 AS customer_id,
      date(p.p06) AS day_dt,
      p.p03 AS staff_id,
      COUNT(*) AS staff_payments,
      ROW_NUMBER() OVER (
        PARTITION BY p.p02, date(p.p06)
        ORDER BY COUNT(*) DESC, p.p03
      ) AS rn
    FROM pay AS p
    WHERE p.p04 IS NOT NULL
    GROUP BY p.p02, date(p.p06), p.p03
  ) x
  WHERE x.rn = 1
),
day_top_category AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_dt,
    ca.g02 AS category_name,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06)
      ORDER BY COUNT(*) DESC, ca.g02
    ) AS rn
  FROM pay AS p
  JOIN ren AS r ON r.q01 = p.p04
  JOIN inv AS i ON i.n01 = r.q03
  JOIN flc AS fc ON fc.l01 = i.n02
  JOIN cat AS ca ON ca.g01 = fc.l02
  WHERE p.p04 IS NOT NULL
  GROUP BY p.p02, date(p.p06), ca.g02
),
day_top_category_pick AS (
  SELECT customer_id, day_dt, category_name
  FROM day_top_category
  WHERE rn = 1
),
risk_rank AS (
  SELECT
    ad.customer_id,
    ad.day_dt,
    ad.day_sum_amount,
    ad.payment_count,
    ad.avg_sum_30d,
    ad.stddev_sum_30d,
    ad.flag_sum_over_3std,
    ad.flag_count_spike,
    (ad.flag_sum_over_3std + ad.flag_count_spike) AS risk_points,
    ROW_NUMBER() OVER (
      ORDER BY (ad.flag_sum_over_3std + ad.flag_count_spike) DESC,
               ad.day_sum_amount DESC,
               ad.payment_count DESC,
               ad.customer_id
    ) AS risk_rank_global,
    RANK() OVER (
      ORDER BY (ad.flag_sum_over_3std + ad.flag_count_spike) DESC,
               ad.day_sum_amount DESC
    ) AS risk_rank_in_tier
  FROM anomaly_days AS ad
  WHERE ad.flag_sum_over_3std = 1 OR ad.flag_count_spike = 1
)
SELECT
  rr.risk_rank_global AS risk_rank,
  rr.customer_id,
  ch.country_name,
  ch.city_name,
  rr.day_dt,
  ad.payment_count,
  ROUND(ad.day_sum_amount, 2) AS day_sum_amount,
  ROUND(ad.avg_sum_30d, 2) AS avg_sum_30d,
  ROUND(ad.stddev_sum_30d, 2) AS stddev_sum_30d,
  rr.flag_sum_over_3std,
  rr.flag_count_spike,
  ROUND((
    SELECT COALESCE(AVG(p2.payment_amount_off_home_share),0.0)
    FROM (
      SELECT
        p.p02 AS customer_id,
        date(p.p06) AS day_dt,
        SUM(CASE WHEN ch.home_store_id <> st.o07 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS payment_amount_off_home_share
      FROM pay AS p
      JOIN stf AS st ON st.o01 = p.p03
      JOIN cus AS c2 ON c2.h01 = p.p02
      WHERE p.p02 = rr.customer_id
        AND date(p.p06) = rr.day_dt
      GROUP BY p.p02, date(p.p06)
    ) p2
  ), 4) AS off_home_staff_payment_share,
  ts.staff_id AS top_staff_id,
  stf.o02 || ' ' || stf.o03 AS top_staff_full_name,
  tcp.category_name AS top_rented_category_today
FROM risk_rank AS rr
JOIN anomaly_days AS ad
  ON ad.customer_id = rr.customer_id AND ad.day_dt = rr.day_dt
JOIN customer_home AS ch
  ON ch.customer_id = rr.customer_id
LEFT JOIN top_staff AS ts
  ON ts.customer_id = rr.customer_id AND ts.day_dt = rr.day_dt
LEFT JOIN stf
  ON stf.o01 = ts.staff_id
LEFT JOIN day_top_category_pick AS tcp
  ON tcp.customer_id = rr.customer_id AND tcp.day_dt = rr.day_dt
ORDER BY
  risk_rank DESC;