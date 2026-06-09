WITH
customer_home AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS home_store_id,
    co.c02 AS customer_country,
    ci.d02 AS customer_city
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ci ON ci.d01 = a.e05
  JOIN cnt co ON co.c01 = ci.d03
),
payments_monthly AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS payment_sum,
    SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) AS off_home_store_payment_count,
    MAX(p.p05) AS max_single_payment,
    SUM(CASE
          WHEN r.q01 IS NOT NULL AND (co2.c02 <> hc.customer_country OR ci2.d02 <> hc.customer_city)
          THEN p.p05 ELSE 0 END
    ) AS off_home_geo_payment_sum
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  JOIN stf s ON s.o01 = p.p03
  LEFT JOIN ren r ON r.q01 = p.p04
  LEFT JOIN inv i ON i.n01 = r.q03
  LEFT JOIN sto s2 ON s2.j01 = i.n03
  LEFT JOIN adr a2 ON a2.e01 = s2.j06
  LEFT JOIN cty ci2 ON ci2.d01 = a2.e05
  LEFT JOIN cnt co2 ON co2.c01 = ci2.d03
  LEFT JOIN customer_home hc ON hc.customer_id = p.p02
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
monthly_with_prev_avg AS (
  SELECT
    pm.*,
    AVG(pm.payment_sum) OVER (
      PARTITION BY pm.customer_id
      ORDER BY pm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_monthly_payment_sum
  FROM payments_monthly pm
),
months_suspicious AS (
  SELECT
    mw.customer_id,
    mw.month_start,
    mw.payment_sum,
    mw.payment_count,
    CAST(mw.off_home_store_payment_count AS REAL) / NULLIF(mw.payment_count, 0) AS off_home_store_payment_share,
    mw.max_single_payment,
    (mw.payment_sum - mw.prev_avg_monthly_payment_sum) AS deviation_from_prev_avg
  FROM monthly_with_prev_avg mw
  WHERE mw.prev_avg_monthly_payment_sum IS NOT NULL
    AND mw.prev_avg_monthly_payment_sum > 0
    AND mw.payment_count >= 5
    AND mw.payment_sum > 3.0 * mw.prev_avg_monthly_payment_sum
),
customer_month_rank AS (
  SELECT
    ms.*,
    RANK() OVER (
      PARTITION BY ms.customer_id
      ORDER BY ms.payment_sum DESC
    ) AS customer_month_payment_rank
  FROM months_suspicious ms
),
categories_by_month AS (
  SELECT
    ms.customer_id,
    ms.month_start,
    GROUP_CONCAT(DISTINCT ca.g02, ', ') AS top_categories
  FROM months_suspicious ms
  JOIN pay p ON p.p02 = ms.customer_id
           AND date(p.p06, 'start of month') = ms.month_start
           AND p.p04 IS NOT NULL
  JOIN ren r ON r.q01 = p.p04
  JOIN inv i ON i.n01 = r.q03
  JOIN flc fc ON fc.l01 = i.n02
  JOIN cat ca ON ca.g01 = fc.l02
  GROUP BY
    ms.customer_id,
    ms.month_start
)
SELECT
  cmr.customer_id,
  ch.customer_country,
  ch.customer_city,
  strftime('%Y-%m', cmr.month_start) AS payment_month,
  ROUND(cmr.payment_sum, 2) AS month_payment_sum,
  cmr.payment_count,
  ROUND(cmr.off_home_store_payment_share, 4) AS off_home_store_payment_share,
  ROUND(cmr.max_single_payment, 2) AS max_single_payment,
  cmr.customer_month_payment_rank,
  cbm.top_categories AS categories_list
FROM customer_month_rank cmr
JOIN customer_home ch ON ch.customer_id = cmr.customer_id
JOIN categories_by_month cbm
  ON cbm.customer_id = cmr.customer_id
 AND cbm.month_start = cmr.month_start
ORDER BY
  cmr.month_start,
  cmr.customer_id;