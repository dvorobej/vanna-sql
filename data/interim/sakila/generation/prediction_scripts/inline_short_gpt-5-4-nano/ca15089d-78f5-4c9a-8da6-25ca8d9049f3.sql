WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    co.c02 AS country_name,
    ct.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ct.d03
),
month_payments AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS total_amount,
    MAX(p.p05) AS max_payment,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count,
    SUM(CASE WHEN p.p04 IS NULL THEN 0 ELSE p.p05 END) AS paid_via_rent_amount
  FROM pay AS p
  LEFT JOIN stf AS s ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
month_with_prev AS (
  SELECT
    mp.*,
    AVG(total_amount) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_monthly_avg
  FROM month_payments AS mp
),
qualified AS (
  SELECT
    mwp.*,
    (mwp.max_payment * 1.0 / mwp.total_amount) AS max_payment_share,
    ROW_NUMBER() OVER (
      PARTITION BY mwp.customer_id
      ORDER BY mwp.month_start
    ) AS month_seq
  FROM month_with_prev AS mwp
)
SELECT
  q.customer_id,
  q.month_start AS payment_month,
  cg.first_name,
  cg.last_name,
  cg.country_name,
  cg.city_name,
  q.payment_count,
  ROUND(q.total_amount, 2) AS total_amount,
  ROUND(q.max_payment, 2) AS max_payment,
  ROUND(q.max_payment_share, 4) AS max_payment_share,
  q.staff_count,
  q.store_count,
  DENSE_RANK() OVER (
    PARTITION BY cg.country_name, q.month_start
    ORDER BY q.total_amount DESC
  ) AS country_month_rank
FROM qualified AS q
JOIN customer_geo AS cg
  ON cg.customer_id = q.customer_id
WHERE q.prev_monthly_avg IS NOT NULL
  AND q.payment_count >= 3
  AND EXISTS (
    SELECT 1
    FROM pay AS p
    WHERE p.p02 = q.customer_id
      AND date(p.p06, 'start of month') = q.month_start
    GROUP BY p.p02, date(p.p06, 'start of month')
    HAVING COUNT(DISTINCT date(p.p06)) >= 3
  )
  AND q.total_amount > 3.0 * q.prev_monthly_avg
ORDER BY
  cg.country_name,
  payment_month,
  country_month_rank,
  q.customer_id;