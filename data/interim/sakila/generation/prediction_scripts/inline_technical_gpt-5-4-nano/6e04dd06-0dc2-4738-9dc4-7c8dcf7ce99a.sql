WITH monthly_base AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    co.c01 AS country_id,
    co.c02 AS country_name,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS monthly_amount,
    COUNT(p.p01) AS payment_count,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT c.h02) AS distinct_store_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ct.d03
  GROUP BY
    c.h01, c.h03, c.h04,
    co.c01, co.c02,
    date(p.p06, 'start of month')
),
monthly_with_history AS (
  SELECT
    mb.*,
    AVG(monthly_amount) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS avg_prev_3_months,
    LAG(monthly_amount, 1) OVER (PARTITION BY customer_id ORDER BY month_start) AS prev1_amount,
    LAG(monthly_amount, 2) OVER (PARTITION BY customer_id ORDER BY month_start) AS prev2_amount,
    LAG(monthly_amount, 3) OVER (PARTITION BY customer_id ORDER BY month_start) AS prev3_amount
  FROM monthly_base AS mb
),
country_month_ranked AS (
  SELECT
    mwh.*,
    ROW_NUMBER() OVER (
      PARTITION BY country_id, month_start
      ORDER BY monthly_amount DESC, customer_id
    ) AS rn_desc,
    COUNT(*) OVER (
      PARTITION BY country_id, month_start
    ) AS country_customers_cnt
  FROM monthly_with_history AS mwh
),
country_month_percentiles AS (
  -- 95-й процентиль и медиана (50-й) месячных сумм по стране/месяцу (линейная аппроксимация через соседние ранги)
  SELECT
    cmr.country_id,
    cmr.month_start,

    MAX(CASE WHEN cmr.rn_asc = CAST((0.50 * (cmr.country_customers_cnt + 1)) AS INTEGER)
             THEN cmr.monthly_amount END) AS p50_lower,

    MAX(CASE WHEN cmr.rn_asc = CAST((0.50 * (cmr.country_customers_cnt + 1)) AS INTEGER) + 1
             THEN cmr.monthly_amount END) AS p50_upper,

    MAX(CASE WHEN cmr.rn_asc = CAST((0.95 * (cmr.country_customers_cnt + 1)) AS INTEGER)
             THEN cmr.monthly_amount END) AS p95_lower,

    MAX(CASE WHEN cmr.rn_asc = CAST((0.95 * (cmr.country_customers_cnt + 1)) AS INTEGER) + 1
             THEN cmr.monthly_amount END) AS p95_upper,

    MAX(cmr.country_customers_cnt) AS country_customers_cnt_max
  FROM (
    SELECT
      mcr.*,
      ROW_NUMBER() OVER (
        PARTITION BY country_id, month_start
        ORDER BY monthly_amount ASC, customer_id
      ) AS rn_asc
    FROM country_month_ranked AS mcr
  ) AS cmr
  GROUP BY
    cmr.country_id, cmr.month_start
),
final AS (
  SELECT
    cmr.customer_id,
    cmr.customer_first_name,
    cmr.customer_last_name,
    cmr.country_id,
    cmr.country_name,
    cmr.month_start,
    cmr.monthly_amount,
    cmr.payment_count,
    cmr.distinct_staff_count,
    cmr.distinct_store_count,
    cmr.avg_prev_3_months,

    -- медиана
    CASE
      WHEN cpm.p50_lower IS NULL OR cpm.p50_upper IS NULL THEN NULL
      ELSE (cpm.p50_lower + (cpm.p50_upper - cpm.p50_lower) * 0.5)
    END AS median_country_monthly_amount,

    -- 95-й процентиль
    CASE
      WHEN cpm.p95_lower IS NULL OR cpm.p95_upper IS NULL THEN NULL
      ELSE (cpm.p95_lower + (cpm.p95_upper - cpm.p95_lower) * 0.5)
    END AS p95_country_monthly_amount,

    -- попадание в верхние 5%: rn_desc <= ceil(0.05 * n)
    (cmr.rn_desc <= CAST(CEIL(0.05 * cmr.country_customers_cnt AS REAL)) AS INTEGER) AS in_top_5pct
  FROM country_month_ranked AS cmr
  JOIN country_month_percentiles AS cpm
    ON cpm.country_id = cmr.country_id
   AND cpm.month_start = cmr.month_start
)
SELECT
  customer_id,
  customer_first_name,
  customer_last_name,
  country_name,
  month_start,
  ROUND(monthly_amount, 2) AS monthly_amount,
  payment_count,
  distinct_staff_count,
  distinct_store_count,
  ROUND(avg_prev_3_months, 2) AS avg_prev_3_months,
  ROUND(median_country_monthly_amount, 2) AS median_country_monthly_amount,
  in_top_5pct
FROM final
WHERE avg_prev_3_months IS NOT NULL
  AND monthly_amount >= 3.0 * avg_prev_3_months
  AND median_country_monthly_amount IS NOT NULL
  AND monthly_amount >= 2.0 * median_country_monthly_amount
  AND in_top_5pct = 1
ORDER BY
  country_name,
  month_start,
  monthly_amount DESC,
  customer_id;