WITH monthly_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS monthly_amount,
    COUNT(p.p01) AS monthly_payment_count
  FROM pay AS p
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
monthly_with_personal AS (
  SELECT
    mp.*,
    AVG(mp.monthly_amount) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_prev_amount
  FROM monthly_pay AS mp
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    ct.d03 AS country_id,
    cty.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS cty
    ON cty.d01 = a.e05
  JOIN cnt AS ct
    ON ct.c01 = cty.d03
),
monthly_country_median_count AS (
  SELECT
    mwp.month_start,
    mwp.customer_id,
    mwp.monthly_payment_count,
    (
      SELECT AVG(x.monthly_payment_count)
      FROM (
        SELECT
          mp2.monthly_payment_count,
          ROW_NUMBER() OVER (PARTITION BY mp2.month_start ORDER BY mp2.monthly_payment_count) AS rn,
          COUNT(*) OVER (PARTITION BY mp2.month_start) AS cnt
        FROM monthly_with_personal AS mp2
        JOIN customer_geo AS cg
          ON cg.customer_id = mp2.customer_id
      ) AS x
      WHERE x.rn IN (CAST((x.cnt + 1) / 2 AS INTEGER), CAST((x.cnt + 2) / 2 AS INTEGER))
    ) AS country_median_payment_count
  FROM monthly_with_personal AS mwp
  JOIN customer_geo AS cg
    ON cg.customer_id = mwp.customer_id
),
candidate_months AS (
  SELECT
    mwp.customer_id,
    mwp.month_start,
    mwp.monthly_amount,
    mwp.monthly_payment_count,
    mwp.personal_avg_prev_amount
  FROM monthly_with_personal AS mwp
  JOIN customer_geo AS cg
    ON cg.customer_id = mwp.customer_id
  WHERE mwp.personal_avg_prev_amount IS NOT NULL
    AND mwp.monthly_amount > 3.0 * mwp.personal_avg_prev_amount
),
ranked_candidates AS (
  SELECT
    cm.*,
    DENSE_RANK() OVER (
      PARTITION BY cg.country_id, cm.month_start
      ORDER BY cm.monthly_amount DESC
    ) AS country_month_customer_rank
  FROM candidate_months AS cm
  JOIN customer_geo AS cg
    ON cg.customer_id = cm.customer_id
),
cat_actions_new AS (
  SELECT g.g01, g.g02
  FROM cat AS g
  WHERE g.g02 IN ('Action', 'New')
),
film_category_flags AS (
  SELECT DISTINCT
    f.l01 AS film_id,
    1 AS is_action_or_new
  FROM flc AS f
  JOIN cat_actions_new AS cn
    ON cn.g01 = f.l02
),
category_payment_shares AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(p.p01) AS payment_count_total,
    SUM(p.p05) AS payment_sum_total,
    SUM(CASE WHEN fcf.is_action_or_new = 1 THEN 1 ELSE 0 END) AS payment_count_action_new,
    SUM(CASE WHEN fcf.is_action_or_new = 1 THEN p.p05 ELSE 0 END) AS payment_sum_action_new
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  LEFT JOIN film_category_flags AS fcf
    ON fcf.film_id = i.n02
  WHERE p.p06 >= '2005-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
)
SELECT
  rc.customer_id AS h01,
  cg.city_name AS city,
  cg.country_id AS country_id,
  cg.store_id AS store_id,
  rc.month_start AS month,
  cps.payment_count_total AS payment_count,
  ROUND(cps.payment_sum_total, 2) AS payment_sum,
  -- максимальный разовый платёж p05 за месяц
  (
    SELECT MAX(p2.p05)
    FROM pay AS p2
    WHERE p2.p02 = rc.customer_id
      AND date(p2.p06, 'start of month') = rc.month_start
  ) AS max_single_payment,
  cps.payment_count_action_new AS payment_count_action_new,
  ROUND(
    1.0 * cps.payment_count_action_new / NULLIF(cps.payment_count_total, 0),
    4
  ) AS action_new_payment_share_by_count,
  rc.country_month_customer_rank AS customer_rank_in_country_month
FROM ranked_candidates AS rc
JOIN customer_geo AS cg
  ON cg.customer_id = rc.customer_id
JOIN category_payment_shares AS cps
  ON cps.customer_id = rc.customer_id
 AND cps.month_start = rc.month_start
WHERE rc.monthly_payment_count >
  (
    SELECT COALESCE(MIN(country_median_payment_count), 0)
    FROM monthly_country_median_count
    WHERE month_start = rc.month_start
  )
ORDER BY
  cg.country_id,
  rc.month_start,
  rc.monthly_amount DESC,
  rc.customer_id;