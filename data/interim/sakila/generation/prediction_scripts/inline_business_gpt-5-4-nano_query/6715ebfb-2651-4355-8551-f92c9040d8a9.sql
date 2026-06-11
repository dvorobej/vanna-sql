WITH monthly_customer AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    c.h02 AS store_id,
    ct.c02 AS country_name,
    ci.d02 AS city_name,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS month_amount,
    MAX(CAST(p.p05 AS REAL)) AS max_single_payment
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS ct
    ON ct.c01 = ci.d03
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    c.h02,
    ct.c02,
    ci.d02
),
monthly_with_history AS (
  SELECT
    mc.*,
    AVG(mc.month_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_month_amount,
    AVG(mc.payment_count) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_payment_count
  FROM monthly_customer AS mc
),
country_month_median_payments AS (
  SELECT
    mwh.country_name,
    mwh.month_start,
    AVG(mwh.payment_count) AS country_month_median_payment_count
  FROM (
    SELECT
      mw.country_name,
      mw.month_start,
      mw.payment_count,
      ROW_NUMBER() OVER (
        PARTITION BY mw.country_name, mw.month_start
        ORDER BY mw.payment_count
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY mw.country_name, mw.month_start
      ) AS cnt
    FROM monthly_with_history AS mw
    WHERE mw.payment_count IS NOT NULL
      AND mw.personal_avg_month_amount IS NOT NULL
  ) AS mwh
  WHERE rn IN (
      CAST((cnt + 1) / 2 AS INTEGER),
      CAST((cnt + 2) / 2 AS INTEGER)
  )
  GROUP BY
    mwh.country_name,
    mwh.month_start
),
action_new_amounts AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(CAST(p.p05 AS REAL)) AS action_new_amount
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN flc AS fc
    ON fc.l01 = i.n02
  JOIN cat AS ca
    ON ca.g01 = fc.l02
  WHERE ca.g02 IN ('Action', 'New')
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
sus_candidates AS (
  SELECT
    mwh.customer_id,
    mwh.month_start,
    mwh.store_id,
    mwh.country_name,
    mwh.city_name,
    mwh.payment_count,
    mwh.month_amount,
    mwh.max_single_payment,
    mwh.personal_avg_month_amount,
    cm.country_month_median_payment_count
  FROM monthly_with_history AS mwh
  JOIN country_month_median_payments AS cm
    ON cm.country_name = mwh.country_name
   AND cm.month_start = mwh.month_start
  WHERE mwh.personal_avg_month_amount > 0
    AND mwh.month_amount > 3.0 * mwh.personal_avg_month_amount
    AND mwh.payment_count > cm.country_month_median_payment_count
),
ranked_country AS (
  SELECT
    sc.*,
    RANK() OVER (
      PARTITION BY sc.country_name, sc.month_start
      ORDER BY sc.month_amount DESC
    ) AS country_month_amount_rank
  FROM sus_candidates AS sc
)
SELECT
  rc.country_name AS country,
  rc.city_name AS city,
  rc.store_id AS store_id,
  rc.month_start AS month,
  rc.payment_count,
  ROUND(rc.month_amount, 2) AS total_suspicious_amount,
  ROUND(rc.max_single_payment, 2) AS max_single_payment,
  ROUND(
    (CAST(COALESCE(ana.action_new_amount, 0.0) AS REAL) / NULLIF(rc.month_amount, 0.0)),
    4
  ) AS share_action_new_rental_amount,
  rc.country_month_amount_rank AS country_amount_rank
FROM ranked_country AS rc
LEFT JOIN action_new_amounts AS ana
  ON ana.customer_id = rc.customer_id
 AND ana.month_start = rc.month_start
ORDER BY
  rc.month_start,
  rc.country_name,
  rc.country_month_amount_rank,
  rc.customer_id;