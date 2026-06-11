WITH customer_base AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country,
    ci.d02 AS city,
    c.h07 AS active_flag
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS cnt ON cnt.c01 = ci.d03
),
payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    DATE(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS amount,
    DATE(p.p06) AS payment_day,
    p.p03 AS staff_id,
    s.o07 AS store_id
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
),
monthly_customer AS (
  SELECT
    pb.customer_id,
    pb.month_start,
    COUNT(pb.payment_id) AS payment_count,
    SUM(pb.amount) AS total_amount,
    MAX(pb.amount) AS max_payment,
    SUM(pb.amount) AS month_sum_check,
    COUNT(DISTINCT pb.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT pb.store_id) AS distinct_store_count,
    COUNT(DISTINCT pb.payment_day) AS distinct_payment_days
  FROM payment_base AS pb
  GROUP BY
    pb.customer_id,
    pb.month_start
),
monthly_with_history AS (
  SELECT
    mc.*,
    AVG(mc.total_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev_months_avg_amount
  FROM monthly_customer AS mc
),
suspicious_months AS (
  SELECT
    mwh.*
  FROM monthly_with_history AS mwh
  WHERE mwh.prev_months_avg_amount IS NOT NULL
    AND mwh.prev_months_avg_amount > 0
    AND mwh.total_amount >= 3.0 * mwh.prev_months_avg_amount
    AND mwh.payment_count >= 3
    AND (
      mwh.distinct_staff_count >= 2
      OR mwh.distinct_store_count >= 2
    )
)
SELECT
  sm.month_start AS payment_month,
  cb.first_name,
  cb.last_name,
  cb.country,
  cb.city,
  sm.payment_count,
  ROUND(sm.total_amount, 2) AS total_amount,
  ROUND(sm.max_payment, 2) AS max_payment,
  ROUND(sm.max_payment / NULLIF(sm.total_amount, 0), 4) AS max_payment_share,
  sm.distinct_staff_count,
  sm.distinct_store_count,
  RANK() OVER (
    PARTITION BY cb.country, sm.month_start
    ORDER BY sm.total_amount DESC
  ) AS country_month_customer_rank
FROM suspicious_months AS sm
JOIN customer_base AS cb
  ON cb.customer_id = sm.customer_id
WHERE cb.active_flag IN ('1', 'Y')
ORDER BY
  sm.month_start,
  cb.country,
  country_month_customer_rank,
  sm.total_amount DESC;