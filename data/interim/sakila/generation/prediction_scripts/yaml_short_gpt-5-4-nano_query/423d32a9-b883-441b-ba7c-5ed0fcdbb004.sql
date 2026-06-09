WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    co.c02 AS country,
    ci.d02 AS city
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
),
monthly_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS payment_sum,
    AVG(p.p05) AS payment_avg,
    COUNT(DISTINCT p.p03) AS staff_cnt,
    COUNT(DISTINCT s.o07) AS store_cnt
  FROM pay AS p
  JOIN ren AS r ON r.q01 = p.p04
  JOIN stf AS s ON s.o01 = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
monthly_scored AS (
  SELECT
    mp.*,
    cg.first_name,
    cg.last_name,
    cg.country,
    cg.city,
    AVG(mp.payment_sum) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_avg_payment_sum
  FROM monthly_pay AS mp
  JOIN customer_geo AS cg
    ON cg.customer_id = mp.customer_id
),
qualified_months AS (
  SELECT
    ms.*,
    (ms.payment_sum - ms.prev_months_avg_payment_sum) AS deviation_from_prev_avg,
    ROW_NUMBER() OVER (
      PARTITION BY ms.customer_id
      ORDER BY ms.month_start
    ) AS rn_in_customer
  FROM monthly_scored AS ms
  WHERE ms.prev_months_avg_payment_sum IS NOT NULL
    AND ms.payment_count >= 5
    AND ms.payment_sum >= 2.0 * ms.prev_months_avg_payment_sum
    AND (ms.staff_cnt >= 2 OR ms.store_cnt >= 2)
),
all_months_flag AS (
  SELECT
    customer_id
  FROM (
    SELECT
      customer_id,
      COUNT(*) AS qualified_month_cnt
    FROM qualified_months
    GROUP BY customer_id
  ) q
  -- требуем: клиент удовлетворяет условию в каждом месяце, начиная с февраля (январь не имеет "предыдущих")
  WHERE q.qualified_month_cnt = 11
)
SELECT
  ql.customer_id,
  ql.first_name,
  ql.last_name,
  ql.country,
  ql.city,
  strftime('%Y-%m', ql.month_start) AS payment_month,
  ROUND(ql.payment_sum, 2) AS payment_sum,
  ql.payment_count,
  ROUND(ql.prev_months_avg_payment_sum, 2) AS prev_months_avg_payment_sum,
  ROUND(ql.deviation_from_prev_avg, 2) AS deviation_from_prev_avg,
  RANK() OVER (
    PARTITION BY ql.country, ql.month_start
    ORDER BY ql.deviation_from_prev_avg DESC
  ) AS country_month_client_rank_by_deviation
FROM qualified_months AS ql
JOIN all_months_flag AS af
  ON af.customer_id = ql.customer_id
ORDER BY
  ql.country,
  ql.month_start,
  country_month_client_rank_by_deviation,
  ql.customer_id;