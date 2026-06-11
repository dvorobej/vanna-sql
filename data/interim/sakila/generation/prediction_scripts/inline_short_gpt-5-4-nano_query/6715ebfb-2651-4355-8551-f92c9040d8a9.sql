WITH RECURSIVE months(month_start) AS (
  SELECT date('2004-01-01')
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < date('2005-12-01')
),
payment_months AS (
  SELECT
    p.p02 AS customer_id,
    c.h02 AS store_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS month_amount,
    MAX(CAST(p.p05 AS REAL)) AS max_single_payment
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  WHERE p.p06 IS NOT NULL
  GROUP BY
    p.p02,
    c.h02,
    date(p.p06, 'start of month')
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    co.c01 AS country_id,
    co.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
),
monthly_with_history AS (
  SELECT
    pm.*,
    cg.country_id,
    cg.country_name,
    cg.city_name,
    AVG(pm.month_amount) OVER (
      PARTITION BY pm.customer_id
      ORDER BY pm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_hist_avg_amount,
    COUNT(*) OVER (
      PARTITION BY pm.customer_id
      ORDER BY pm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_hist_months_count
  FROM payment_months AS pm
  JOIN customer_geo AS cg
    ON cg.customer_id = pm.customer_id
),
country_month_paycount_distribution AS (
  SELECT
    mwh.country_id,
    mwh.month_start,
    mwh.customer_id,
    mwh.payment_count,
    ROW_NUMBER() OVER (
      PARTITION BY mwh.country_id, mwh.month_start
      ORDER BY mwh.payment_count
    ) AS rn,
    COUNT(*) OVER (
      PARTITION BY mwh.country_id, mwh.month_start
    ) AS cnt
  FROM monthly_with_history AS mwh
),
country_month_median_paycount AS (
  SELECT
    country_id,
    month_start,
    AVG(1.0 * payment_count) AS median_payment_count
  FROM country_month_paycount_distribution
  WHERE rn IN (
    CAST((cnt + 1) / 2 AS INTEGER),
    CAST((cnt + 2) / 2 AS INTEGER)
  )
  GROUP BY
    country_id,
    month_start
),
action_new_payment_shares AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(CASE
          WHEN cat.g02 IN ('Action', 'New') THEN 1
          ELSE 0
        END) * 1.0 / COUNT(*) AS action_new_rent_share
  FROM pay AS p
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
  LEFT JOIN flc AS fc
    ON fc.l01 = i.n02
  LEFT JOIN cat AS cat
    ON cat.g01 = fc.l02
  WHERE p.p06 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
suspected AS (
  SELECT
    mwh.customer_id,
    mwh.store_id,
    mwh.country_id,
    mwh.country_name,
    mwh.city_name,
    mwh.month_start,
    mwh.payment_count,
    mwh.month_amount,
    mwh.max_single_payment,
    mwh.personal_hist_avg_amount,
    mn.median_payment_count,
    ans.action_new_rent_share
  FROM monthly_with_history AS mwh
  JOIN country_month_median_paycount AS mn
    ON mn.country_id = mwh.country_id
   AND mn.month_start = mwh.month_start
  LEFT JOIN action_new_payment_shares AS ans
    ON ans.customer_id = mwh.customer_id
   AND ans.month_start = mwh.month_start
  WHERE mwh.personal_hist_avg_amount IS NOT NULL
    AND mwh.personal_hist_avg_amount > 0
    AND mwh.month_amount > 3.0 * mwh.personal_hist_avg_amount
    AND mwh.payment_count > mn.median_payment_count
),
ranked AS (
  SELECT
    s.*,
    RANK() OVER (
      PARTITION BY s.country_id
      ORDER BY s.month_amount DESC
    ) AS suspicious_customer_rank_in_country
  FROM suspected AS s
)
SELECT
  ranked.country_name AS country,
  ranked.city_name AS city,
  ranked.store_id AS store,
  ranked.customer_id,
  ranked.month_start AS payment_month,
  ranked.payment_count,
  ROUND(ranked.month_amount, 2) AS total_suspicious_amount,
  ROUND(ranked.max_single_payment, 2) AS max_single_payment,
  ROUND(ranked.action_new_rent_share, 4) AS action_new_rent_payments_share,
  ranked.suspicious_customer_rank_in_country AS customer_rank_in_country
FROM ranked
ORDER BY
  ranked.payment_month,
  ranked.country_name,
  ranked.suspicious_customer_rank_in_country,
  ranked.month_amount DESC,
  ranked.customer_id;