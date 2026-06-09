WITH
monthly_client AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS month_total_amount,
    MAX(p.p05) AS max_payment_amount
  FROM pay AS p
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
customer_history AS (
  SELECT
    mc.*,
    AVG(mc.month_total_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_hist_avg_amount,
    COUNT(*) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_hist_months_count
  FROM monthly_client AS mc
),
country_median_count AS (
  SELECT
    customer_id,
    month_start,
    payment_count,
    country_id
  FROM (
    SELECT
      cc.customer_id,
      cc.month_start,
      cc.payment_count,
      cc.country_id,
      PERCENT_RANK() OVER (
        PARTITION BY cc.country_id, cc.month_start
        ORDER BY cc.payment_count
      ) AS pr
    FROM (
      SELECT
        mc.customer_id,
        mc.month_start,
        mc.payment_count,
        cnt.c01 AS country_id
      FROM monthly_client AS mc
      JOIN cus AS c
        ON c.h01 = mc.customer_id
      JOIN adr AS a
        ON a.e01 = c.h06
      JOIN cty AS city
        ON city.d01 = a.e05
      JOIN cnt
        ON cnt.c01 = city.d03
    ) AS cc
  )
),
customer_monthly_with_geo AS (
  SELECT
    ch.customer_id,
    ch.month_start,
    ch.payment_count,
    ch.month_total_amount,
    ch.max_payment_amount,
    c.h02 AS store_id,
    cnt.c02 AS country_name,
    city.d02 AS city_name,
    cnt.c01 AS country_id
  FROM customer_history AS ch
  JOIN cus AS c
    ON c.h01 = ch.customer_id
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS city
    ON city.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = city.d03
),
country_monthly_stats AS (
  SELECT
    cmwg.country_id,
    cmwg.month_start,
    -- медианный уровень: берём верхнюю медиану/середину через 50-й перцентиль методом row_number
    -- рассчитываем порог как payment_count значения с позициями ceil(n/2)
    MAX(CASE WHEN rn = ((cnt_n + 1) / 2) THEN payment_count END) AS median_payment_count
  FROM (
    SELECT
      cmwg.country_id,
      cmwg.month_start,
      cmwg.payment_count,
      ROW_NUMBER() OVER (
        PARTITION BY cmwg.country_id, cmwg.month_start
        ORDER BY cmwg.payment_count
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY cmwg.country_id, cmwg.month_start
      ) AS cnt_n
    FROM customer_monthly_with_geo AS cmwg
  ) AS x
  GROUP BY
    country_id,
    month_start
),
suspicious_months AS (
  SELECT
    cmwg.*,
    cms.median_payment_count,
    cmwg.month_total_amount - cmwg.personal_hist_avg_amount AS deviation_from_personal_avg
  FROM customer_monthly_with_geo AS cmwg
  LEFT JOIN country_monthly_stats AS cms
    ON cms.country_id = cmwg.country_id
   AND cms.month_start = cmwg.month_start
  JOIN customer_history AS ch
    ON ch.customer_id = cmwg.customer_id
   AND ch.month_start = cmwg.month_start
  WHERE ch.personal_hist_months_count >= 1
    AND ch.personal_hist_avg_amount > 0
    AND cmwg.month_total_amount > ch.personal_hist_avg_amount * 3
    AND cmwg.payment_count > cms.median_payment_count
),
top_suspicious_rank AS (
  SELECT
    sm.country_id,
    sm.customer_id,
    SUM(sm.month_total_amount) AS suspicious_total_amount,
    RANK() OVER (
      PARTITION BY sm.country_id
      ORDER BY SUM(sm.month_total_amount) DESC
    ) AS country_customer_suspicious_rank
  FROM suspicious_months AS sm
  GROUP BY
    sm.country_id,
    sm.customer_id
),
film_category_shares AS (
  SELECT
    sm.customer_id,
    sm.month_start,
    SUM(CASE WHEN cat.g02 = 'Action' THEN p.p05 ELSE 0 END) AS action_amount,
    SUM(CASE WHEN cat.g02 = 'New' THEN p.p05 ELSE 0 END) AS new_amount,
    SUM(p.p05) AS total_amount
  FROM suspicious_months AS sm
  JOIN pay AS p
    ON p.p02 = sm.customer_id
   AND date(p.p06, 'start of month') = sm.month_start
   AND p.p04 IS NOT NULL
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN flc AS fc
    ON fc.l01 = i.n02
  JOIN cat
    ON cat.g01 = fc.l02
  GROUP BY
    sm.customer_id,
    sm.month_start
)
SELECT
  sm.country_name AS country,
  sm.city_name AS city,
  sm.store_id AS store_id,
  sm.payment_count,
  ROUND(sm.month_total_amount, 2) AS month_total_amount,
  ROUND(sm.max_payment_amount, 2) AS max_payment_amount,
  ROUND(
    (
      (COALESCE(fcs.action_amount, 0) + COALESCE(fcs.new_amount, 0)) / NULLIF(fcs.total_amount, 0)
    ),
    4
  ) AS share_action_plus_new,
  tsr.country_customer_suspicious_rank
FROM suspicious_months AS sm
JOIN top_suspicious_rank AS tsr
  ON tsr.country_id = sm.country_id
 AND tsr.customer_id = sm.customer_id
LEFT JOIN film_category_shares AS fcs
  ON fcs.customer_id = sm.customer_id
 AND fcs.month_start = sm.month_start
ORDER BY
  sm.country_id,
  tsr.country_customer_suspicious_rank,
  sm.month_start,
  sm.month_total_amount DESC,
  sm.customer_id;