WITH monthly_customer_payment AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS month_payment_sum
  FROM pay AS p
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
customer_history AS (
  SELECT
    mcp.*,
    AVG(mcp.month_payment_sum) OVER (
      PARTITION BY mcp.customer_id
      ORDER BY mcp.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_avg_payment_sum,
    COUNT(*) OVER (
      PARTITION BY mcp.customer_id
      ORDER BY mcp.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_count
  FROM monthly_customer_payment AS mcp
),
month_level AS (
  SELECT
    ch.customer_id,
    ch.month_start,
    ch.month_payment_sum,
    ch.payment_count,
    ch.prev_months_avg_payment_sum
  FROM customer_history AS ch
  WHERE ch.prev_months_count >= 1
),
payment_flags AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p05 AS payment_amount,
    p.p01 AS payment_id,
    p.p04 AS rental_id,
    s.o07 AS staff_store_id,
    inv2.n03 AS film_store_id,
    cust_store.j01 AS customer_store_id,
    CASE
      WHEN cust_store.j01 IS NULL OR inv2.n03 IS NULL THEN 1
      WHEN cust_store.j01 <> inv2.n03 THEN 1
      ELSE 0
    END AS is_foreign_store
  FROM pay AS p
  JOIN ren AS r ON r.q01 = p.p04
  JOIN stf AS s ON s.o01 = p.p03
  JOIN inv AS inv2 ON inv2.n01 = r.q03
  JOIN cus AS c ON c.h01 = p.p02
  LEFT JOIN adr AS cust_adr ON cust_adr.e01 = c.h06
  LEFT JOIN sto AS cust_store ON cust_store.j01 = c.h02
),
month_foreign_share AS (
  SELECT
    pf.customer_id,
    pf.month_start,
    SUM(CASE WHEN pf.is_foreign_store = 1 THEN 1 ELSE 0 END) AS foreign_payment_count,
    COUNT(*) AS payment_count
  FROM payment_flags AS pf
  GROUP BY
    pf.customer_id,
    pf.month_start
),
month_top_staff_rank AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_payment_sum,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC, p.p03
    ) AS rn
  FROM pay AS p
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    p.p03
),
month_customer_top_staff AS (
  SELECT
    mts.customer_id,
    mts.month_start,
    mts.staff_id
  FROM month_top_staff_rank AS mts
  WHERE mts.rn = 1
),
month_client_rank AS (
  SELECT
    mcp.customer_id,
    mcp.month_start,
    RANK() OVER (
      PARTITION BY mcp.month_start
      ORDER BY mcp.month_payment_sum DESC
    ) AS month_rank_within_client
  FROM monthly_customer_payment AS mcp
),
month_categories_top AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    fc.l02 AS category_id,
    COUNT(*) AS category_payment_count,
    SUM(p.p05) AS category_payment_sum
  FROM pay AS p
  JOIN ren r ON r.q01 = p.p04
  JOIN inv i ON i.n01 = r.q03
  JOIN flc fc ON fc.l01 = i.n02
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    fc.l02
),
categories_ranked AS (
  SELECT
    mct.customer_id,
    mct.month_start,
    mct.category_id,
    mct.category_payment_sum,
    mct.category_payment_count,
    SUM(mct.category_payment_sum) OVER (
      PARTITION BY mct.customer_id, mct.month_start
    ) AS month_total_amount,
    SUM(mct.category_payment_sum) OVER (
      PARTITION BY mct.customer_id, mct.month_start
      ORDER BY mct.category_payment_sum DESC, mct.category_id
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_amount
  FROM month_categories_top AS mct
),
categories_main AS (
  SELECT
    cr.customer_id,
    cr.month_start,
    cr.category_id,
    cr.category_payment_sum
  FROM categories_ranked AS cr
  WHERE cr.month_total_amount > 0
    AND (cr.running_amount * 1.0 / cr.month_total_amount) <= 0.8
),
categories_list AS (
  SELECT
    cm.customer_id,
    cm.month_start,
    GROUP_CONCAT(cm.category_id, ', ') AS category_ids_main_part
  FROM (
    SELECT DISTINCT customer_id, month_start, category_id
    FROM categories_main
  ) AS cm
  GROUP BY
    cm.customer_id,
    cm.month_start
)
SELECT
  ml.month_start AS month,
  ml.customer_id,
  cus.h03 || ' ' || cus.h04 AS customer_name,
  ROUND(ml.month_payment_sum, 2) AS month_payment_sum,
  ml.payment_count,
  ROUND(1.0 * mfs.foreign_payment_count / NULLIF(mfs.payment_count, 0), 4) AS foreign_store_payment_share,
  ROUND((
    SELECT MAX(p2.p05)
    FROM pay p2
    WHERE p2.p02 = ml.customer_id
      AND date(p2.p06, 'start of month') = ml.month_start
      AND p2.p04 IS NOT NULL
  ), 2) AS max_single_payment,
  mcr.month_rank_within_client AS month_rank_within_client,
  COALESCE(cl.category_ids_main_part, '') AS top_category_ids_main_part
FROM month_level AS ml
JOIN cus ON cus.h01 = ml.customer_id
JOIN month_foreign_share AS mfs
  ON mfs.customer_id = ml.customer_id
 AND mfs.month_start = ml.month_start
JOIN month_client_rank AS mcr
  ON mcr.customer_id = ml.customer_id
 AND mcr.month_start = ml.month_start
LEFT JOIN categories_list AS cl
  ON cl.customer_id = ml.customer_id
 AND cl.month_start = ml.month_start
WHERE
  ml.payment_count >= 5
  AND ml.prev_months_avg_payment_sum > 0
  AND ml.month_payment_sum > 3.0 * ml.prev_months_avg_payment_sum
ORDER BY
  ml.month_start,
  ml.customer_id;