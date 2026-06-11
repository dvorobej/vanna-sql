WITH
pay_month AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    p.p05 AS payment_amount,
    p.p06 AS payment_ts,
    date(p.p06, 'start of month') AS month_start
  FROM pay AS p
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS customer_store_id,
    cn.c01 AS country_id
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ci.d03
),
monthly_client AS (
  SELECT
    pm.customer_id,
    cg.customer_store_id,
    cg.country_id,
    pm.month_start,
    COUNT(*) AS payment_count,
    SUM(pm.payment_amount) AS monthly_amount
  FROM pay_month AS pm
  JOIN customer_geo AS cg
    ON cg.customer_id = pm.customer_id
  GROUP BY
    pm.customer_id,
    cg.customer_store_id,
    cg.country_id,
    pm.month_start
),
client_with_history AS (
  SELECT
    mc.*,
    AVG(mc.monthly_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS rolling_avg_prev2_amount
  FROM monthly_client AS mc
),
country_month_values AS (
  SELECT
    mc.country_id,
    mc.month_start,
    mc.monthly_amount
  FROM monthly_client AS mc
),
country_month_p95 AS (
  /* Псевдо-95-й перцентиль по ранжированию в группе (SQLite-совместимо) */
  SELECT
    cm.country_id,
    cm.month_start,
    MAX(CASE WHEN cm.rn = cm.pos THEN cm.monthly_amount END) AS p95_value
  FROM (
    SELECT
      cmv.country_id,
      cmv.month_start,
      cmv.monthly_amount,
      ROW_NUMBER() OVER (
        PARTITION BY cmv.country_id, cmv.month_start
        ORDER BY cmv.monthly_amount
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY cmv.country_id, cmv.month_start
      ) AS cnt,
      CAST(0.95 * (COUNT(*) OVER (
        PARTITION BY cmv.country_id, cmv.month_start
      )) AS INTEGER) AS pos
    FROM country_month_values AS cmv
  ) AS cm
  GROUP BY
    cm.country_id,
    cm.month_start
),
monthly_filtered AS (
  SELECT
    ch.*,
    cp95.p95_value AS country_month_p95
  FROM client_with_history AS ch
  JOIN country_month_p95 AS cp95
    ON cp95.country_id = ch.country_id
   AND cp95.month_start = ch.month_start
  WHERE ch.rolling_avg_prev2_amount IS NOT NULL
    AND ch.monthly_amount >= 3.0 * ch.rolling_avg_prev2_amount
    AND ch.monthly_amount > cp95.p95_value
),
monthly_staff_stats AS (
  SELECT
    pm.customer_id,
    pm.month_start,
    /* доля платежей, где staff из другого магазина, чем customer.h02 */
    SUM(CASE WHEN st.j01 <> cg.customer_store_id THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_store_payment_share,
    COUNT(DISTINCT pm.staff_id) AS distinct_staff_count,
    /* сумма для позднего расчёта ранга */
    SUM(pm.payment_amount) AS monthly_amount_check
  FROM pay_month AS pm
  JOIN customer_geo AS cg
    ON cg.customer_id = pm.customer_id
  JOIN stf AS sf
    ON sf.o01 = pm.staff_id
  JOIN sto AS st
    ON st.j01 = sf.o07
  GROUP BY
    pm.customer_id,
    pm.month_start
),
monthly_rank_within_country AS (
  SELECT
    mf.customer_id,
    mf.month_start,
    RANK() OVER (
      PARTITION BY mf.country_id, mf.month_start
      ORDER BY mf.monthly_amount DESC
    ) AS customer_country_month_rank
  FROM monthly_filtered AS mf
)
SELECT
  mf.customer_id AS h01,
  /* страна/контекст */
  mf.country_id,
  mf.month_start AS month,
  mf.payment_count,
  ROUND(mf.monthly_amount, 2) AS monthly_amount,
  ROUND(mf.rolling_avg_prev2_amount, 2) AS rolling_avg_prev2_amount,
  ROUND((mf.monthly_amount - mf.rolling_avg_prev2_amount * 1.0) , 2) AS deviation_from_prev2_avg,
  ROUND(ms.off_store_payment_share, 4) AS off_store_payment_share,
  ms.distinct_staff_count,
  rnk.customer_country_month_rank
FROM monthly_filtered AS mf
JOIN monthly_staff_stats AS ms
  ON ms.customer_id = mf.customer_id
 AND ms.month_start = mf.month_start
JOIN monthly_rank_within_country AS rnk
  ON rnk.customer_id = mf.customer_id
 AND rnk.month_start = mf.month_start
ORDER BY
  mf.month_start,
  mf.country_id,
  mf.monthly_amount DESC,
  mf.customer_id;