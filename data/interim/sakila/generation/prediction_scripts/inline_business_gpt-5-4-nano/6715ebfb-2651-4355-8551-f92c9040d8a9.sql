WITH monthly_customer AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    s.j01 AS home_store_id,
    cn.c01 AS country_id,
    cn.c02 AS country_name,
    ct.d01 AS city_id,
    ct.d02 AS city_name,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS month_total_amount,
    MAX(CAST(p.p05 AS REAL)) AS max_single_payment
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ct.d03
  LEFT JOIN sto AS s
    ON s.j01 = c.h02
  WHERE p.p06 IS NOT NULL
  GROUP BY
    c.h01,
    c.h03,
    c.h04,
    s.j01,
    cn.c01,
    cn.c02,
    ct.d01,
    ct.d02,
    date(p.p06, 'start of month')
),
customer_monthly_with_personal AS (
  SELECT
    mc.*,
    AVG(mc.month_total_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_month_total_amount,
    AVG(mc.payment_count * 1.0) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_payment_count
  FROM monthly_customer AS mc
),
country_monthly_median AS (
  SELECT
    mc.country_id,
    mc.month_start,
    AVG(mc2.month_payment_count_median) AS country_median_payment_count
  FROM (
    SELECT
      country_id,
      month_start,
      payment_count AS month_payment_count_median,
      ROW_NUMBER() OVER (
        PARTITION BY country_id, month_start
        ORDER BY payment_count
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY country_id, month_start
      ) AS cnt
    FROM monthly_customer
  ) AS mc2
  JOIN (
    SELECT DISTINCT country_id, month_start
    FROM monthly_customer
  ) AS mc
    ON mc.country_id = mc2.country_id
   AND mc.month_start = mc2.month_start
  WHERE mc2.rn IN (
    CAST((mc2.cnt + 1) / 2 AS INTEGER),
    CAST((mc2.cnt + 2) / 2 AS INTEGER)
  )
  GROUP BY
    mc.country_id,
    mc.month_start
),
suspicious_months AS (
  SELECT
    cm.customer_id,
    cm.first_name,
    cm.last_name,
    cm.home_store_id,
    cm.country_id,
    cm.country_name,
    cm.city_id,
    cm.city_name,
    cm.month_start,
    cm.payment_count,
    cm.month_total_amount,
    cm.max_single_payment,
    cm.personal_avg_month_total_amount,
    cm.personal_avg_payment_count,
    cmm.country_median_payment_count
  FROM customer_monthly_with_personal AS cm
  LEFT JOIN country_monthly_median AS cmm
    ON cmm.country_id = cm.country_id
   AND cmm.month_start = cm.month_start
  WHERE
    cm.personal_avg_month_total_amount IS NOT NULL
    AND cm.personal_avg_month_total_amount > 0
    AND cm.month_total_amount > 3.0 * cm.personal_avg_month_total_amount
    AND cmm.country_median_payment_count IS NOT NULL
    AND cm.payment_count > cmm.country_median_payment_count
),
action_new_shares AS (
  SELECT
    sm.customer_id,
    sm.month_start,
    SUM(CASE WHEN cat.g02 IN ('Action', 'New') THEN CAST(p.p05 AS REAL) ELSE 0 END) AS action_new_amount,
    SUM(CAST(p.p05 AS REAL)) AS month_amount
  FROM suspicious_months AS sm
  JOIN pay AS p
    ON p.p02 = sm.customer_id
   AND date(p.p06, 'start of month') = sm.month_start
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN flc AS l
    ON l.l01 = i.n02
  JOIN cat
    ON cat.g01 = l.l02
  WHERE p.p06 IS NOT NULL
  GROUP BY
    sm.customer_id,
    sm.month_start
),
suspicious_store_ranking AS (
  SELECT
    sm.customer_id,
    sm.month_start,
    sm.country_id,
    RANK() OVER (
      PARTITION BY sm.country_id, sm.month_start
      ORDER BY sm.month_total_amount DESC
    ) AS country_month_amount_rank
  FROM suspicious_months AS sm
),
top_store_in_month AS (
  SELECT
    sm.customer_id,
    sm.month_start,
    sm.country_id,
    st2.j01 AS servicing_store_id,
    ROW_NUMBER() OVER (
      PARTITION BY sm.customer_id, sm.month_start
      ORDER BY SUM(CAST(p.p05 AS REAL)) DESC, COUNT(*) DESC, st2.j01
    ) AS rn
  FROM suspicious_months AS sm
  JOIN pay AS p
    ON p.p02 = sm.customer_id
   AND date(p.p06, 'start of month') = sm.month_start
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN sto AS st2
    ON st2.j01 = i.n03
  GROUP BY
    sm.customer_id,
    sm.month_start,
    sm.country_id,
    st2.j01
)
SELECT
  sm.customer_id,
  sm.first_name,
  sm.last_name,
  sm.country_name AS country,
  sm.city_name AS city,
  tsim.servicing_store_id AS servicing_store_id,
  sm.payment_count,
  ROUND(sm.month_total_amount, 2) AS month_total_amount,
  ROUND(sm.max_single_payment, 2) AS max_single_payment,
  ROUND(
    1.0 * COALESCE(ans.action_new_amount, 0) / NULLIF(ans.month_amount, 0),
    4
  ) AS action_new_payment_share,
  sr.country_month_amount_rank
FROM suspicious_months AS sm
JOIN suspicious_store_ranking AS sr
  ON sr.customer_id = sm.customer_id
 AND sr.month_start = sm.month_start
 AND sr.country_id = sm.country_id
LEFT JOIN action_new_shares AS ans
  ON ans.customer_id = sm.customer_id
 AND ans.month_start = sm.month_start
JOIN top_store_in_month AS tsim
  ON tsim.customer_id = sm.customer_id
 AND tsim.month_start = sm.month_start
 AND tsim.rn = 1
ORDER BY
  sm.month_start,
  sm.country_name,
  sr.country_month_amount_rank,
  sm.month_total_amount DESC,
  sm.customer_id;