WITH monthly AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    p.p06 AS payment_date,
    strftime('%Y-%m', p.p06) AS ym,
    CAST(strftime('%m', p.p06) AS INTEGER) AS month_num,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS month_total,
    AVG(p.p05) AS month_avg
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
    AND c.h07 = 'Y'
  GROUP BY
    c.h01, c.h02, c.h03, c.h04, strftime('%Y-%m', p.p06)
),
year_avg AS (
  SELECT
    customer_id,
    store_id,
    AVG(month_total) AS avg_month_total_year
  FROM monthly
  GROUP BY customer_id, store_id
),
ranked_store AS (
  SELECT
    m.*,
    ya.avg_month_total_year,
    (m.month_total - ya.avg_month_total_year) AS deviation_from_avg,
    (m.month_total - ya.avg_month_total_year) / NULLIF(ya.avg_month_total_year, 0) AS deviation_ratio,
    RANK() OVER (
      PARTITION BY m.store_id
      ORDER BY m.month_total DESC
    ) AS store_month_rank,
    CAST(
      (COUNT(*) OVER (PARTITION BY m.store_id) * 0.05) AS INTEGER
    ) AS top_5pct_cutoff
  FROM monthly m
  JOIN year_avg ya
    ON ya.customer_id = m.customer_id
   AND ya.store_id = m.store_id
),
filtered AS (
  SELECT *
  FROM ranked_store
  WHERE
    ya.avg_month_total_year IS NOT NULL
    AND m.month_total > 2 * ya.avg_month_total_year
    AND store_month_rank <= (
      SELECT MAX(top_5pct_cutoff)
      FROM ranked_store rs2
      WHERE rs2.store_id = ranked_store.store_id
    )
)
SELECT
  f.customer_id AS customer_id,
  f.first_name || ' ' || f.last_name AS customer_name,
  f.store_id AS store_id,
  co.c02 AS country,
  ci.d02 AS city,
  f.month_num AS month,
  ROUND(f.month_total, 2) AS month_total,
  f.payment_count AS payment_count,
  ROUND(f.deviation_from_avg, 2) AS deviation_from_avg,
  f.store_month_rank AS month_rank_in_store,
  (
    SELECT p2.p03
    FROM pay p2
    WHERE p2.p02 = f.customer_id
      AND strftime('%Y-%m', p2.p06) = f.ym
    ORDER BY p2.p06 DESC
    LIMIT 1
  ) AS last_staff_id
FROM filtered f
JOIN cus c ON c.h01 = f.customer_id AND c.h02 = f.store_id
JOIN adr a ON a.e01 = c.h06
JOIN cty ci ON ci.d01 = a.e05
JOIN cnt co ON co.c01 = ci.d03
ORDER BY
  f.store_id,
  f.month_total DESC,
  f.customer_id;