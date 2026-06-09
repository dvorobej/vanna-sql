WITH monthly_customer AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cn.c02 AS country_name,
    ct.d02 AS city_name,
    c.h02 AS home_store_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS month_total_amount,
    MAX(CAST(p.p05 AS REAL)) AS month_max_payment
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ct.d03
  GROUP BY
    c.h01, c.h03, c.h04,
    cn.c02, ct.d02,
    c.h02,
    date(p.p06, 'start of month')
),
customer_history AS (
  SELECT
    mc.*,
    AVG(mc.month_total_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_month_total_amount,
    AVG(mc.payment_count) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_month_payment_count
  FROM monthly_customer AS mc
),
country_month_median AS (
  SELECT
    customer_id,
    month_start,
    country_name,
    CASE
      WHEN rn = 1 THEN monthly_amount_sorted_value
    END AS dummy
  FROM (
    SELECT
      customer_id,
      month_start,
      country_name,
      monthly_amount,
      ROW_NUMBER() OVER (
        PARTITION BY country_name, month_start
        ORDER BY monthly_amount
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY country_name, month_start
      ) AS cnt,
      monthly_amount AS monthly_amount_sorted_value
    FROM (
      SELECT
        mc.customer_id,
        mc.month_start,
        mc.country_name,
        mc.month_total_amount AS monthly_amount
      FROM monthly_customer AS mc
    )
  )
  WHERE 1 = 1
),
country_month_medians AS (
  SELECT
    cm.country_name,
    cm.month_start,
    AVG(cm.month_total_amount) AS country_median_month_total_amount
  FROM (
    SELECT
      country_name,
      month_start,
      month_total_amount,
      ROW_NUMBER() OVER (
        PARTITION BY country_name, month_start
        ORDER BY month_total_amount
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY country_name, month_start
      ) AS cnt
    FROM monthly_customer
  ) cm
  WHERE rn IN (
    CAST((cnt + 1) / 2 AS INTEGER),
    CAST((cnt + 2) / 2 AS INTEGER)
  )
  GROUP BY cm.country_name, cm.month_start
),
qualifying_months AS (
  SELECT
    ch.*,
    cm.country_median_month_total_amount,
    (ch.month_total_amount - ch.personal_avg_month_total_amount) AS deviation_from_personal_avg_amount,
    RANK() OVER (
      PARTITION BY ch.country_name, ch.month_start
      ORDER BY ch.month_total_amount DESC
    ) AS suspicious_country_rank,
    COUNT(*) OVER (
      PARTITION BY ch.country_name, ch.month_start
    ) AS suspicious_country_count
  FROM customer_history AS ch
  JOIN country_month_medians AS cm
    ON cm.country_name = ch.country_name
   AND cm.month_start = ch.month_start
  WHERE ch.personal_avg_month_total_amount IS NOT NULL
    AND ch.personal_avg_month_payment_count IS NOT NULL
    AND ch.month_total_amount > 3.0 * ch.personal_avg_month_total_amount
    AND ch.payment_count > (
      SELECT
        AVG(m.payment_count)
      FROM monthly_customer AS m
      WHERE m.customer_id = ch.customer_id
        AND m.month_start < ch.month_start
    )
),
payment_category_shares AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(CASE WHEN ca.g02 = 'Action' THEN CAST(p.p05 AS REAL) ELSE 0 END) AS action_amount,
    SUM(CASE WHEN ca.g02 = 'New' THEN CAST(p.p05 AS REAL) ELSE 0 END) AS new_amount,
    SUM(CAST(p.p05 AS REAL)) AS total_amount
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN flc AS fc
    ON fc.l01 = i.n02
  JOIN cat AS ca
    ON ca.g01 = fc.l02
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
)
SELECT
  qm.customer_id,
  qm.first_name,
  qm.last_name,
  qm.country_name AS country,
  qm.city_name AS city,
  qm.home_store_id AS store_id,
  qm.payment_count,
  ROUND(qm.month_total_amount, 2) AS total_amount,
  ROUND(qm.month_max_payment, 2) AS max_payment,
  ROUND(
    COALESCE(pcs.action_amount, 0) / NULLIF(pcs.total_amount, 0),
    4
  ) AS action_category_payment_share,
  ROUND(
    COALESCE(pcs.new_amount, 0) / NULLIF(pcs.total_amount, 0),
    4
  ) AS new_category_payment_share,
  qm.suspicious_country_rank AS suspicious_country_rank,
  qm.suspicious_country_count
FROM qualifying_months AS qm
LEFT JOIN payment_category_shares AS pcs
  ON pcs.customer_id = qm.customer_id
 AND pcs.month_start = qm.month_start
ORDER BY
  qm.country_name,
  qm.month_start,
  qm.month_total_amount DESC,
  qm.customer_id;