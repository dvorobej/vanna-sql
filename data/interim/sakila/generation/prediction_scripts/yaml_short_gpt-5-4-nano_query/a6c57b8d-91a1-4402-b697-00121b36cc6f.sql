WITH payments_2005 AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS amount,
    p.p06 AS payment_date,
    date(p.p06, 'start of month') AS month_start
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
),
customer_monthly AS (
  SELECT
    customer_id,
    month_start,
    COUNT(*) AS payment_count,
    SUM(amount) AS payment_sum
  FROM payments_2005
  GROUP BY customer_id, month_start
),
customer_month_with_history AS (
  SELECT
    cm.*,
    AVG(cm.payment_sum) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS personal_avg_monthly_sum
  FROM customer_monthly AS cm
),
country_month_avg AS (
  SELECT
    c.customer_id,
    c.month_start,
    c.payment_sum,
    c.payment_count,
    c.personal_avg_monthly_sum,
    AVG(c.payment_sum) OVER (
      PARTITION BY m.country_id, c.month_start
    ) AS country_avg_monthly_payment_sum
  FROM customer_month_with_history AS c
  JOIN cus AS cu
    ON cu.h01 = c.customer_id
  JOIN adr AS a
    ON a.e01 = cu.h06
  JOIN cty AS city
    ON city.d01 = a.e05
  JOIN cnt AS m
    ON m.c01 = city.d03
),
country_month_top_rank AS (
  SELECT
    c.customer_id,
    c.month_start,
    c.payment_sum,
    c.payment_count,
    c.personal_avg_monthly_sum,
    RANK() OVER (
      PARTITION BY cn.country_id, c.month_start
      ORDER BY c.payment_sum DESC
    ) AS customer_rank_in_country_month,
    COUNT(*) OVER (
      PARTITION BY cn.country_id, c.month_start
    ) AS country_customers_in_month,
    cn.country_id
  FROM customer_month_with_history AS c
  JOIN cus AS cu
    ON cu.h01 = c.customer_id
  JOIN adr AS a
    ON a.e01 = cu.h06
  JOIN cty AS city
    ON city.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = city.d03
),
suspicious_months AS (
  SELECT
    cmw.customer_id,
    cmw.month_start,
    cmw.payment_sum,
    cmw.payment_count,
    cmw.personal_avg_monthly_sum,
    cmp.country_id,
    cmp.customer_rank_in_country_month,
    (cmp.country_customers_in_month * 0.10) AS top10_threshold_customers
  FROM (
    SELECT
      cm.*,
      AVG(cm.payment_sum) OVER (
        PARTITION BY cm.customer_id
      ) AS personal_avg_monthly_sum
    FROM customer_monthly AS cm
  ) AS cmw
  JOIN (
    SELECT
      c.customer_id,
      c.month_start,
      cn.country_id,
      c.customer_rank_in_country_month,
      c.country_customers_in_month
    FROM country_month_top_rank AS c
    JOIN cnt AS cn
      ON cn.country_id = c.country_id
    UNION ALL
    SELECT
      c.customer_id,
      c.month_start,
      c.country_id,
      c.customer_rank_in_country_month,
      c.country_customers_in_month
    FROM country_month_top_rank AS c
  ) AS cmp
    ON cmp.customer_id = cmw.customer_id
   AND cmp.month_start = cmw.month_start
  WHERE cmw.personal_avg_monthly_sum IS NOT NULL
    AND cmw.personal_avg_monthly_sum > 0
    AND cmw.payment_sum > 2.0 * cmw.personal_avg_monthly_sum
)
, staff_top_in_month AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_month_sum,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC, p.p03
    ) AS rn
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    p.p03
)
SELECT
  s.customer_id,
  cu.h03 || ' ' || cu.h04 AS customer_name,
  cn.c02 AS country,
  city.d02 AS city,
  strftime('%Y-%m', s.month_start) AS month,
  ROUND(s.payment_sum, 2) AS payment_sum,
  s.payment_count,
  ROUND(s.payment_sum - s.personal_avg_monthly_sum, 2) AS deviation_from_personal_avg,
  RANK() OVER (
    PARTITION BY cn.c01, s.month_start
    ORDER BY s.payment_sum DESC
  ) AS rank_in_country_month,
  st.o02 || ' ' || st.o03 AS top_staff_name,
  st.o01 AS top_staff_id
FROM (
  SELECT
    c.customer_id,
    c.month_start,
    c.payment_sum,
    c.payment_count,
    AVG(c.payment_sum) OVER (PARTITION BY c.customer_id) AS personal_avg_monthly_sum,
    c.payment_sum,
    c.payment_count,
    c.month_start
  FROM customer_monthly c
) AS s
JOIN cus AS cu
  ON cu.h01 = s.customer_id
JOIN adr AS a
  ON a.e01 = cu.h06
JOIN cty AS city
  ON city.d01 = a.e05
JOIN cnt AS cn
  ON cn.c01 = city.d03
JOIN staff_top_in_month AS stm
  ON stm.customer_id = s.customer_id
 AND stm.month_start = s.month_start
 AND stm.rn = 1
JOIN stf AS st
  ON st.o01 = stm.staff_id
WHERE
  s.personal_avg_monthly_sum > 0
  AND s.payment_sum > 2.0 * s.personal_avg_monthly_sum
  AND (
    RANK() OVER (
      PARTITION BY cn.c01, s.month_start
      ORDER BY s.payment_sum DESC
    ) <= (
      SELECT
        CAST(COUNT(*) * 0.10 AS INTEGER) + 1
      FROM customer_monthly cm2
      JOIN cus cu2 ON cu2.h01 = cm2.customer_id
      JOIN adr a2 ON a2.e01 = cu2.h06
      JOIN cty city2 ON city2.d01 = a2.e05
      JOIN cnt cn2 ON cn2.c01 = city2.d03
      WHERE cn2.c01 = cn.c01
        AND cm2.month_start = s.month_start
    )
  )
ORDER BY
  cn.c02,
  s.month_start,
  s.payment_sum DESC,
  s.customer_id;