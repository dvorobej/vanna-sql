WITH customer_home AS (
  SELECT
    c.h01 AS customer_id,
    co.c01 AS country_id,
    co.c02 AS country,
    c.h02 AS home_store_id
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ci ON ci.d01 = a.e05
  JOIN cnt co ON co.c01 = ci.d03
),
monthly_payments AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_ym,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS payment_sum,
    SUM(CASE WHEN st.o07 <> ch.home_store_id THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_home_staff_payment_share,
    COUNT(DISTINCT p.p03) AS distinct_staff_count_offered
  FROM pay p
  JOIN customer_home ch ON ch.customer_id = p.p02
  JOIN stf st ON st.o01 = p.p03
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
prev_two_months AS (
  SELECT
    mp.*,
    (
      SELECT AVG(m2.payment_sum)
      FROM monthly_payments m2
      WHERE m2.customer_id = mp.customer_id
        AND m2.month_ym < mp.month_ym
        AND m2.month_ym >= strftime('%Y-%m', date(mp.month_ym || '-01', '-2 months'))
    ) AS personal_avg_prev2_months_sum
  FROM monthly_payments mp
),
country_month_stats AS (
  SELECT
    ch.country_id,
    mp.month_ym,
    mp.payment_sum,
    ROW_NUMBER() OVER (
      PARTITION BY ch.country_id, mp.month_ym
      ORDER BY mp.payment_sum
    ) AS rn,
    COUNT(*) OVER (
      PARTITION BY ch.country_id, mp.month_ym
    ) AS cnt
  FROM monthly_payments mp
  JOIN customer_home ch ON ch.customer_id = mp.customer_id
),
country_p95 AS (
  SELECT
    country_id,
    month_ym,
    AVG(payment_sum) AS country_p95_payment_sum
  FROM country_month_stats
  WHERE rn >= CAST(0.95 * cnt AS INTEGER)
  GROUP BY country_id, month_ym
),
scored AS (
  SELECT
    ptm.customer_id,
    ptm.month_ym,
    ch.country,
    ch.country_id,
    ptm.payment_count,
    ptm.payment_sum,
    ptm.personal_avg_prev2_months_sum,
    cp.country_p95_payment_sum,
    ptm.off_home_staff_payment_share,
    ptm.distinct_staff_count_offered,
    RANK() OVER (
      PARTITION BY ch.country_id, ptm.month_ym
      ORDER BY ptm.payment_sum DESC
    ) AS country_month_payment_rank
  FROM prev_two_months ptm
  JOIN customer_home ch ON ch.customer_id = ptm.customer_id
  JOIN country_p95 cp
    ON cp.country_id = ch.country_id
   AND cp.month_ym = ptm.month_ym
)
SELECT
  customer_id,
  country,
  month_ym AS month,
  payment_count,
  ROUND(payment_sum, 2) AS payment_sum,
  ROUND(personal_avg_prev2_months_sum, 2) AS personal_avg_prev2_months_sum,
  ROUND(country_p95_payment_sum, 2) AS country_p95_payment_sum,
  ROUND(payment_sum / NULLIF(personal_avg_prev2_months_sum, 0), 2) AS month_sum_vs_personal_avg_ratio,
  ROUND(off_home_staff_payment_share, 4) AS off_home_staff_payment_share,
  distinct_staff_count_offered AS distinct_staff_count,
  country_month_payment_rank
FROM scored
WHERE personal_avg_prev2_months_sum IS NOT NULL
  AND personal_avg_prev2_months_sum > 0
  AND payment_sum >= 3.0 * personal_avg_prev2_months_sum
  AND payment_sum > country_p95_payment_sum
ORDER BY
  country,
  month,
  country_month_payment_rank,
  payment_sum DESC,
  customer_id;