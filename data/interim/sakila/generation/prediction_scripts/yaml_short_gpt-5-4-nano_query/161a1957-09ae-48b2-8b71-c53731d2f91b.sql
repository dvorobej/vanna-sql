WITH payment_days AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS daily_sum
  FROM pay AS p
  GROUP BY p.p02, date(p.p06)
),
customer_daily_details AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS daily_sum,
    GROUP_CONCAT(DISTINCT p.p03) AS staff_list,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT st.o07) AS store_count
  FROM pay AS p
  JOIN stf AS st ON st.o01 = p.p03
  GROUP BY p.p02, date(p.p06)
),
calendar_join AS (
  SELECT
    cdd.customer_id,
    cdd.payment_date,
    cdd.payment_count,
    cdd.daily_sum,
    cdd.staff_list,
    cdd.staff_count,
    cdd.store_count,
    (
      SELECT AVG(pd2.daily_sum)
      FROM payment_days AS pd2
      WHERE pd2.customer_id = cdd.customer_id
        AND pd2.payment_date >= date(cdd.payment_date, '-30 days')
        AND pd2.payment_date < cdd.payment_date
    ) AS personal_avg_prev_30d
  FROM customer_daily_details AS cdd
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c02 AS country,
    ci.d02 AS city
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt ON cnt.c01 = ci.d03
),
country_daily_sums AS (
  SELECT
    cg.country,
    cg.customer_id,
    pd.payment_date,
    pd.daily_sum
  FROM payment_days AS pd
  JOIN customer_geo AS cg ON cg.customer_id = pd.customer_id
),
country_p95 AS (
  SELECT country, MIN(daily_sum) AS p95_daily_sum
  FROM (
    SELECT
      country,
      daily_sum,
      ROW_NUMBER() OVER (PARTITION BY country ORDER BY daily_sum) AS rn,
      COUNT(*)    OVER (PARTITION BY country) AS cnt
    FROM country_daily_sums
    -- use only real days with payments
  ) t
  WHERE rn >= CAST((95.0 * cnt + 99) / 100 AS INTEGER)
  GROUP BY country
),
suspicious AS (
  SELECT
    cj.customer_id,
    cg.country,
    cg.city,
    cj.payment_date,
    cj.payment_count,
    cj.daily_sum,
    cj.staff_list,
    (cj.daily_sum - cj.personal_avg_prev_30d) AS deviation_from_personal_avg,
    DENSE_RANK() OVER (
      PARTITION BY cg.country
      ORDER BY (cj.daily_sum - cj.personal_avg_prev_30d) DESC
    ) AS country_spike_rank
  FROM calendar_join AS cj
  JOIN customer_geo AS cg
    ON cg.customer_id = cj.customer_id
  JOIN country_p95 AS cp
    ON cp.country = cg.country
  WHERE cj.payment_count >= 3
    AND cj.personal_avg_prev_30d IS NOT NULL
    AND cj.personal_avg_prev_30d > 0
    AND cj.daily_sum > 2 * cj.personal_avg_prev_30d
    AND cj.daily_sum > cp.p95_daily_sum
    AND (cj.staff_count >= 2 OR cj.store_count >= 2)
)
SELECT
  customer_id,
  country,
  city,
  payment_date AS spike_date,
  payment_count,
  ROUND(daily_sum, 2) AS day_total_amount,
  staff_list,
  ROUND(deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  country_spike_rank
FROM suspicious
ORDER BY
  country,
  country_spike_rank,
  payment_date,
  customer_id;