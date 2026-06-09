SELECT AVG(mp2.payment_sum)
      FROM monthly_payments AS mp2
      WHERE mp2.customer_id = mp.customer_id
        AND mp2.month_start >= date(mp.month_start, '-2 months')
        AND mp2.month_start <  date(mp.month_start, '-0 months')
        AND mp2.month_start < mp.month_start
    ) AS personal_avg_prev2_months_sum,
    (
      SELECT AVG(mp2.payment_count * 1.0)
      FROM monthly_payments AS mp2
      WHERE mp2.customer_id = mp.customer_id
        AND mp2.month_start >= date(mp.month_start, '-2 months')
        AND mp2.month_start <  date(mp.month_start, '-0 months')
        AND mp2.month_start < mp.month_start
    ) AS personal_avg_prev2_months_cnt
  FROM monthly_payments AS mp
),
country_months AS (
  SELECT
    customer_id,
    month_start,
    cg.country_id,
    cg.country,
    payment_sum,
    payment_count,
    off_home_staff_payment_share,
    distinct_staff_count
  FROM customer_prev2 AS cp
  JOIN customer_geo AS cg ON cg.customer_id = cp.customer_id
),
country_p95 AS (
  -- Find countries' 95th percentile by month using rank-th value (nearest rank method)
  SELECT
    cm.country_id,
    cm.month_start,
    MIN(cm.payment_sum) AS country_p95_payment_sum
  FROM (
    SELECT
      cm.*,
      ROW_NUMBER() OVER (
        PARTITION BY cm.country_id, cm.month_start
        ORDER BY cm.payment_sum
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY cm.country_id, cm.month_start
      ) AS cnt
    FROM country_months AS cm
  ) AS cm
  WHERE rn >= ((95.0 * cnt + 99.0) / 100.0)
  GROUP BY cm.country_id, cm.month_start
),
scored AS (
  SELECT
    cp.customer_id,
    cg.country,
    cg.country_id,
    cg.city,
    cp.month_start,
    cp.payment_count,
    cp.payment_sum,
    cp.personal_avg_prev2_months_sum,
    cp.off_home_staff_payment_share,
    cp.distinct_staff_count,
    (cp.payment_sum / NULLIF(cp.personal_avg_prev2_months_sum, 0)) AS personal_ratio,
    cp2.country_p95_payment_sum,
    (cp.payment_sum > cp2.country_p95_payment_sum) AS above_country_p95
  FROM customer_prev2 AS cp
  JOIN customer_geo AS cg ON cg.customer_id = cp.customer_id
  JOIN country_p95 AS cp2
    ON cp2.country_id = cg.country_id
   AND cp2.month_start = cp.month_start
),
suspicious AS (
  SELECT
    s.*,
    RANK() OVER (
      PARTITION BY s.country_id, s.month_start
      ORDER BY s.payment_sum DESC
    ) AS country_month_payment_rank
  FROM scored AS s
  WHERE
    s.personal_avg_prev2_months_sum IS NOT NULL
    AND s.personal_avg_prev2_months_sum > 0
    AND s.payment_sum >= 3.0 * s.personal_avg_prev2_months_sum
    AND s.payment_sum > s.country_p95_payment_sum
)
SELECT
  month_start AS payment_month,
  customer_id,
  country,
  city,
  payment_count,
  ROUND(payment_sum, 2) AS payment_sum,
  ROUND(personal_avg_prev2_months_sum, 2) AS personal_avg_prev2_months_sum,
  ROUND(personal_ratio, 3) AS personal_ratio,
  ROUND(country_p95_payment_sum, 2) AS country_p95_payment_sum,
  ROUND(off_home_staff_payment_share, 4) AS off_home_staff_payment_share,
  distinct_staff_count AS distinct_staff_count,
  country_month_payment_rank
FROM suspicious
ORDER BY
  country,
  payment_month,
  country_month_payment_rank,
  payment_sum DESC,
  customer_id;