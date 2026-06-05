WITH client_months AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cn.c01 AS country_id,
    cn.c02 AS country,
    ct.d02 AS city,
    strftime('%Y-%m', p.p06) AS pay_month,
    SUM(p.p05) AS monthly_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ct.d03
  JOIN stf AS s
    ON s.o01 = p.p03
  WHERE c.h07 IN ('1', 'Y', 'y')
  GROUP BY
    c.h01,
    c.h03,
    c.h04,
    cn.c01,
    cn.c02,
    ct.d02,
    strftime('%Y-%m', p.p06)
),
client_months_with_prev AS (
  SELECT
    cm.*,
    AVG(cm.monthly_amount) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.pay_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_monthly_amount
  FROM client_months AS cm
),
country_month_median_src AS (
  SELECT
    cm.country_id,
    cm.pay_month,
    cm.payment_count,
    ROW_NUMBER() OVER (
      PARTITION BY cm.country_id, cm.pay_month
      ORDER BY cm.payment_count
    ) AS rn,
    COUNT(*) OVER (
      PARTITION BY cm.country_id, cm.pay_month
    ) AS cnt
  FROM client_months AS cm
),
country_month_medians AS (
  SELECT
    country_id,
    pay_month,
    AVG(payment_count * 1.0) AS median_payment_count
  FROM country_month_median_src
  WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
  GROUP BY country_id, pay_month
),
ranked_client_months AS (
  SELECT
    cmp.*,
    RANK() OVER (
      PARTITION BY cmp.country_id, cmp.pay_month
      ORDER BY cmp.monthly_amount DESC
    ) AS country_month_rank
  FROM client_months_with_prev AS cmp
)
SELECT
  r.customer_id,
  r.first_name,
  r.last_name,
  r.country,
  r.city,
  r.pay_month AS month,
  ROUND(r.monthly_amount, 2) AS monthly_payment_sum,
  r.payment_count,
  ROUND(r.monthly_amount - r.prev_avg_monthly_amount, 2) AS deviation_from_previous_average,
  r.staff_count,
  r.store_count,
  r.country_month_rank
FROM ranked_client_months AS r
JOIN country_month_medians AS m
  ON m.country_id = r.country_id
 AND m.pay_month = r.pay_month
WHERE r.pay_month >= '2005-01'
  AND r.pay_month <= '2005-12'
  AND r.prev_avg_monthly_amount IS NOT NULL
  AND r.monthly_amount >= r.prev_avg_monthly_amount * 3
  AND r.payment_count > m.median_payment_count
  AND (r.staff_count > 1 OR r.store_count > 1)
ORDER BY
  r.pay_month,
  r.country,
  r.country_month_rank,
  r.customer_id;