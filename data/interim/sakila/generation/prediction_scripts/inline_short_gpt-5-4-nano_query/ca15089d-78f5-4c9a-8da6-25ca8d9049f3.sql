WITH
monthly_payments AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    co.c02 AS country,
    ci.d02 AS city,
    strftime('%Y-%m', p.p06) AS payment_month,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS monthly_amount,
    MAX(p.p05) AS max_payment,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count
  FROM pay AS p
  JOIN cus AS c ON c.h01 = p.p02
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
  JOIN stf AS s ON s.o01 = p.p03
  WHERE p.p04 IS NOT NULL
  GROUP BY
    c.h01, c.h03, c.h04, co.c02, ci.d02, strftime('%Y-%m', p.p06)
),
with_history AS (
  SELECT
    mp.*,
    AVG(mp.monthly_amount) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.payment_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_monthly_amount
  FROM monthly_payments AS mp
),
eligible_months AS (
  SELECT
    wh.*
  FROM with_history AS wh
  WHERE wh.prev_avg_monthly_amount IS NOT NULL
    AND wh.prev_avg_monthly_amount > 0
    AND wh.monthly_amount >= wh.prev_avg_monthly_amount * 3
),
month_day_staff_store AS (
  SELECT
    c.h01 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    COUNT(DISTINCT date(p.p06)) AS distinct_days_in_month,
    COUNT(DISTINCT p.p03) AS distinct_staff_in_month,
    COUNT(DISTINCT s.o07) AS distinct_store_in_month
  FROM pay AS p
  JOIN cus AS c ON c.h01 = p.p02
  JOIN stf AS s ON s.o01 = p.p03
  WHERE p.p04 IS NOT NULL
  GROUP BY c.h01, strftime('%Y-%m', p.p06)
)
SELECT
  em.payment_month,
  em.customer_id,
  em.first_name || ' ' || em.last_name AS fio,
  em.country,
  em.city,
  em.payment_count,
  ROUND(em.monthly_amount, 2) AS monthly_amount,
  ROUND(em.max_payment, 2) AS max_payment,
  ROUND(em.max_payment / NULLIF(em.monthly_amount, 0), 4) AS max_payment_share,
  em.distinct_staff_count,
  em.distinct_store_count,
  RANK() OVER (
    PARTITION BY em.country, em.payment_month
    ORDER BY em.monthly_amount DESC
  ) AS country_month_amount_rank
FROM eligible_months AS em
JOIN month_day_staff_store AS md
  ON md.customer_id = em.customer_id
 AND md.payment_month = em.payment_month
WHERE md.distinct_days_in_month >= 3
  AND (md.distinct_staff_in_month >= 2 OR md.distinct_store_in_month >= 2)
ORDER BY
  em.country,
  em.payment_month,
  country_month_amount_rank,
  em.customer_id;