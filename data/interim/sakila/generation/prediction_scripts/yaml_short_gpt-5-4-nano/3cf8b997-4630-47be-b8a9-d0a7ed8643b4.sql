WITH
monthly_by_store_customer AS (
  SELECT
    r.q01 AS rental_id,
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    date(p.p06,'start of month') AS month_start,
    s2.j01 AS store_id,
    SUM(p.p05) AS month_amount,
    COUNT(*) AS payment_count
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN sto AS s2
    ON s2.j01 = i.n03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06,'start of month'),
    s2.j01,
    r.q01,
    p.p01
),
monthly AS (
  SELECT
    customer_id,
    month_start,
    store_id,
    month_amount,
    payment_count,
    LAG(month_amount, 1) OVER (
      PARTITION BY customer_id, store_id
      ORDER BY month_start
    ) AS prev1_amount,
    LAG(month_amount, 2) OVER (
      PARTITION BY customer_id, store_id
      ORDER BY month_start
    ) AS prev2_amount
  FROM (
    SELECT
      p.p02 AS customer_id,
      date(p.p06,'start of month') AS month_start,
      i.n03 AS store_id,
      SUM(p.p05) AS month_amount,
      COUNT(*) AS payment_count
    FROM pay AS p
    JOIN ren AS r
      ON r.q01 = p.p04
    JOIN inv AS i
      ON i.n01 = r.q03
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
    GROUP BY
      p.p02,
      date(p.p06,'start of month'),
      i.n03
  ) x
),
qualified AS (
  SELECT
    m.*,
    ((prev1_amount + prev2_amount) / 2.0) AS prev2_month_avg,
    CASE
      WHEN (prev1_amount + prev2_amount) = 0 THEN NULL
      ELSE month_amount / ((prev1_amount + prev2_amount) / 2.0)
    END AS ratio_vs_prev_avg
  FROM monthly AS m
  WHERE payment_count >= 3
),
month_flags AS (
  SELECT
    q.*,
    (prev2_month_avg IS NOT NULL AND month_amount >= 2 * prev2_month_avg) AS is_alert_month
  FROM qualified AS q
),
store_month_rank AS (
  SELECT
    mf.*,
    PERCENT_RANK() OVER (
      PARTITION BY store_id, month_start
      ORDER BY month_amount
    ) AS pr
  FROM month_flags AS mf
),
sus_store_month AS (
  -- выбираем месяцы для магазинов, попадающие в верхние 10% подозрительных сумм
  SELECT
    *
  FROM store_month_rank
  WHERE pr >= 0.90
),
customers_who_fit_all_months AS (
  -- клиенты, для которых в КАЖДОМ месяце 2005, начиная с третьего (т.к. нужны предыдущие 2),
  -- выполняется условие >= 2x от среднего двух предыдущих месяцев
  SELECT
    store_id,
    customer_id
  FROM sus_store_month
  GROUP BY store_id, customer_id
  HAVING
    SUM(CASE WHEN is_alert_month = 1 THEN 1 ELSE 0 END) = COUNT(*)  -- только из отобранных подозрительных месяцев
),
final_months AS (
  SELECT
    smm.*
  FROM sus_store_month AS smm
  JOIN customers_who_fit_all_months AS cwa
    ON cwa.store_id = smm.store_id
   AND cwa.customer_id = smm.customer_id
),
top_staff_per_month AS (
  SELECT
    r.q01 AS rental_id,
    p.p02 AS customer_id,
    i.n03 AS store_id,
    date(p.p06,'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_amount,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, i.n03, date(p.p06,'start of month')
      ORDER BY SUM(p.p05) DESC, p.p03
    ) AS rn
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    i.n03,
    date(p.p06,'start of month'),
    p.p03,
    r.q01
)
SELECT
  fs.store_id,
  st.j02 AS store_address_city,
  st.j03 AS store_address_country,
  strftime('%Y-%m', fs.month_start) AS month,
  ROUND(fs.month_amount, 2) AS month_amount,
  fs.payment_count,
  ROUND(fs.month_amount - fs.prev2_month_avg, 2) AS deviation_from_prev_avg,
  RANK() OVER (
    PARTITION BY fs.store_id, fs.month_start
    ORDER BY fs.month_amount DESC
  ) AS month_rank_in_store,
  ts.staff_id AS top_staff_id,
  sf.o02 || ' ' || sf.o03 AS top_staff_full_name,
  ts.staff_amount AS top_staff_amount,
  fs.customer_id
FROM final_months AS fs
JOIN sto AS st
  ON st.j01 = fs.store_id
LEFT JOIN top_staff_per_month AS ts
  ON ts.customer_id = fs.customer_id
 AND ts.store_id = fs.store_id
 AND ts.month_start = fs.month_start
 AND ts.rn = 1
LEFT JOIN stf AS sf
  ON sf.o01 = ts.staff_id
ORDER BY
  fs.store_id,
  fs.month_start,
  fs.customer_id;