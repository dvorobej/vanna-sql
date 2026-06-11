WITH payments_2005 AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    p.p05 AS amount,
    date(p.p06, 'start of month') AS month_start
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
customer_store_country_city AS (
  SELECT
    c.h01 AS customer_id,
    s.j01 AS store_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    a.e01 AS address_id,
    ct.d01 AS city_id,
    ct.d02 AS city_name,
    cn.c01 AS country_id,
    cn.c02 AS country_name
  FROM cus AS c
  JOIN sto AS s
    ON s.j01 = c.h02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ct.d03
),
monthly_customer_payments AS (
  SELECT
    p.customer_id,
    p.month_start,
    COUNT(p.payment_id) AS payment_count,
    SUM(p.amount) AS monthly_amount,
    MAX(p.amount) AS monthly_max_amount
  FROM payments_2005 AS p
  GROUP BY
    p.customer_id,
    p.month_start
),
monthly_customer_join AS (
  SELECT
    mcp.customer_id,
    cs.store_id,
    cs.first_name,
    cs.last_name,
    cs.address_id,
    cs.city_name,
    cs.country_name,
    mcp.month_start,
    mcp.payment_count,
    mcp.monthly_amount
  FROM monthly_customer_payments AS mcp
  JOIN customer_store_country_city AS cs
    ON cs.customer_id = mcp.customer_id
),
customer_year_avg AS (
  SELECT
    customer_id,
    AVG(monthly_amount) AS personal_avg_monthly_amount
  FROM monthly_customer_join
  WHERE monthly_amount IS NOT NULL
  GROUP BY customer_id
),
store_month_rank AS (
  SELECT
    mcj.*,
    cya.personal_avg_monthly_amount,
    DENSE_RANK() OVER (
      PARTITION BY mcj.store_id, mcj.month_start
      ORDER BY mcj.monthly_amount DESC
    ) AS store_month_pos,
    COUNT(*) OVER (
      PARTITION BY mcj.store_id, mcj.month_start
    ) AS store_month_customer_cnt,
    PERCENT_RANK() OVER (
      PARTITION BY mcj.store_id, mcj.month_start
      ORDER BY mcj.monthly_amount DESC
    ) AS store_month_percent_rank
  FROM monthly_customer_join AS mcj
  JOIN customer_year_avg AS cya
    ON cya.customer_id = mcj.customer_id
),
qualifying_customers AS (
  SELECT
    customer_id
  FROM store_month_rank
  GROUP BY customer_id
  HAVING
    MIN(monthly_amount > personal_avg_monthly_amount * 1.5) = 1
    AND MIN(store_month_percent_rank < 0.05) = 1
),
final AS (
  SELECT
    smr.store_id,
    smr.customer_id,
    smr.first_name,
    smr.last_name,
    smr.address_id,
    smr.city_name,
    smr.country_name,
    smr.month_start AS month,
    smr.monthly_amount AS total_amount,
    smr.payment_count,
    (smr.monthly_amount - smr.personal_avg_monthly_amount) AS deviation_from_personal_avg,
    smr.store_month_pos AS position_in_store_for_month,
    smr.staff_id_last_in_month
  FROM (
    SELECT
      smr.*,
      (
        SELECT p2.p03
        FROM payments_2005 AS p2
        WHERE p2.customer_id = smr.customer_id
          AND date(p2.p06, 'start of month') = smr.month_start
        ORDER BY p2.payment_id DESC
        LIMIT 1
      ) AS staff_id_last_in_month
    FROM store_month_rank AS smr
  ) AS smr
  JOIN qualifying_customers qc
    ON qc.customer_id = smr.customer_id
)
SELECT
  f.customer_id,
  f.first_name,
  f.last_name,
  f.store_id,
  f.country_name,
  f.city_name,
  f.address_id,
  f.month,
  ROUND(f.total_amount, 2) AS total_amount,
  f.payment_count,
  ROUND(f.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  f.position_in_store_for_month,
  f.staff_id_last_in_month AS last_staff_id
FROM final AS f
ORDER BY
  f.month,
  f.store_id,
  f.position_in_store_for_month,
  f.total_amount DESC;