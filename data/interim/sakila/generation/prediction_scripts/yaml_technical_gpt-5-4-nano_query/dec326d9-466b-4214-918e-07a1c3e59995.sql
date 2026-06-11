WITH
base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS payment_amount,
    p.p06 AS payment_ts,
    DATE(p.p06) AS payment_day,
    ci.c02 AS country_name,
    ct.d02 AS city_name,
    a.h02 AS home_store_id
  FROM pay p
  JOIN cus c
    ON c.h01 = p.p02
  JOIN adr a1
    ON a1.e01 = c.h06
  JOIN cty ct
    ON ct.d01 = a1.e05
  JOIN cnt ci
    ON ci.c01 = ct.d03
  JOIN (
    SELECT
      c2.h01,
      c2.h02
    FROM cus c2
  ) a
    ON a.h01 = c.h01
),
daily_customer AS (
  SELECT
    b.customer_id,
    b.payment_day,
    b.country_name,
    b.city_name,
    b.home_store_id,
    COUNT(*) AS payment_count,
    SUM(b.payment_amount) AS payment_sum
  FROM base b
  GROUP BY
    b.customer_id,
    b.payment_day,
    b.country_name,
    b.city_name,
    b.home_store_id
),
daily_with_rolling AS (
  SELECT
    dc.*,
    SUM(dc.payment_sum) OVER (
      PARTITION BY dc.customer_id
      ORDER BY dc.payment_day
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS roll_7d_payment_sum,
    SUM(dc.payment_count) OVER (
      PARTITION BY dc.customer_id
      ORDER BY dc.payment_day
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS roll_7d_payment_count,
    AVG(dc.payment_sum) OVER (
      PARTITION BY dc.customer_id
      ORDER BY dc.payment_day
      ROWS BETWEEN 30 PRECEDING AND 7 PRECEDING
    ) AS hist_avg_daily_payment_sum
  FROM daily_customer dc
),
suspect_days AS (
  SELECT
    dwr.*,
    RANK() OVER (
      ORDER BY dwr.roll_7d_payment_sum DESC, dwr.customer_id
    ) AS customer_risk_rank_global
  FROM daily_with_rolling dwr
  WHERE dwr.hist_avg_daily_payment_sum IS NOT NULL
    AND dwr.hist_avg_daily_payment_sum > 0
    AND dwr.roll_7d_payment_sum >= 3.0 * dwr.hist_avg_daily_payment_sum
    AND dwr.roll_7d_payment_count >= 5
),
window_staff_stores AS (
  SELECT
    s.customer_id,
    s.payment_day,
    GROUP_CONCAT(DISTINCT st.o02 || ' ' || st.o03, ', ') AS staff_names,
    GROUP_CONCAT(DISTINCT c2.h02, ', ') AS store_ids
  FROM suspect_days s
  JOIN pay p
    ON p.p02 = s.customer_id
   AND DATE(p.p06) BETWEEN DATE(s.payment_day, '-6 day') AND s.payment_day
  JOIN stf st
    ON st.o01 = p.p03
  JOIN cus c2
    ON c2.h01 = p.p02
  GROUP BY s.customer_id, s.payment_day
),
window_film_count AS (
  SELECT
    s.customer_id,
    s.payment_day,
    COUNT(DISTINCT i.n02) AS distinct_inventory_count,
    COUNT(DISTINCT fc.l02) AS distinct_category_count
  FROM suspect_days s
  LEFT JOIN pay p
    ON p.p02 = s.customer_id
   AND DATE(p.p06) BETWEEN DATE(s.payment_day, '-6 day') AND s.payment_day
  LEFT JOIN ren r
    ON r.q01 = p.p04
  LEFT JOIN inv i
    ON i.n01 = r.q03
  LEFT JOIN flc fcl
    ON fcl.l01 = i.n02
  LEFT JOIN cat fc
    ON fc.g01 = fcl.l02
  GROUP BY s.customer_id, s.payment_day
)
SELECT
  sd.customer_id,
  sd.country_name,
  sd.city_name,
  sd.payment_day AS window_end_day,
  ROUND(sd.roll_7d_payment_sum, 2) AS roll_7d_payment_sum,
  sd.roll_7d_payment_count AS roll_7d_payment_count,
  ROUND(sd.hist_avg_daily_payment_sum, 2) AS hist_avg_daily_payment_sum,
  wss.staff_names,
  wss.store_ids,
  COUNT(DISTINCT p.p01) AS payment_count_confirmed,
  COALESCE(wfc.distinct_inventory_count, 0) AS distinct_rented_films_inventory_count,
  sd.customer_risk_rank_global AS customer_risk_rank
FROM suspect_days sd
LEFT JOIN window_staff_stores wss
  ON wss.customer_id = sd.customer_id
 AND wss.payment_day = sd.payment_day
LEFT JOIN window_film_count wfc
  ON wfc.customer_id = sd.customer_id
 AND wfc.payment_day = sd.payment_day
LEFT JOIN pay p
  ON p.p02 = sd.customer_id
 AND DATE(p.p06) BETWEEN DATE(sd.payment_day, '-6 day') AND sd.payment_day
GROUP BY
  sd.customer_id,
  sd.country_name,
  sd.city_name,
  sd.payment_day,
  sd.roll_7d_payment_sum,
  sd.roll_7d_payment_count,
  sd.hist_avg_daily_payment_sum,
  wss.staff_names,
  wss.store_ids,
  wfc.distinct_inventory_count,
  sd.customer_risk_rank_global
ORDER BY
  sd.customer_risk_rank_global,
  sd.roll_7d_payment_sum DESC,
  sd.customer_id;