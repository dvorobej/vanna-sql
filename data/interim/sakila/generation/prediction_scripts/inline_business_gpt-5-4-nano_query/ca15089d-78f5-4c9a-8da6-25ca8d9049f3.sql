WITH monthly_payments AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    co.c02 AS country_name,
    ct.d02 AS city_name,
    strftime('%Y-%m', p.p06) AS payment_month,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS monthly_amount,
    MAX(p.p05) AS max_payment,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT st.o07) AS distinct_store_count
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt co ON co.c01 = ct.d03
  JOIN stf st ON st.o01 = p.p03
  WHERE p.p04 IS NULL OR p.p04 IS NOT NULL
  GROUP BY
    c.h01, c.h03, c.h04, co.c02, ct.d02, strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
  SELECT
    mp.*,
    AVG(mp.monthly_amount) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.payment_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_monthly_amount
  FROM monthly_payments mp
),
qualify AS (
  SELECT *
  FROM monthly_with_history
  WHERE prev_avg_monthly_amount IS NOT NULL
    AND monthly_amount >= 3.0 * prev_avg_monthly_amount
),
qualified_with_day_check AS (
  SELECT
    q.*,
    (
      SELECT COUNT(DISTINCT date(p2.p06))
      FROM pay p2
      WHERE p2.p02 = q.customer_id
        AND strftime('%Y-%m', p2.p06) = q.payment_month
    ) AS distinct_payment_days
  FROM qualify q
),
final_cases AS (
  SELECT
    q.*,
    (q.max_payment * 1.0 / NULLIF(q.monthly_amount, 0)) AS max_payment_share
  FROM qualified_with_day_check q
  WHERE q.distinct_payment_days >= 3
    AND q.distinct_staff_count >= 2
    AND q.distinct_store_count >= 1
)
SELECT
  payment_month,
  customer_id,
  first_name || ' ' || last_name AS full_name,
  country_name,
  city_name,
  payment_count,
  ROUND(monthly_amount, 2) AS monthly_amount,
  ROUND(max_payment, 2) AS max_payment,
  ROUND(max_payment_share, 4) AS max_payment_share,
  distinct_staff_count,
  distinct_store_count,
  RANK() OVER (
    PARTITION BY country_name, payment_month
    ORDER BY monthly_amount DESC
  ) AS country_month_amount_rank
FROM final_cases
ORDER BY
  country_name,
  payment_month,
  country_month_amount_rank,
  customer_id;