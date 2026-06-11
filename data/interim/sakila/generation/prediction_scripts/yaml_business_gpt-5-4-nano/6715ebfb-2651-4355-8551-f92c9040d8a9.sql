WITH monthly AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_ym,
    SUM(CAST(p.p05 AS REAL)) AS month_amount,
    COUNT(*) AS payment_count
  FROM pay AS p
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
personal_avg AS (
  SELECT
    customer_id,
    AVG(month_amount) AS personal_avg_amount,
    AVG(payment_count) AS personal_avg_payment_count
  FROM monthly
  GROUP BY customer_id
),
country_month_stats AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    m.month_ym,
    m.month_amount,
    m.payment_count
  FROM monthly AS m
  JOIN cus AS c
    ON c.h01 = m.customer_id
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = ci.d03
),
country_median_payment_count AS (
  -- SQLite: approximate median using row number at 50% (works when "median" is interpreted as nearest-middle order statistic)
  SELECT
    cms.country_id,
    cms.month_ym,
    AVG(cms.payment_count) AS country_median_payment_count
  FROM (
    SELECT
      country_id,
      month_ym,
      payment_count,
      ROW_NUMBER() OVER (
        PARTITION BY country_id, month_ym
        ORDER BY payment_count
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY country_id, month_ym
      ) AS cnt_rows
    FROM country_month_stats
  ) AS cms
  WHERE rn IN (
    CAST((cnt_rows + 1) / 2 AS INTEGER),
    CAST((cnt_rows + 2) / 2 AS INTEGER)
  )
  GROUP BY
    country_id,
    month_ym
),
candidate_months AS (
  SELECT
    cms.customer_id,
    cms.country_id,
    cms.country_name,
    cms.month_ym,
    cms.month_amount,
    cms.payment_count,
    pa.personal_avg_amount,
    pa.personal_avg_payment_count,
    cm.country_median_payment_count
  FROM country_month_stats AS cms
  JOIN personal_avg AS pa
    ON pa.customer_id = cms.customer_id
  JOIN country_median_payment_count AS cm
    ON cm.country_id = cms.country_id
   AND cm.month_ym = cms.month_ym
  WHERE
    pa.personal_avg_amount IS NOT NULL
    AND pa.personal_avg_amount > 0
    AND cms.month_amount > 1.5 * pa.personal_avg_amount
    AND cms.payment_count > cm.country_median_payment_count
),
payment_breakdown AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_ym,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS total_amount,
    MAX(CAST(p.p05 AS REAL)) AS max_payment_amount,
    SUM(
      CASE
        WHEN cat.g02 IN ('Action', 'New') THEN CAST(p.p05 AS REAL)
        ELSE 0
      END
    ) AS action_new_amount,
    SUM(CAST(p.p05 AS REAL)) AS all_amount
  FROM pay AS p
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
  LEFT JOIN flc AS fc
    ON fc.l01 = i.n02
  LEFT JOIN cat AS cat
    ON cat.g01 = fc.l02
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
top_store_month AS (
  SELECT
    s.customer_id,
    s.month_ym,
    s.store_id
  FROM (
    SELECT
      p.p02 AS customer_id,
      strftime('%Y-%m', p.p06) AS month_ym,
      cus.h02 AS store_id,
      SUM(CAST(p.p05 AS REAL)) AS store_amount,
      ROW_NUMBER() OVER (
        PARTITION BY p.p02, strftime('%Y-%m', p.p06)
        ORDER BY SUM(CAST(p.p05 AS REAL)) DESC
      ) AS rn
    FROM pay AS p
    JOIN cus
      ON cus.h01 = p.p02
    WHERE
      p.p06 >= '2005-07-01' -- no-op safeguard for query planning;