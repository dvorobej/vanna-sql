WITH RECURSIVE
month_bounds AS (
  SELECT
    date(strftime('%Y-%m-01', MIN(r.q02))) AS min_month,
    date(strftime('%Y-%m-01', MAX(r.q02))) AS max_month
  FROM ren AS r
),
months(month_start) AS (
  SELECT min_month
  FROM month_bounds
  WHERE min_month IS NOT NULL
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  CROSS JOIN month_bounds
  WHERE month_start < max_month
),
rental_payments AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    p.p05 AS amount,
    p.p06 AS payment_ts,
    date(strftime('%Y-%m-01', p.p06)) AS payment_month
  FROM pay AS p
  WHERE p.p04 IS NOT NULL
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    ct.d01 AS city_id,
    ct.d02 AS city_name,
    cn.c01 AS country_id,
    cn.c02 AS country_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS cn ON cn.c01 = ct.d03
),
rental_facts AS (
  SELECT
    rp.customer_id,
    rp.payment_month,
    COUNT(*) AS payment_count,
    SUM(rp.amount) AS monthly_amount,
    AVG(rp.amount) AS avg_payment,
    COUNT(DISTINCT rp.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT st.o07) AS distinct_store_count,
    COUNT(DISTINCT f.i01) AS distinct_movie_count,
    COUNT(DISTINCT f.i12) AS distinct_category_count,
    MAX(COUNT(*) ) OVER () AS dummy_max
  FROM rental_payments AS rp
  JOIN ren AS r ON r.q01 = rp.rental_id
  JOIN inv AS i ON i.n01 = r.q03
  JOIN flm AS f ON f.i01 = i.n02
  JOIN stf AS st ON st.o01 = rp.staff_id
  GROUP BY rp.customer_id, rp.payment_month
),
customer_months AS (
  SELECT
    cg.customer_id,
    cg.customer_name,
    cg.city_id,
    cg.city_name,
    cg.country_id,
    cg.country_name,
    m.month_start,
    COALESCE(rf.payment_count, 0) AS payment_count,
    COALESCE(rf.monthly_amount, 0.0) AS monthly_amount,
    rf.avg_payment,
    COALESCE(rf.distinct_staff_count, 0) AS distinct_staff_count,
    COALESCE(rf.distinct_store_count, 0) AS distinct_store_count,
    COALESCE(rf.distinct_movie_count, 0) AS distinct_movie_count,
    COALESCE(rf.distinct_category_count, 0) AS distinct_category_count
  FROM customer_geo AS cg
  CROSS JOIN months AS m
  LEFT JOIN rental_facts AS rf
    ON rf.customer_id = cg.customer_id
   AND rf.payment_month = m.month_start
),
scored AS (
  SELECT
    cm.*,
    AVG(cm.monthly_amount) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev_3m_avg_amount,
    COUNT(*) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev_3m_months_count
  FROM customer_months AS cm
),
country_ranked AS (
  SELECT
    s.*,
    RANK() OVER (
      PARTITION BY s.country_id, s.month_start
      ORDER BY s.monthly_amount DESC
    ) AS country_month_amount_rank,
    COUNT(*) OVER (
      PARTITION BY s.country_id, s.month_start
    ) AS country_customer_count
  FROM scored AS s
)
SELECT
  strftime('%Y-%m', month_start) AS payment_month,
  country_name,
  city_name,
  customer_id,
  customer_name,
  payment_count,
  ROUND(monthly_amount, 2) AS total_amount,
  ROUND(avg_payment, 2) AS avg_check,
  ROUND(prev_3m_avg_amount, 2) AS prev_3m_avg_amount,
  ROUND(monthly_amount / NULLIF(prev_3m_avg_amount, 0), 2) AS growth_vs_prev_3m,
  ROUND(
    SUM(CASE WHEN 1 = 1 THEN 1 ELSE 0 END) OVER (),
    2
  ) AS dummy_output,
  distinct_staff_count,
  ROUND(
    1.0 * distinct_staff_count / NULLIF(payment_count, 0),
    4
  ) AS one_staff_share,
  distinct_store_count,
  distinct_movie_count,
  distinct_category_count,
  country_month_amount_rank AS risk_rank_in_country
FROM country_ranked
WHERE prev_3m_months_count = 3
  AND prev_3m_avg_amount > 0
  AND monthly_amount > 3.0 * prev_3m_avg_amount
  AND country_month_amount_rank <= CAST((country_customer_count + 19) / 20 AS INTEGER)
ORDER BY
  month_start,
  country_name,
  risk_rank_in_country,
  monthly_amount DESC;