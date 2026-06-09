WITH RECURSIVE months(month_start) AS (
  SELECT date('2005-01-01')
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < date('2005-12-01')
),
customer_base AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS home_store_id,
    cn.c02 AS country_name,
    ct.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a  ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS cn ON cn.c01 = ct.d03
),
monthly_payments AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS month_amount,
    MAX(CAST(p.p05 AS REAL)) AS max_single_payment
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
client_history AS (
  SELECT
    mp.*,
    AVG(mp.month_amount) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_historical_avg_month_amount,
    COUNT(*) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_hist_months_cnt
  FROM monthly_payments AS mp
),
country_month_medians AS (
  SELECT
    ch.month_start,
    ch.country_name,
    ch.payment_count,
    ch.month_amount,
    ch.customer_id,
    ch.personal_historical_avg_month_amount,
    ch.personal_hist_months_cnt,
    -- median of payment_count for the country & month
    CAST(
      (1 + (COUNT(*) OVER (PARTITION BY ch.country_name, ch.month_start) - 1) / 2)
      AS INTEGER
    ) AS median_pos_placeholder
  FROM (
    SELECT
      ch0.*,
      cb.country_name
    FROM client_history AS ch0
    JOIN customer_base AS cb
      ON cb.customer_id = ch0.customer_id
  ) AS ch
),
country_payment_count_ranked AS (
  SELECT
    cm.*,
    ROW_NUMBER() OVER (
      PARTITION BY cm.country_name, cm.month_start
      ORDER BY cm.payment_count
    ) AS rn_asc,
    COUNT(*) OVER (
      PARTITION BY cm.country_name, cm.month_start
    ) AS cnt_in_group
  FROM (
    SELECT
      cb.country_name,
      ch.month_start,
      ch.payment_count,
      ch.month_amount,
      ch.max_single_payment,
      ch.customer_id,
      ch.personal_historical_avg_month_amount,
      ch.personal_hist_months_cnt
    FROM (
      SELECT
        mp.*,
        AVG(mp.month_amount) OVER (
          PARTITION BY mp.customer_id
          ORDER BY mp.month_start
          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS personal_historical_avg_month_amount,
        COUNT(*) OVER (
          PARTITION BY mp.customer_id
          ORDER BY mp.month_start
          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS personal_hist_months_cnt
      FROM monthly_payments AS mp
    ) AS ch
    JOIN customer_base AS cb
      ON cb.customer_id = ch.customer_id
  ) AS cm
),
country_payment_count_median AS (
  SELECT
    country_name,
    month_start,
    MAX(CASE WHEN rn_asc = CAST((cnt_in_group + 1) / 2 AS INTEGER) THEN payment_count END) AS median_payment_count
  FROM country_payment_count_ranked
  GROUP BY
    country_name,
    month_start
),
flagged_customer_months AS (
  SELECT
    cpcm.country_name,
    cpcm.month_start,
    cpcm.customer_id,
    cpcm.payment_count,
    cpcm.month_amount,
    cpcm.max_single_payment,
    cpcm.personal_historical_avg_month_amount,
    cpcm.personal_hist_months_cnt,
    cpcm.median_payment_count
  FROM (
    SELECT
      cb.country_name,
      ch.month_start,
      ch.customer_id,
      ch.payment_count,
      ch.month_amount,
      ch.max_single_payment,
      ch.personal_historical_avg_month_amount,
      ch.personal_hist_months_cnt
    FROM client_history AS ch
    JOIN customer_base AS cb
      ON cb.customer_id = ch.customer_id
  ) AS cpcm
  JOIN country_payment_count_median AS med
    ON med.country_name = cpcm.country_name
   AND med.month_start = cpcm.month_start
  WHERE
    cpcm.personal_hist_months_cnt >= 1
    AND cpcm.personal_historical_avg_month_amount > 0
    AND cpcm.month_amount > 3.0 * cpcm.personal_historical_avg_month_amount
    AND cpcm.payment_count > med.median_payment_count
),
rent_amounts_by_category AS (
  -- Allocate rent payments to film categories via flm/inventory/rental
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(
      CASE
        WHEN cat.g02 IN ('Action','New') THEN CAST(p.p05 AS REAL)
        ELSE 0.0
      END
    ) AS amount_action_new,
    SUM(CAST(p.p05 AS REAL)) AS amount_all,
    COUNT(*) AS payment_count_all
  FROM pay AS p
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
  LEFT JOIN flm AS f
    ON f.i01 = i.n02
  LEFT JOIN flc AS fc
    ON fc.l01 = f.i01
  LEFT JOIN cat
    ON cat.g01 = fc.l02
  WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
final_monthly AS (
  SELECT
    fcm.country_name,
    cb.city_name,
    cb.home_store_id,
    fcm.month_start,
    fcm.customer_id,
    fcm.payment_count,
    ROUND(fcm.month_amount, 2) AS total_amount,
    ROUND(fcm.max_single_payment, 2) AS max_single_payment,
    -- share of payments in categories Action and New
    ROUND(
      COALESCE(rac.amount_action_new / NULLIF(rac.amount_all, 0), 0.0),
      4
    ) AS share_action_new
  FROM flagged_customer_months AS fcm
  JOIN customer_base AS cb
    ON cb.customer_id = fcm.customer_id
  LEFT JOIN rent_amounts_by_category AS rac
    ON rac.customer_id = fcm.customer_id
   AND rac.month_start = fcm.month_start
),
ranked_within_country AS (
  SELECT
    fm.*,
    DENSE_RANK() OVER (
      PARTITION BY fm.country_name
      ORDER BY fm.total_amount DESC
    ) AS country_customer_suspicious_rank
  FROM final_monthly AS fm
)
SELECT
  rcc.country_name AS country,
  rcc.city_name AS city,
  rcc.home_store_id AS store_id,
  strftime('%Y-%m', rcc.month_start) AS payment_month,
  rcc.customer_id,
  rcc.payment_count,
  rcc.total_amount,
  rcc.max_single_payment,
  rcc.share_action_new,
  rcc.country_customer_suspicious_rank
FROM ranked_within_country AS rcc
ORDER BY
  rcc.country_name,
  rcc.country_customer_suspicious_rank,
  rcc.total_amount DESC,
  rcc.customer_id;