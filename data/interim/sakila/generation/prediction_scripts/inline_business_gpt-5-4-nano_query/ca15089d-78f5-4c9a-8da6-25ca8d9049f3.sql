WITH monthly_payments AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    co.c02 AS country_name,
    ci.d02 AS city_name,
    strftime('%Y-%m', p.p06) AS payment_month,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS month_sum,
    MAX(p.p05) AS max_payment,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT COALESCE(s.o07, -1)) AS distinct_store_count
  FROM pay AS p
  JOIN cus AS c ON c.h01 = p.p02
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
  JOIN stf AS s ON s.o01 = p.p03
  WHERE p.p06 IS NOT NULL
  GROUP BY
    c.h01, c.h03, c.h04,
    co.c02, ci.d02,
    strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
  SELECT
    mp.*,
    AVG(mp.month_sum) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.payment_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_month_avg_sum
  FROM monthly_payments AS mp
),
qualified AS (
  SELECT
    mwh.*,
    (mwh.max_payment * 1.0 / NULLIF(mwh.month_sum, 0)) AS max_payment_share,
    RANK() OVER (
      PARTITION BY mwh.country_name, mwh.payment_month
      ORDER BY mwh.month_sum DESC
    ) AS country_month_rank
  FROM monthly_with_history AS mwh
  WHERE mwh.prev_month_avg_sum IS NOT NULL
    AND mwh.prev_month_avg_sum > 0
    AND mwh.month_sum >= 3.0 * mwh.prev_month_avg_sum
    AND mwh.payment_count >= 3
    AND (mwh.distinct_staff_count >= 2 OR mwh.distinct_store_count >= 2)
),
final AS (
  SELECT
    q.payment_month AS month,
    q.customer_id,
    q.customer_first_name,
    q.customer_last_name,
    q.country_name,
    q.city_name,
    q.payment_count,
    ROUND(q.month_sum, 2) AS month_sum,
    ROUND(q.max_payment, 2) AS max_payment,
    ROUND(q.max_payment_share, 4) AS max_payment_share,
    q.distinct_staff_count AS different_staff_count,
    q.distinct_store_count AS different_store_count,
    q.country_month_rank AS country_month_rank
  FROM qualified q
)
SELECT
  month,
  customer_id,
  customer_first_name || ' ' || customer_last_name AS fio,
  country_name AS country,
  city_name AS city,
  payment_count,
  month_sum,
  max_payment,
  max_payment_share,
  different_staff_count,
  different_store_count,
  country_month_rank
FROM final
ORDER BY
  country_month_rank,
  month,
  month_sum DESC,
  customer_id;