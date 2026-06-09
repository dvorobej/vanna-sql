WITH monthly AS (
  SELECT
    p.p02 AS customer_id,
    c.h02 AS registration_store_id,
    p.p06 AS payment_month_date,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS month_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT c.h02) AS store_count
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    c.h02,
    date(p.p06, 'start of month')
),
history AS (
  SELECT
    m.*,
    AVG(month_amount) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev3_avg_amount
  FROM monthly m
),
country_month AS (
  SELECT
    h.*,
    PERCENT_RANK() OVER (
      PARTITION BY registration_store_id, month_start
      ORDER BY month_amount DESC
    ) AS pr_in_country
  FROM (
    SELECT
      h2.*,
      cnt.country_id
    FROM history h2
    JOIN cus c ON c.h01 = h2.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt ON cnt.c01 = ct.d03
  ) h
  JOIN (
    SELECT 1 AS dummy
  ) x ON 1=1
),
country_percentiles AS (
  SELECT
    h.*,
    RANK() OVER (
      PARTITION BY country_id, month_start
      ORDER BY month_amount DESC
    ) AS country_rank,
    COUNT(*) OVER (
      PARTITION BY country_id, month_start
    ) AS country_count,
    (1.0 * RANK() OVER (
      PARTITION BY country_id, month_start
      ORDER BY month_amount DESC
    )) / (1.0 * COUNT(*) OVER (
      PARTITION BY country_id, month_start
    )) AS frac_rank
  FROM (
    SELECT
      h3.customer_id,
      h3.month_start,
      h3.month_amount,
      h3.payment_count,
      h3.staff_count,
      h3.store_count,
      ctry.c01 AS country_id
    FROM history h3
    JOIN cus c ON c.h01 = h3.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt ctry ON ctry.c01 = ct.d03
  ) h
),
country_median AS (
  SELECT
    country_id,
    month_start,
    AVG(month_amount) AS country_median_amount
  FROM (
    SELECT
      cpm.country_id,
      cpm.month_start,
      cpm.month_amount,
      ROW_NUMBER() OVER (
        PARTITION BY cpm.country_id, cpm.month_start
        ORDER BY cpm.month_amount
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY cpm.country_id, cpm.month_start
      ) AS cnt_rows
    FROM country_percentiles cpm
  ) t
  WHERE rn IN (
    CAST((cnt_rows + 1) / 2 AS INTEGER),
    CAST((cnt_rows + 2) / 2 AS INTEGER)
  )
  GROUP BY country_id, month_start
)
SELECT
  cm.customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  cm.month_start,
  ROUND(cm.month_amount, 2) AS month_amount,
  cm.payment_count,
  cm.staff_count,
  cm.store_count,
  cm.prev3_avg_amount AS prev3_avg_amount,
  ROUND(med.country_median_amount, 2) AS country_median_amount,
  CASE
    WHEN cm.prev3_avg_amount IS NOT NULL AND cm.prev3_avg_amount > 0
      THEN ROUND(cm.month_amount / cm.prev3_avg_amount, 4)
    ELSE NULL
  END AS growth_vs_prev3_avg_ratio,
  CASE
    WHEN med.country_median_amount > 0
      THEN ROUND(cm.month_amount / med.country_median_amount, 4)
    ELSE NULL
  END AS ratio_vs_country_median,
  cp.country_rank,
  cp.country_count
FROM (
  SELECT
    h.customer_id,
    h.month_start,
    h.month_amount,
    h.payment_count,
    h.staff_count,
    h.store_count,
    h.prev3_avg_amount,
    ctry.c01 AS country_id
  FROM history h
  JOIN cus c ON c.h01 = h.customer_id
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt ctry ON ctry.c01 = ct.d03
) cm
JOIN country_median med
  ON med.country_id = cm.country_id
 AND med.month_start = cm.month_start
JOIN (
  SELECT
    customer_id,
    month_start,
    country_id,
    RANK() OVER (PARTITION BY country_id, month_start ORDER BY month_amount DESC) AS country_rank,
    COUNT(*) OVER (PARTITION BY country_id, month_start) AS country_count
  FROM (
    SELECT
      h.customer_id,
      h.month_start,
      h.month_amount,
      ctry.c01 AS country_id
    FROM history h
    JOIN cus c ON c.h01 = h.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt ctry ON ctry.c01 = ct.d03
  )
) cp
  ON cp.customer_id = cm.customer_id
 AND cp.month_start = cm.month_start
 AND cp.country_id = cm.country_id
JOIN cus c ON c.h01 = cm.customer_id
WHERE
  cm.prev3_avg_amount > 0
  AND cm.month_amount >= 3.0 * cm.prev3_avg_amount
  AND med.country_median_amount > 0
  AND cm.month_amount >= 2.0 * med.country_median_amount
  AND cp.country_rank <= CAST((cp.country_count + 9) / 10 AS INTEGER)
ORDER BY
  cm.month_start,
  cp.country_rank,
  cm.customer_id;