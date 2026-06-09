WITH july_all_months AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount
  FROM pay AS p
),
monthly_customer AS (
  SELECT
    p.customer_id,
    p.month_start,
    COUNT(*) AS payment_count,
    SUM(p.payment_amount) AS month_total_amount,
    MAX(p.payment_amount) AS max_payment_amount
  FROM july_all_months AS p
  GROUP BY
    p.customer_id,
    p.month_start
),
customer_country AS (
  SELECT
    c.h01 AS customer_id,
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
customer_home_store AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS home_store_id
  FROM cus AS c
),
customer_history AS (
  SELECT
    mc.customer_id,
    mc.month_start,
    mc.payment_count,
    mc.month_total_amount,
    mc.max_payment_amount,
    AVG(mc.month_total_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_month_amount,
    AVG(mc.payment_count) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_month_payment_count,
    COUNT(*) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_prev_months_cnt
  FROM monthly_customer AS mc
),
country_month_medians AS (
  -- медиана по стране для "числа платежей" в каждом месяце
  SELECT
    x.country_name,
    x.month_start,
    AVG(x.payment_count) AS country_median_payment_count
  FROM (
    SELECT
      cc.country_name,
      mc.customer_id,
      mc.month_start,
      mc.payment_count,
      ROW_NUMBER() OVER (
        PARTITION BY cc.country_name, mc.month_start
        ORDER BY mc.payment_count
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY cc.country_name, mc.month_start
      ) AS cnt
    FROM monthly_customer AS mc
    JOIN customer_country AS cc
      ON cc.customer_id = mc.customer_id
  ) AS x
  WHERE x.rn IN (
    CAST((x.cnt + 1) / 2 AS INTEGER),
    CAST((x.cnt + 2) / 2 AS INTEGER)
  )
  GROUP BY
    x.country_name,
    x.month_start
),
action_new_share AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(
      CASE
        WHEN ca.g02 IN ('Action','New') THEN 1
        ELSE 0
      END
    ) * 1.0 / COUNT(*) AS action_new_payment_share
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN flc AS fc
    ON fc.l01 = i.n02
  JOIN cat AS ca
    ON ca.g01 = fc.l02
  WHERE p.p06 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
suspicious_rank AS (
  -- место клиента по сумме подозрительных платежей внутри страны и месяца
  SELECT
    cc.country_name,
    mc.month_start,
    mc.customer_id,
    RANK() OVER (
      PARTITION BY cc.country_name, mc.month_start
      ORDER BY mc.month_total_amount DESC
    ) AS country_month_suspicious_rank
  FROM monthly_customer AS mc
  JOIN customer_country AS cc
    ON cc.customer_id = mc.customer_id
)
SELECT
  ch.customer_id,
  ch.month_start AS month,
  cc.country_name AS country,
  cc.city_name AS city,
  ch.payment_count AS payment_count,
  ROUND(ch.month_total_amount, 2) AS month_total_amount,
  ROUND(ch.max_payment_amount, 2) AS max_payment_amount,
  ROUND(
    (ch.month_total_amount / NULLIF(ch.personal_avg_month_amount, 0)) - 1,
    4
  ) AS deviation_from_personal_avg,
  ROUND(
    CASE
      WHEN cm.country_median_payment_count IS NOT NULL AND cm.country_median_payment_count > 0
      THEN ch.payment_count * 1.0 / cm.country_median_payment_count
      ELSE NULL
    END,
    4
  ) AS payment_count_vs_country_median_ratio,
  COALESCE(ans.action_new_payment_share, 0.0) AS action_new_payment_share,
  sr.country_month_suspicious_rank AS country_rank_by_suspicious_sum
FROM customer_history AS ch
JOIN customer_country AS cc
  ON cc.customer_id = ch.customer_id
JOIN country_month_medians AS cm
  ON cm.country_name = cc.country_name
 AND cm.month_start = ch.month_start
LEFT JOIN action_new_share AS ans
  ON ans.customer_id = ch.customer_id
 AND ans.month_start = ch.month_start
JOIN suspicious_rank AS sr
  ON sr.customer_id = ch.customer_id
 AND sr.month_start = ch.month_start
 AND sr.country_name = cc.country_name
WHERE ch.personal_prev_months_cnt >= 2
  AND ch.personal_avg_month_amount IS NOT NULL
  AND cm.country_median_payment_count IS NOT NULL
  AND ch.month_total_amount > 1.5 * ch.personal_avg_month_amount
  AND ch.payment_count > cm.country_median_payment_count
ORDER BY
  ch.month_start,
  cc.country_name,
  sr.country_month_suspicious_rank,
  ch.month_total_amount DESC,
  ch.customer_id;