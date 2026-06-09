WITH pay_2000 AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS payment_amount,
    p.p06 AS payment_date,
    date(p.p06, 'start of month') AS month_start
  FROM pay AS p
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS customer_store_id,
    ci.d01 AS city_id,
    co.c01 AS country_id
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
),
monthly_payments AS (
  SELECT
    p.customer_id,
    p.month_start,
    SUM(p.payment_amount) AS monthly_sum,
    COUNT(p.payment_id) AS monthly_count
  FROM pay_2000 AS p
  GROUP BY
    p.customer_id,
    p.month_start
),
monthly_with_rolling AS (
  SELECT
    mp.*,
    AVG(mp.monthly_sum) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS rolling_avg_prev_2
  FROM monthly_payments AS mp
),
country_month_sums AS (
  SELECT
    cg.country_id,
    mp.month_start,
    mp.monthly_sum
  FROM monthly_payments AS mp
  JOIN customer_geo AS cg
    ON cg.customer_id = mp.customer_id
),
country_month_thresholds AS (
  SELECT
    cms.country_id,
    cms.month_start,
    -- псевдо-95% перцентиль через позицию (ближайший порядок statistic)
    -- для SQLite: берём значение на ранге closest_to_0.95
    (
      SELECT cms2.monthly_sum
      FROM country_month_sums AS cms2
      WHERE cms2.country_id = cms.country_id
        AND cms2.month_start = cms.month_start
      ORDER BY cms2.monthly_sum ASC
      LIMIT 1 OFFSET CAST(0.95 * (COUNT(*) OVER (
        PARTITION BY cms.country_id, cms.month_start
      ) - 1) AS INTEGER)
    ) AS p95_monthly_sum
  FROM country_month_sums AS cms
  GROUP BY
    cms.country_id,
    cms.month_start
),
staff_side_month AS (
  SELECT
    p.customer_id,
    p.month_start,
    SUM(CASE WHEN st.o01 <> cg.customer_store_id THEN 1 ELSE 0 END) * 1.0
      / COUNT(p.payment_id) AS off_store_staff_payment_share,
    COUNT(DISTINCT p.staff_id) AS distinct_staff_count,
    SUM(CASE WHEN st.o01 <> cg.customer_store_id THEN p.payment_amount ELSE 0 END) AS off_store_staff_payment_sum
  FROM pay_2000 AS p
  JOIN customer_geo AS cg
    ON cg.customer_id = p.customer_id
  JOIN stf AS st
    ON st.o01 = st.o01
  WHERE 1=1
  GROUP BY
    p.customer_id,
    p.month_start
),
staff_side_month_fixed AS (
  SELECT
    p.customer_id,
    p.month_start,
    SUM(CASE WHEN st.o01 <> cg.customer_store_id THEN 1 ELSE 0 END) * 1.0
      / COUNT(p.payment_id) AS off_store_staff_payment_share,
    COUNT(DISTINCT p.staff_id) AS distinct_staff_count
  FROM pay_2000 AS p
  JOIN customer_geo AS cg
    ON cg.customer_id = p.customer_id
  JOIN stf AS st
    ON st.o01 = p.staff_id
  GROUP BY
    p.customer_id,
    p.month_start
),
ranked_in_country AS (
  SELECT
    mwr.*,
    cg.country_id,
    RANK() OVER (
      PARTITION BY cg.country_id, mwr.month_start
      ORDER BY mwr.monthly_sum DESC
    ) AS customer_country_month_rank
  FROM monthly_with_rolling AS mwr
  JOIN customer_geo AS cg
    ON cg.customer_id = mwr.customer_id
)
SELECT
  r.customer_id AS h01,
  cg.country_id,
  r.month_start AS month,
  ROUND(r.monthly_sum, 2) AS monthly_payment_sum,
  r.monthly_count AS monthly_payment_count,
  ROUND(r.rolling_avg_prev_2, 2) AS personal_rolling_avg_prev_2,
  ROUND(r.monthly_sum - r.rolling_avg_prev_2, 2) AS deviation_from_personal_rolling_avg,
  ROUND(smf.off_store_staff_payment_share, 4) AS off_store_staff_payment_share,
  smf.distinct_staff_count,
  r.customer_country_month_rank
FROM ranked_in_country AS r
JOIN customer_geo AS cg
  ON cg.customer_id = r.customer_id
JOIN country_month_thresholds AS th
  ON th.country_id = cg.country_id
 AND th.month_start = r.month_start
LEFT JOIN staff_side_month_fixed AS smf
  ON smf.customer_id = r.customer_id
 AND smf.month_start = r.month_start
WHERE r.rolling_avg_prev_2 IS NOT NULL
  AND r.monthly_sum >= 3.0 * r.rolling_avg_prev_2
  AND r.monthly_sum > th.p95_monthly_sum
ORDER BY
  r.month_start,
  cg.country_id,
  r.customer_country_month_rank,
  r.customer_id;