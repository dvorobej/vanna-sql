SELECT date('2005-01-01','start of month') AS month_start
  UNION ALL
  SELECT date(month_start,'+1 month')
  FROM months_2005
  WHERE month_start < date('2005-12-01','start of month')
),
customer_home AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    co.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ci ON ci.d01 = a.e05
  JOIN cnt co ON co.c01 = ci.d03
),
payments_monthly AS (
  SELECT
    r.q04 AS customer_id,
    date(p.p06,'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS month_sum
  FROM pay p
  JOIN ren r ON r.q01 = p.p04
  WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
  GROUP BY r.q04, date(p.p06,'start of month')
),
monthly_with_rolling AS (
  SELECT
    ch.customer_id,
    ch.store_id,
    ch.country_name,
    ch.city_name,
    m.month_start,
    COALESCE(pm.payment_count,0) AS payment_count,
    COALESCE(pm.month_sum,0) AS month_sum,
    AVG(COALESCE(pm.month_sum,0)) OVER (
      PARTITION BY ch.customer_id
      ORDER BY m.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev2_month_avg
  FROM customer_home ch
  CROSS JOIN months_2005 m
  LEFT JOIN payments_monthly pm
    ON pm.customer_id = ch.customer_id
   AND pm.month_start = m.month_start
),
suspicious_months AS (
  SELECT
    mw.*,
    (mw.month_sum - mw.prev2_month_avg) AS deviation_from_rolling_avg,
    RANK() OVER (
      PARTITION BY mw.store_id, mw.month_start
      ORDER BY mw.month_sum DESC
    ) AS store_month_rank
  FROM monthly_with_rolling mw
  WHERE mw.prev2_month_avg > 0
    AND mw.month_sum >= 2.0 * mw.prev2_month_avg
    AND mw.payment_count >= 3
),
store_month_top10 AS (
  SELECT
    store_id,
    month_start,
    month_sum,
    store_month_rank,
    COUNT(*) OVER (PARTITION BY store_id, month_start) AS store_month_clients_count
  FROM suspicious_months
),
eligible_suspicious_months AS (
  SELECT
    sm.*
  FROM suspicious_months sm
  JOIN (
    SELECT
      store_id,
      month_start,
      CAST((store_month_clients_count * 0.10) + 0.999999 AS INTEGER) AS top10_threshold_rank
    FROM (
      SELECT DISTINCT store_id, month_start,
        COUNT(*) OVER (PARTITION BY store_id, month_start) AS store_month_clients_count
      FROM suspicious_months
    )
  ) t
    ON t.store_id = sm.store_id
   AND t.month_start = sm.month_start
  WHERE sm.store_month_rank <= t.top10_threshold_rank
),
qualified_clients AS (
  -- клиенты, у которых В КАЖДОМ МЕСЯЦЕ 2005 года есть подозрительный месяц по критерию
  -- (для января/февраля prev2_month_avg не определён — поэтому требование выполняется со 2005-03 по 2005-12)
  SELECT
    ec.customer_id
  FROM (
    SELECT
      customer_id,
      COUNT(*) AS suspicious_months_count
    FROM eligible_suspicious_months
    WHERE month_start >= '2005-03-01' AND month_start <= '2005-12-01'
    GROUP BY customer_id
  ) ec
  WHERE ec.suspicious_months_count = 10
),
month_staff_top AS (
  SELECT
    r.q04 AS customer_id,
    date(p.p06,'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_month_sum,
    COUNT(*) AS staff_month_payments_count,
    ROW_NUMBER() OVER (
      PARTITION BY r.q04, date(p.p06,'start of month')
      ORDER BY SUM(p.p05) DESC, COUNT(*) DESC, p.p03
    ) AS rn
  FROM pay p
  JOIN ren r ON r.q01 = p.p04
  WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
  GROUP BY r.q04, date(p.p06,'start of month'), p.p03
)
SELECT
  sm.store_id,
  sm.city_name,
  sm.country_name,
  strftime('%Y-%m', sm.month_start) AS suspicious_month,
  ROUND(sm.month_sum, 2) AS month_sum,
  sm.payment_count,
  ROUND(sm.deviation_from_rolling_avg, 2) AS deviation_from_rolling_avg,
  sm.store_month_rank AS month_rank_in_store,
  st.o02 AS staff_first_name,
  st.o03 AS staff_last_name,
  mst.staff_month_payments_count,
  ROUND(mst.staff_month_sum, 2) AS top_staff_amount_in_month
FROM eligible_suspicious_months sm
JOIN qualified_clients qc ON qc.customer_id = sm.customer_id
JOIN month_staff_top mst
  ON mst.customer_id = sm.customer_id
 AND mst.month_start = sm.month_start
 AND mst.rn = 1
JOIN stf st ON st.o01 = mst.staff_id
ORDER BY sm.store_id, sm.month_start, sm.store_month_rank;