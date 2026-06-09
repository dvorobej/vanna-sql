WITH monthly AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    s.j01 AS store_store_id,
    ct.d02 AS city,
    cn.c02 AS country,
    strftime('%Y-%m', p.p06) AS month,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS month_amount
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  JOIN sto s ON s.j01 = c.h02
  JOIN adr a_store ON a_store.e01 = s.j03
  JOIN cty ct ON ct.d01 = a_store.e05
  JOIN cnt cn ON cn.c01 = ct.d03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    c.h01, c.h02, ct.d02, cn.c02, strftime('%Y-%m', p.p06)
),
year_avg AS (
  SELECT
    customer_id,
    store_id,
    AVG(month_amount) AS avg_month_amount
  FROM monthly
  GROUP BY customer_id, store_id
),
monthly_rank AS (
  SELECT
    m.*,
    ya.avg_month_amount,
    (m.month_amount - ya.avg_month_amount) / NULLIF(ya.avg_month_amount, 0) AS deviation_ratio,
    RANK() OVER (
      PARTITION BY m.store_id, m.month
      ORDER BY m.month_amount DESC
    ) AS store_month_rank,
    COUNT(*) OVER (
      PARTITION BY m.store_id, m.month
    ) AS store_month_customer_cnt
  FROM monthly m
  JOIN year_avg ya
    ON ya.customer_id = m.customer_id
   AND ya.store_id = m.store_id
)
SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  mr.store_id AS store_id,
  mr.city,
  mr.country,
  mr.month,
  ROUND(mr.month_amount, 2) AS month_amount,
  mr.payment_count,
  ROUND(mr.deviation_ratio * 100.0, 2) AS deviation_percent,
  mr.store_month_rank AS rank_in_store_month,
  MAX(p.p03) FILTER (WHERE p.p06 < (mr.month || '-01') || ' 23:59:59') AS last_staff_id
FROM monthly_rank mr
JOIN cus c ON c.h01 = mr.customer_id
JOIN pay p ON p.p02 = c.h01
WHERE mr.avg_month_amount IS NOT NULL
  AND mr.month_amount > 2.0 * mr.avg_month_amount
  AND mr.store_month_rank <= CEIL(0.05 * mr.store_month_customer_cnt)
GROUP BY
  c.h01, c.h03, c.h04,
  mr.store_id, mr.city, mr.country, mr.month,
  mr.month_amount, mr.payment_count, mr.deviation_ratio, mr.store_month_rank
ORDER BY mr.store_id, mr.month, mr.month_amount DESC;