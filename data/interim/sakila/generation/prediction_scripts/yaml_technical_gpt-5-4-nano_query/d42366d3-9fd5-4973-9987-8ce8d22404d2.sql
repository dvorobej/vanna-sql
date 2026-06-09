SELECT AVG(mc2.payment_sum)
      FROM monthly_customer mc2
      WHERE mc2.customer_id = mc.customer_id
        AND mc2.month_start >= date(mc.month_start, '-2 months')
        AND mc2.month_start <  date(mc.month_start, '-0 months')
    ) AS personal_prev2_avg_payment_sum,
    (
      SELECT COUNT(*)
      FROM monthly_customer mc2
      WHERE mc2.customer_id = mc.customer_id
        AND mc2.month_start >= date(mc.month_start, '-2 months')
        AND mc2.month_start <  date(mc.month_start, '-0 months')
    ) AS personal_prev2_months_count
  FROM monthly_customer mc
),
country_months AS (
  SELECT
    cg.country,
    mc.month_start,
    mc.payment_sum,
    mc.customer_id
  FROM monthly_customer mc
  JOIN customer_geo cg ON cg.customer_id = mc.customer_id
),
country_p95 AS (
  -- Approximation of 95th percentile using the 95th rank in the sorted list
  SELECT
    cm.country,
    cm.month_start,
    MAX(cm2.payment_sum) AS country_p95_payment_sum
  FROM country_months cm
  JOIN (
    SELECT
      country,
      month_start,
      customer_id,
      payment_sum,
      ROW_NUMBER() OVER (
        PARTITION BY country, month_start
        ORDER BY payment_sum
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY country, month_start
      ) AS cnt
    FROM country_months
  ) cm2
    ON cm2.country = cm.country
   AND cm2.month_start = cm.month_start
   AND cm2.rn >= CAST((0.95 * cm2.cnt) + 0.999999 AS INTEGER)
  GROUP BY cm.country, cm.month_start
),
country_rank_for_month AS (
  SELECT
    cg.country,
    mc.month_start,
    mc.customer_id,
    DENSE_RANK() OVER (
      PARTITION BY cg.country, mc.month_start
      ORDER BY mc.payment_sum DESC
    ) AS country_month_payment_rank
  FROM monthly_customer mc
  JOIN customer_geo cg ON cg.customer_id = mc.customer_id
),
suspicious AS (
  SELECT
    mh.customer_id,
    cg.country,
    cg.city,
    mh.month_start,
    mh.payment_count,
    mh.payment_sum,
    mh.off_home_staff_share,
    mh.distinct_staff_count,
    mh.personal_prev2_avg_payment_sum,
    cp95.country_p95_payment_sum,
    (mh.payment_sum / NULLIF(mh.personal_prev2_avg_payment_sum, 0)) AS personal_multiplier,
    (mh.payment_sum > cp95.country_p95_payment_sum) AS above_country_p95
  FROM monthly_history mh
  JOIN customer_geo cg ON cg.customer_id = mh.customer_id
  JOIN country_p95 cp95
    ON cp95.country = cg.country
   AND cp95.month_start = mh.month_start
  WHERE mh.personal_prev2_months_count = 2
    AND mh.personal_prev2_avg_payment_sum > 0
    AND mh.payment_sum >= 3.0 * mh.personal_prev2_avg_payment_sum
    AND mh.payment_sum > cp95.country_p95_payment_sum
)
SELECT
  s.month_start AS payment_month,
  s.customer_id,
  s.country,
  s.city,
  s.payment_sum,
  s.payment_count,
  s.personal_prev2_avg_payment_sum AS personal_prev2_avg_monthly_sum,
  ROUND(s.personal_multiplier, 3) AS personal_multiplier_over_avg,
  s.country_p95_payment_sum AS country_p95_payment_sum,
  s.off_home_staff_share,
  s.distinct_staff_count AS distinct_staff_count,
  cr.country_month_payment_rank AS country_month_payment_rank
FROM suspicious s
JOIN country_rank_for_month cr
  ON cr.customer_id = s.customer_id
 AND cr.country = s.country
 AND cr.month_start = s.month_start
ORDER BY
  s.country,
  cr.country_month_payment_rank,
  s.payment_sum DESC,
  s.customer_id;