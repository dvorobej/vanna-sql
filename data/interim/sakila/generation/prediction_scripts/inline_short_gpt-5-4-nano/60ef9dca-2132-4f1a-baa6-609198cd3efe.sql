WITH monthly AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    a.e05 AS city_id,
    ct.d02 AS city_name,
    cn.c02 AS country_name,
    strftime('%Y-%m', p.p06) AS month_key,
    SUBSTR(strftime('%Y-%m', p.p06), 6, 2) AS month_num,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS month_sum
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt cn ON cn.c01 = ct.d03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    c.h01, c.h02, a.e05, ct.d02, cn.c02, strftime('%Y-%m', p.p06)
),
year_avg AS (
  SELECT
    customer_id,
    store_id,
    AVG(month_sum) AS avg_month_sum
  FROM monthly
  GROUP BY customer_id, store_id
),
store_top5 AS (
  SELECT
    m.*,
    RANK() OVER (
      PARTITION BY m.store_id
      ORDER BY m_month_store_total DESC
    ) AS store_rank_by_total
  FROM (
    SELECT
      customer_id,
      store_id,
      SUM(month_sum) AS m_month_store_total
    FROM monthly
    GROUP BY customer_id, store_id
  ) t
  JOIN monthly m ON m.customer_id = t.customer_id AND m.store_id = t.store_id
),
last_staff AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_key,
    MAX(p.p06) AS last_pay_ts
  FROM pay p
  WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
  GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
last_staff_staff AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_key,
    MAX(p.p06) AS last_pay_ts,
    p.p03 AS last_staff_id
  FROM pay p
  WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
  GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
final AS (
  SELECT
    m.customer_id,
    m.store_id,
    m.city_name AS city,
    m.country_name AS country,
    m.month_num AS month,
    ROUND(m.month_sum, 2) AS month_sum,
    m.payment_count,
    ROUND(m.month_sum - ya.avg_month_sum, 2) AS deviation_from_avg,
    ya.avg_month_sum,
    DENSE_RANK() OVER (
      PARTITION BY m.store_id
      ORDER BY st_sum.store_total_sum DESC
    ) AS rank_in_store,
    ls.last_staff_id
  FROM monthly m
  JOIN year_avg ya
    ON ya.customer_id = m.customer_id AND ya.store_id = m.store_id
  JOIN (
    SELECT customer_id, store_id, SUM(month_sum) AS store_total_sum
    FROM monthly
    GROUP BY customer_id, store_id
  ) st_sum
    ON st_sum.customer_id = m.customer_id AND st_sum.store_id = m.store_id
  JOIN last_staff_staff ls
    ON ls.customer_id = m.customer_id AND ls.month_key = m.month_key
)
SELECT
  f.customer_id,
  f.store_id,
  f.city,
  f.country,
  f.month,
  f.month_sum,
  f.payment_count,
  f.deviation_from_avg,
  f.rank_in_store AS rank,
  f.last_staff_id AS last_staff_id
FROM final f
JOIN (
  SELECT
    store_id,
    CAST(CEIL(COUNT(*) * 0.05) AS INT) AS top5_count
  FROM (
    SELECT DISTINCT store_id, customer_id
    FROM monthly
  )
  GROUP BY store_id
) tc
  ON tc.store_id = f.store_id
WHERE
  f.month_sum > 2.0 * f.avg_month_sum
  AND f.rank_in_store <= tc.top5_count
ORDER BY f.store_id, f.month, f.month_sum DESC;