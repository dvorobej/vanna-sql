WITH
monthly_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS monthly_amount
  FROM pay AS p
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
monthly_with_personal_avg AS (
  SELECT
    mp.*,
    AVG(mp.monthly_amount) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_amount
  FROM monthly_pay AS mp
),
customer_month_median_country AS (
  SELECT
    mpa.*,
    PERCENT_RANK() OVER () AS dummy
  FROM monthly_with_personal_avg AS mpa
),
country_month_stats AS (
  SELECT
    cty.c01 AS country_id,
    mpa.month_start,
    mpa.payment_count,
    -- approximate median as the value at the middle rank
    ROW_NUMBER() OVER (
      PARTITION BY cty.c01, mpa.month_start
      ORDER BY mpa.payment_count
    ) AS rn,
    COUNT(*) OVER (
      PARTITION BY cty.c01, mpa.month_start
    ) AS cnt
  FROM monthly_with_personal_avg AS mpa
  JOIN cus AS c
    ON c.h01 = mpa.customer_id
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
),
country_month_median AS (
  SELECT
    country_id,
    month_start,
    AVG(payment_count) AS median_payment_count
  FROM (
    SELECT
      country_id,
      month_start,
      payment_count,
      cnt,
      rn
    FROM country_month_stats
  ) t
  WHERE t.rn IN (CAST((t.cnt + 1) / 2 AS INTEGER), CAST((t.cnt + 2) / 2 AS INTEGER))
  GROUP BY
    country_id,
    month_start
),
qualified_months AS (
  SELECT
    mpa.customer_id,
    mpa.month_start,
    mpa.payment_count,
    mpa.monthly_amount,
    cty.c01 AS country_id,
    cmm.median_payment_count
  FROM monthly_with_personal_avg AS mpa
  JOIN cus AS c
    ON c.h01 = mpa.customer_id
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN country_month_median AS cmm
    ON cmm.country_id = cty.c01
   AND cmm.month_start = mpa.month_start
  WHERE mpa.personal_avg_amount IS NOT NULL
    AND mpa.monthly_amount > 3 * mpa.personal_avg_amount
    AND mpa.payment_count > cmm.median_payment_count
),
customer_month_summary AS (
  SELECT
    qm.customer_id,
    qm.month_start,
    qm.country_id,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS total_amount,
    MAX(p.p05) AS max_payment_amount
  FROM qualified_months AS qm
  JOIN pay AS p
    ON p.p02 = qm.customer_id
   AND date(p.p06, 'start of month') = qm.month_start
  GROUP BY
    qm.customer_id,
    qm.month_start,
    qm.country_id
),
store_city_country AS (
  SELECT
    c.h01 AS customer_id,
    st.j01 AS store_id,
    adr.e01 AS customer_address_id,
    ct.d02 AS city_name,
    cnt.c02 AS country_name,
    cnt.c01 AS country_id
  FROM cus AS c
  JOIN sto AS st
    ON st.j01 = c.h02
  JOIN adr
    ON adr.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = adr.e05
  JOIN cnt
    ON cnt.c01 = ct.d03
),
action_new_category_share AS (
  SELECT
    qm.customer_id,
    qm.month_start,
    SUM(CASE WHEN ca.category_name IN ('Action', 'New') THEN p.p05 ELSE 0 END) * 1.0
      / NULLIF(SUM(p.p05), 0) AS action_new_payment_share
  FROM qualified_months AS qm
  JOIN pay AS p
    ON p.p02 = qm.customer_id
   AND date(p.p06, 'start of month') = qm.month_start
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS inv
    ON inv.n01 = r.q03
  JOIN flm AS f
    ON f.i01 = inv.n02
  JOIN flc AS fc
    ON fc.l01 = f.i01
  JOIN cat AS ca
    ON ca.g01 = fc.l02
  GROUP BY
    qm.customer_id,
    qm.month_start
)
SELECT
  cms.customer_id AS h01,
  sc.country_name,
  sc.city_name,
  sc.store_id AS j01,
  cms.month_start AS month,
  cms.payment_count,
  ROUND(cms.total_amount, 2) AS total_amount,
  ROUND(cms.max_payment_amount, 2) AS max_payment_amount,
  ROUND(cms.total_amount - 0, 2) AS total_amount_check,
  RANK() OVER (
    PARTITION BY sc.country_id, sc.city_name
    ORDER BY cms.total_amount DESC
  ) AS country_city_rank,
  COALESCE(share.action_new_payment_share, 0) AS action_new_payment_share
FROM customer_month_summary AS cms
JOIN store_city_country AS sc
  ON sc.customer_id = cms.customer_id
JOIN qualified_months AS qm
  ON qm.customer_id = cms.customer_id
 AND qm.month_start = cms.month_start
LEFT JOIN action_new_category_share AS share
  ON share.customer_id = cms.customer_id
 AND share.month_start = cms.month_start
ORDER BY
  sc.country_name,
  month,
  cms.total_amount DESC,
  cms.customer_id;