WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    c.h06 AS address_id,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    ci.d02 AS city_name,
    c.h07 AS active_flag
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ci ON ci.d01 = a.e05
  JOIN cnt ON cnt.c01 = ci.d03
),
pay_daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count,
    GROUP_CONCAT(DISTINCT p.p03) AS staff_ids
  FROM pay p
  JOIN stf s ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_personal_avg AS (
  SELECT
    pd.*,
    (
      SELECT AVG(CAST(p2.p05 AS REAL))
      FROM pay p2
      WHERE p2.p02 = pd.customer_id
        AND date(p2.p06) >= date(pd.payment_date, '-30 days')
        AND date(p2.p06) <  pd.payment_date
    ) AS personal_avg_prev_30d
  FROM pay_daily pd
),
country_daily_values AS (
  SELECT
    cg.country_id,
    pd.payment_date,
    pd.day_amount,
    cg.customer_id
  FROM pay_daily pd
  JOIN customer_geo cg ON cg.customer_id = pd.customer_id
),
country_ranked AS (
  SELECT
    country_id,
    payment_date,
    day_amount,
    customer_id,
    ROW_NUMBER() OVER (
      PARTITION BY country_id, payment_date
      ORDER BY day_amount
    ) AS rn,
    COUNT(*) OVER (
      PARTITION BY country_id, payment_date
    ) AS cnt
  FROM country_daily_values
),
country_p95 AS (
  SELECT
    country_id,
    payment_date,
    MIN(day_amount) AS p95_daily_amount
  FROM country_ranked
  WHERE rn >= CAST((95 * cnt + 99) / 100 AS INTEGER)
  GROUP BY country_id, payment_date
),
candidates AS (
  SELECT
    dwp.customer_id,
    cg.first_name,
    cg.last_name,
    cg.country_name,
    cg.city_name,
    dwp.payment_date,
    dwp.payment_count,
    dwp.day_amount,
    dwp.staff_ids,
    dwp.personal_avg_prev_30d,
    (dwp.day_amount - dwp.personal_avg_prev_30d) AS deviation_from_personal_avg,
    c95.p95_daily_amount
  FROM daily_with_personal_avg dwp
  JOIN customer_geo cg ON cg.customer_id = dwp.customer_id
  JOIN country_p95 c95
    ON c95.country_id = cg.country_id
   AND c95.payment_date = dwp.payment_date
  WHERE dwp.payment_count >= 3
    AND dwp.day_amount > 2.0 * dwp.personal_avg_prev_30d
    AND dwp.personal_avg_prev_30d IS NOT NULL
    AND dwp.personal_avg_prev_30d > 0
    AND dwp.day_amount > c95.p95_daily_amount
    AND (dwp.staff_count >= 2 OR dwp.store_count >= 2)
),
final_ranked AS (
  SELECT
    c.*,
    DENSE_RANK() OVER (
      PARTITION BY c.country_name
      ORDER BY c.deviation_from_personal_avg DESC
    ) AS suspicion_rank_in_country
  FROM candidates c
)
SELECT
  customer_id,
  first_name,
  last_name,
  country_name AS country,
  city_name AS city,
  payment_date AS spike_date,
  payment_count,
  ROUND(day_amount, 2) AS day_amount,
  staff_ids AS staff_ids_list,
  ROUND(deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  suspicion_rank_in_country
FROM final_ranked
ORDER BY
  country,
  suspicion_rank_in_country,
  spike_date,
  customer_id;