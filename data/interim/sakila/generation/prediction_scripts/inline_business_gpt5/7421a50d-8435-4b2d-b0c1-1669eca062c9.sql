WITH staff_total AS (
  SELECT COUNT(DISTINCT o01) AS total_staff_count
  FROM stf
),
customer_country AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cn.c01 AS country_id,
    cn.c02 AS country_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ct.d03
),
monthly_payments AS (
  SELECT
    p.p02 AS customer_id,
    date(strftime('%Y-%m-01', p.p06)) AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS total_amount,
    AVG(p.p05) AS avg_payment,
    COUNT(DISTINCT p.p03) AS staff_count
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    date(strftime('%Y-%m-01', p.p06))
),
payment_series_24h AS (
  SELECT DISTINCT
    p1.p02 AS customer_id,
    date(strftime('%Y-%m-01', p1.p06)) AS month_start
  FROM pay AS p1
  WHERE p1.p06 >= '2005-01-01'
    AND p1.p06 < '2006-01-01'
    AND (
      SELECT COUNT(*)
      FROM pay AS p2
      WHERE p2.p02 = p1.p02
        AND p2.p06 >= p1.p06
        AND p2.p06 < datetime(p1.p06, '+24 hours')
    ) >= 3
),
scored AS (
  SELECT
    cc.customer_id,
    cc.first_name,
    cc.last_name,
    cc.country_id,
    cc.country_name,
    mp.month_start,
    mp.payment_count,
    mp.total_amount,
    mp.avg_payment,
    mp.staff_count,
    AVG(mp.payment_count * 1.0) OVER (
      PARTITION BY cc.country_id, mp.month_start
    ) AS country_avg_payment_count,
    COUNT(*) OVER (
      PARTITION BY cc.country_id, mp.month_start
    ) AS country_customer_count,
    RANK() OVER (
      PARTITION BY cc.country_id, mp.month_start
      ORDER BY mp.total_amount DESC
    ) AS country_amount_rank,
    ROW_NUMBER() OVER (
      PARTITION BY cc.country_id, mp.month_start
      ORDER BY mp.total_amount DESC, mp.payment_count DESC, cc.customer_id
    ) AS country_amount_rownum
  FROM monthly_payments AS mp
  JOIN customer_country AS cc
    ON cc.customer_id = mp.customer_id
)
SELECT
  s.country_name,
  strftime('%Y-%m', s.month_start) AS payment_month,
  s.customer_id,
  s.first_name,
  s.last_name,
  s.payment_count,
  ROUND(s.total_amount, 2) AS total_amount,
  ROUND(s.avg_payment, 2) AS avg_payment,
  s.staff_count,
  s.country_amount_rank
FROM scored AS s
JOIN payment_series_24h AS ps
  ON ps.customer_id = s.customer_id
 AND ps.month_start = s.month_start
CROSS JOIN staff_total AS st
WHERE s.country_amount_rownum <= CAST((s.country_customer_count + 9) / 10 AS INTEGER)
  AND s.payment_count > s.country_avg_payment_count
  AND s.staff_count = st.total_staff_count
ORDER BY
  s.month_start,
  s.country_name,
  s.country_amount_rank,
  s.total_amount DESC,
  s.customer_id;