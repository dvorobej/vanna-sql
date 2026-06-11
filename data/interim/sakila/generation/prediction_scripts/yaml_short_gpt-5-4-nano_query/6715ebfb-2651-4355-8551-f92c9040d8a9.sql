WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    co.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
),
month_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS month_amount,
    MAX(CAST(p.p05 AS REAL)) AS max_single_payment
  FROM pay AS p
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
customer_hist AS (
  SELECT
    mp.*,
    AVG(mp.month_amount) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_amount_prev,
    AVG(mp.payment_count * 1.0) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_count_prev
  FROM month_pay AS mp
),
country_month_counts AS (
  SELECT
    mp.month_start,
    cg.country_name,
    mp.payment_count,
    PERCENT_RANK() OVER (
      PARTITION BY cg.country_name, mp.month_start
      ORDER BY mp.payment_count
    ) AS pr_payment_count
  FROM month_pay AS mp
  JOIN customer_geo AS cg ON cg.customer_id = mp.customer_id
),
country_month_median_count AS (
  SELECT
    month_start,
    country_name,
    AVG(payment_count * 1.0) AS median_payment_count
  FROM (
    SELECT
      cmc.*,
      ROW_NUMBER() OVER (
        PARTITION BY cmc.country_name, cmc.month_start
        ORDER BY cmc.payment_count
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY cmc.country_name, cmc.month_start
      ) AS cnt
    FROM country_month_counts AS cmc
  ) x
  WHERE rn IN (CAST((cnt + 1) / 2 AS INTEGER), CAST((cnt + 2) / 2 AS INTEGER))
  GROUP BY month_start, country_name
),
action_new_shares AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(CASE WHEN cat.g02 IN ('Action', 'New') THEN CAST(p.p05 AS REAL) ELSE 0 END) AS action_new_amount,
    SUM(CAST(p.p05 AS REAL)) AS month_amount_for_share
  FROM pay AS p
  JOIN ren r ON r.q01 = p.p04
  JOIN inv i ON i.n01 = r.q03
  JOIN flc fc ON fc.l01 = i.n02
  JOIN cat ON cat.g01 = fc.l02
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
suspicious_months AS (
  SELECT
    ch.customer_id,
    cg.country_name,
    cg.city_name,
    ch.month_start,
    ch.payment_count,
    ch.month_amount,
    ch.max_single_payment,
    ch.personal_avg_amount_prev,
    (ch.month_amount - ch.personal_avg_amount_prev) AS deviation_from_personal_avg,
    cm_med.median_payment_count,
    CASE
      WHEN ch.payment_count > cm_med.median_payment_count THEN 1 ELSE 0
    END AS is_count_above_median
  FROM customer_hist AS ch
  JOIN customer_geo AS cg
    ON cg.customer_id = ch.customer_id
  JOIN country_month_median_count AS cm_med
    ON cm_med.country_name = cg.country_name
   AND cm_med.month_start = ch.month_start
  WHERE ch.personal_avg_amount_prev IS NOT NULL
    AND ch.personal_avg_amount_prev > 0
    AND ch.month_amount > ch.personal_avg_amount_prev * 3.0
    AND ch.payment_count > cm_med.median_payment_count
),
country_month_suspicious_rank AS (
  SELECT
    sm.*,
    RANK() OVER (
      PARTITION BY sm.country_name, sm.month_start
      ORDER BY sm.month_amount DESC
    ) AS country_month_amount_rank
  FROM suspicious_months AS sm
)
SELECT
  r.country_name,
  r.city_name,
  c.h02 AS store_id,
  r.month_start AS payment_month,
  r.payment_count,
  ROUND(r.month_amount, 2) AS total_suspicious_amount,
  ROUND(r.max_single_payment, 2) AS max_single_payment,
  ROUND(
    (ans.action_new_amount / NULLIF(ans.month_amount_for_share, 0)) * 100.0,
    2
  ) AS action_new_payment_share_percent,
  r.country_month_amount_rank
FROM country_month_suspicious_rank AS r
JOIN cus c ON c.h01 = r.customer_id
LEFT JOIN action_new_shares ans
  ON ans.customer_id = r.customer_id
 AND ans.month_start = r.month_start
ORDER BY
  r.country_name,
  r.month_start,
  r.country_month_amount_rank,
  r.month_amount DESC;