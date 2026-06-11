WITH pay_monthly AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_ym,
    SUM(p.p05) AS month_payment_sum,
    COUNT(p.p01) AS month_payment_count,
    GROUP_CONCAT(DISTINCT p.p03) AS staff_ids,
    GROUP_CONCAT(DISTINCT s.o07) AS store_ids
  FROM pay p
  JOIN stf s
    ON s.o01 = p.p03
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
personal_history AS (
  SELECT
    pm.customer_id,
    pm.month_ym,
    pm.month_payment_sum,
    pm.month_payment_count,
    pm.staff_ids,
    pm.store_ids,
    (
      SELECT AVG(ph.month_payment_sum)
      FROM pay_monthly ph
      WHERE ph.customer_id = pm.customer_id
        AND date(ph.month_ym || '-01') BETWEEN date(pm.month_ym || '-01', '-3 months') AND date(pm.month_ym || '-01', '-1 day')
    ) AS avg_prev_3m_sum
  FROM pay_monthly pm
),
country_month_stats AS (
  SELECT
    c.h01 AS customer_id,
    m.month_ym,
    m.month_payment_sum,
    (
      SELECT AVG(m2.month_payment_sum * 1.0)
      FROM (
        SELECT
          pm2.month_payment_sum
        FROM pay_monthly pm2
        JOIN cus c2 ON c2.h01 = pm2.customer_id
        JOIN adr a2 ON a2.e01 = c2.h06
        JOIN cty city2 ON city2.d01 = a2.e05
        JOIN cnt co2 ON co2.c01 = city2.d03
        WHERE co2.c01 = co.c01
          AND pm2.month_ym = m.month_ym
      ) x
    ) AS dummy
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty city ON city.d01 = a.e05
  JOIN cnt co ON co.c01 = city.d03
  JOIN pay_monthly m ON m.customer_id = c.h01
),
country_month_ranked AS (
  SELECT
    pm.*,
    co.c01 AS country_id,
    (
      SELECT
        COUNT(*)
      FROM pay_monthly pm2
      JOIN cus c2 ON c2.h01 = pm2.customer_id
      JOIN adr a2 ON a2.e01 = c2.h06
      JOIN cty city2 ON city2.d01 = a2.e05
      WHERE city2.d03 = city.d03
        AND pm2.month_ym = pm.month_ym
    ) AS dummy2
  FROM pay_monthly pm
  JOIN cus c ON c.h01 = pm.customer_id
  JOIN adr a ON a.e01 = c.h06
  JOIN cty city ON city.d01 = a.e05
  JOIN cnt co ON co.c01 = city.d03
),
country_month_with_median_and_percentile AS (
  SELECT
    cmr.*,
    ROW_NUMBER() OVER (
      PARTITION BY cmr.country_id, cmr.month_ym
      ORDER BY cmr.month_payment_sum
    ) AS rn_asc,
    ROW_NUMBER() OVER (
      PARTITION BY cmr.country_id, cmr.month_ym
      ORDER BY cmr.month_payment_sum DESC
    ) AS rn_desc,
    COUNT(*) OVER (
      PARTITION BY cmr.country_id, cmr.month_ym
    ) AS cnt_in_country_month
  FROM country_month_ranked cmr
),
country_month_median AS (
  SELECT
    country_id,
    month_ym,
    AVG(1.0 * month_payment_sum) AS median_country_payment_sum
  FROM country_month_with_median_and_percentile
  WHERE rn_asc IN (
    CAST((cnt_in_country_month + 1) / 2 AS INTEGER),
    CAST((cnt_in_country_month + 2) / 2 AS INTEGER)
  )
  GROUP BY country_id, month_ym
),
final_flagged AS (
  SELECT
    cm.country_id,
    cm.customer_id,
    cm.month_ym,
    cm.month_payment_sum,
    cm.month_payment_count,
    cm.staff_ids,
    cm.store_ids,
    pm.avg_prev_3m_sum,
    cmw.median_country_payment_sum,
    cm.rn_desc,
    cm.cnt_in_country_month,
    (cm.month_payment_sum >= 3 * pm.avg_prev_3m_sum) AS cond_growth,
    (cm.month_payment_sum >= 2 * cmw.median_country_payment_sum) AS cond_over_median,
    (cm.rn_desc <= CAST(cm.cnt_in_country_month * 0.05 AS INTEGER) OR cm.rn_desc <= 1) AS cond_top_5pct
  FROM country_month_with_median_and_percentile cm
  JOIN personal_history pm
    ON pm.customer_id = cm.customer_id
   AND pm.month_ym = cm.month_ym
  JOIN country_month_median cmw
    ON cmw.country_id = cm.country_id
   AND cmw.month_ym = cm.month_ym
)
SELECT
  f.customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  f.month_ym AS payment_month,
  f.month_payment_count AS month_payment_count,
  ROUND(f.month_payment_sum, 2) AS month_payment_sum,
  f.staff_ids AS staff_ids,
  f.store_ids AS store_ids,
  ROUND(f.avg_prev_3m_sum, 2) AS avg_payment_sum_prev_3m,
  ROUND(f.median_country_payment_sum, 2) AS median_country_payment_sum,
  CAST(
    ROUND(
      (f.month_payment_sum / NULLIF(f.avg_prev_3m_sum, 0)),
      2
    ) AS REAL
  ) AS growth_factor_vs_prev_3m,
  CAST(
    ROUND(
      (f.month_payment_sum / NULLIF(f.median_country_payment_sum, 0)),
      2
    ) AS REAL
  ) AS ratio_vs_country_median
FROM final_flagged f
JOIN cus c
  ON c.h01 = f.customer_id
WHERE f.cond_growth = 1
  AND f.cond_over_median = 1
  AND f.cond_top_5pct = 1
ORDER BY
  f.country_id,
  f.month_ym,
  f.month_payment_sum DESC;