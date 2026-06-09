WITH pay_daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS daily_sum
  FROM pay AS p
  GROUP BY p.p02, date(p.p06)
),
customer_calendar AS (
  SELECT DISTINCT
    pd.customer_id,
    pd.payment_date
  FROM pay_daily AS pd
),
daily_with_avg AS (
  SELECT
    cc.customer_id,
    cc.payment_date,
    COALESCE(pdd.payment_count, 0) AS payment_count,
    COALESCE(pdd.daily_sum, 0.0) AS daily_sum,
    (
      SELECT AVG(CAST(pdd2.daily_sum AS REAL))
      FROM pay_daily AS pdd2
      WHERE pdd2.customer_id = cc.customer_id
        AND pdd2.payment_date >= date(cc.payment_date, '-30 days')
        AND pdd2.payment_date < cc.payment_date
    ) AS avg_prev_30d
  FROM customer_calendar AS cc
  LEFT JOIN pay_daily AS pdd
    ON pdd.customer_id = cc.customer_id
   AND pdd.payment_date = cc.payment_date
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    co.c02 AS country,
    ci.d02 AS city
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
),
staff_store_daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    GROUP_CONCAT(DISTINCT (s.o02 || ' ' || s.o03)) AS staff_list,
    GROUP_CONCAT(DISTINCT st.j01) AS store_list,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT st.j01) AS store_count
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  JOIN sto AS st ON st.j01 = s.o07
  GROUP BY p.p02, date(p.p06)
),
country_daily_sums AS (
  SELECT
    cg.country,
    pd.payment_date,
    pd.daily_sum
  FROM pay_daily AS pd
  JOIN customer_geo AS cg ON cg.customer_id = pd.customer_id
),
country_p95 AS (
  SELECT
    country,
    MIN(daily_sum) AS p95_daily_sum
  FROM (
    SELECT
      country,
      daily_sum,
      ROW_NUMBER() OVER (PARTITION BY country ORDER BY daily_sum) AS rn,
      COUNT(*) OVER (PARTITION BY country) AS cnt
    FROM country_daily_sums
  ) t
  WHERE rn >= CAST((95 * cnt + 99) / 100 AS INTEGER)
  GROUP BY country
),
candidate_days AS (
  SELECT
    dwa.customer_id,
    cg.country,
    cg.city,
    dwa.payment_date,
    dwa.payment_count,
    dwa.daily_sum,
    dwa.avg_prev_30d,
    (dwa.daily_sum - dwa.avg_prev_30d) AS deviation_from_personal_avg
  FROM daily_with_avg AS dwa
  JOIN customer_geo AS cg ON cg.customer_id = dwa.customer_id
  JOIN country_p95 AS cp ON cp.country = cg.country
  WHERE dwa.payment_count >= 3
    AND dwa.avg_prev_30d IS NOT NULL
    AND dwa.avg_prev_30d > 0
    AND dwa.daily_sum >= 2.0 * dwa.avg_prev_30d
    AND dwa.daily_sum > cp.p95_daily_sum
),
ranked AS (
  SELECT
    cd.*,
    DENSE_RANK() OVER (
      PARTITION BY cd.country
      ORDER BY cd.deviation_from_personal_avg DESC
    ) AS country_suspicion_rank
  FROM candidate_days AS cd
)
SELECT
  r.customer_id,
  r.country,
  r.city,
  r.payment_date,
  r.payment_count,
  ROUND(r.daily_sum, 2) AS daily_sum,
  sd.staff_list AS staff_list,
  ROUND(r.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  r.country_suspicion_rank
FROM ranked AS r
LEFT JOIN staff_store_daily AS sd
  ON sd.customer_id = r.customer_id
 AND sd.payment_date = r.payment_date
WHERE (sd.staff_count >= 2 OR sd.store_count >= 2)
ORDER BY
  r.country,
  r.country_suspicion_rank,
  r.payment_date,
  r.customer_id;