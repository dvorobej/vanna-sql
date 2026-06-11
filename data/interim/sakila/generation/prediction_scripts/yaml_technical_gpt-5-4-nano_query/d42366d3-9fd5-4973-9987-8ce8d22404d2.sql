WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    co.c02 AS country,
    ci.d02 AS city,
    c.h02 AS home_store_id
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
),
payments_base AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id
  FROM pay AS p
),
monthly_customer AS (
  SELECT
    pb.customer_id,
    cg.country,
    cg.home_store_id,
    pb.month_start,
    COUNT(*) AS payment_count,
    SUM(pb.payment_amount) AS payment_sum,
    COUNT(DISTINCT pb.staff_id) AS distinct_staff_count,
    SUM(CASE WHEN stf.o07 <> cg.home_store_id THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_home_staff_payment_share
  FROM payments_base pb
  JOIN customer_geo cg ON cg.customer_id = pb.customer_id
  JOIN stf ON stf.o01 = pb.staff_id
  GROUP BY
    pb.customer_id,
    cg.country,
    cg.home_store_id,
    pb.month_start
),
monthly_with_history AS (
  SELECT
    mc.*,
    (
      SELECT AVG(mc2.payment_sum)
      FROM monthly_customer mc2
      WHERE mc2.customer_id = mc.customer_id
        AND mc2.month_start >= date(mc.month_start, '-2 months')
        AND mc2.month_start <  date(mc.month_start, '-0 months')
        AND mc2.month_start < mc.month_start
        AND mc2.month_start >= date(mc.month_start, '-2 months')
    ) AS personal_avg_prev_2_months_payment_sum,
    (
      SELECT AVG(mc2.payment_count)
      FROM monthly_customer mc2
      WHERE mc2.customer_id = mc.customer_id
        AND mc2.month_start >= date(mc.month_start, '-2 months')
        AND mc2.month_start <  date(mc.month_start, '-0 months')
        AND mc2.month_start < mc.month_start
        AND mc2.month_start >= date(mc.month_start, '-2 months')
    ) AS personal_avg_prev_2_months_payment_count
  FROM monthly_customer mc
),
country_month_sums AS (
  SELECT
    cg.country,
    mc.month_start,
    mc.payment_sum,
    ROW_NUMBER() OVER (
      PARTITION BY cg.country, mc.month_start
      ORDER BY mc.payment_sum
    ) AS rn,
    COUNT(*) OVER (
      PARTITION BY cg.country, mc.month_start
    ) AS cnt
  FROM monthly_customer mc
  JOIN customer_geo cg ON cg.customer_id = mc.customer_id
),
country_p95 AS (
  SELECT
    country,
    month_start,
    MIN(payment_sum) AS country_p95_payment_sum
  FROM (
    SELECT
      country,
      month_start,
      payment_sum,
      rn,
      cnt
    FROM (
      SELECT
        cg.country,
        cm.month_start,
        cm.payment_sum,
        ROW_NUMBER() OVER (PARTITION BY cg.country, cm.month_start ORDER BY cm.payment_sum) AS rn,
        COUNT(*) OVER (PARTITION BY cg.country, cm.month_start) AS cnt
      FROM monthly_customer cm
      JOIN customer_geo cg ON cg.customer_id = cm.customer_id
    )
  )
  WHERE rn >= CAST((0.95 * cnt) AS INT)
  GROUP BY country, month_start
),
filtered AS (
  SELECT
    mwh.customer_id,
    mwh.country,
    mwh.home_store_id,
    mwh.month_start,
    mwh.payment_count,
    mwh.payment_sum,
    mwh.off_home_staff_payment_share,
    mwh.distinct_staff_count,
    mwh.personal_avg_prev_2_months_payment_sum,
    c15.country_p95_payment_sum,
    (mwh.payment_sum / NULLIF(mwh.personal_avg_prev_2_months_payment_sum, 0)) AS personal_ratio,
    RANK() OVER (
      PARTITION BY mwh.country, mwh.month_start
      ORDER BY mwh.payment_sum DESC
    ) AS country_month_rank
  FROM monthly_with_history mwh
  JOIN country_p95 c15
    ON c15.country = mwh.country
   AND c15.month_start = mwh.month_start
  WHERE mwh.personal_avg_prev_2_months_payment_sum IS NOT NULL
    AND mwh.personal_avg_prev_2_months_payment_sum > 0
    AND mwh.payment_sum >= 3.0 * mwh.personal_avg_prev_2_months_payment_sum
    AND mwh.payment_sum > c15.country_p95_payment_sum
)
SELECT
  customer_id,
  country,
  month_start,
  payment_count,
  ROUND(payment_sum, 2) AS payment_sum,
  ROUND(personal_avg_prev_2_months_payment_sum, 2) AS personal_avg_prev_2_months_payment_sum,
  ROUND(personal_ratio, 2) AS personal_ratio,
  ROUND(off_home_staff_payment_share, 4) AS off_home_staff_payment_share,
  distinct_staff_count,
  country_p95_payment_sum AS country_p95_payment_sum,
  country_month_rank
FROM filtered
ORDER BY
  country,
  month_start,
  country_month_rank,
  payment_sum DESC,
  customer_id;