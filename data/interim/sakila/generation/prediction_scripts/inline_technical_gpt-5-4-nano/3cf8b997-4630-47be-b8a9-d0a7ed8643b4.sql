WITH monthly_pay AS (
  SELECT
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS payment_amount,
    p.p01 AS payment_id,
    date(p.p06, 'start of month') AS month_start,
    strftime('%Y', p.p06) AS year_str,
    p.p06 AS payment_datetime
  FROM pay p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
    AND p.p04 IS NOT NULL
),
monthly_by_customer AS (
  SELECT
    mp.customer_id AS h01,
    mp.month_start,
    COUNT(*) AS payment_count,
    SUM(mp.payment_amount) AS month_payment_sum,
    AVG(mp.payment_amount) AS month_avg_payment_amount
  FROM monthly_pay mp
  GROUP BY mp.customer_id, mp.month_start
),
with_rolling AS (
  SELECT
    mbc.h01,
    mbc.month_start,
    mbc.payment_count,
    mbc.month_payment_sum,
    mbc.month_avg_payment_amount,
    AVG(mbc.month_payment_sum) OVER (
      PARTITION BY mbc.h01
      ORDER BY mbc.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev2_month_avg_sum
  FROM monthly_by_customer mbc
),
suspicious_months AS (
  SELECT
    w.h01,
    w.month_start,
    w.payment_count,
    w.month_payment_sum,
    w.prev2_month_avg_sum,
    (w.month_payment_sum - w.prev2_month_avg_sum) AS deviation_from_rolling_sum,
    CASE
      WHEN w.prev2_month_avg_sum IS NOT NULL AND w.prev2_month_avg_sum <> 0
      THEN w.month_payment_sum / w.prev2_month_avg_sum
    END AS rolling_ratio
  FROM with_rolling w
  WHERE w.prev2_month_avg_sum IS NOT NULL
    AND w.payment_count >= 3
    AND w.month_payment_sum >= 2.0 * w.prev2_month_avg_sum
),
ranked_month_staff AS (
  SELECT
    sm.h01,
    sm.month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_month_payment_sum,
    ROW_NUMBER() OVER (
      PARTITION BY sm.h01, sm.month_start
      ORDER BY SUM(p.p05) DESC, p.p03
    ) AS staff_rn
  FROM suspicious_months sm
  JOIN pay p
    ON p.p02 = sm.h01
   AND date(p.p06, 'start of month') = sm.month_start
   AND p.p04 IS NOT NULL
  JOIN ren r
    ON r.q01 = p.p04
  WHERE (p.p04 = r.q01 OR p.p04 = r.q04) -- to ensure linkage via ren.q01/ren.q04 context
  GROUP BY sm.h01, sm.month_start, p.p03
),
top_staff_each_month AS (
  SELECT
    rms.h01,
    rms.month_start,
    rms.staff_id,
    rms.staff_month_payment_sum
  FROM ranked_month_staff rms
  WHERE rms.staff_rn = 1
),
customer_geo AS (
  SELECT
    c.h01,
    c.h02 AS home_store_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    a.e01 AS address_id,
    ct.d02 AS city_name,
    co.c02 AS country_name,
    co.c01 AS country_id
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt co ON co.c01 = ct.d03
),
month_staff_rank_by_store AS (
  SELECT
    sm.h01,
    sm.month_start,
    sm.month_payment_sum,
    RANK() OVER (
      PARTITION BY c.h02, sm.month_start
      ORDER BY sm.month_payment_sum DESC
    ) AS store_month_payment_rank
  FROM suspicious_months sm
  JOIN cus c ON c.h01 = sm.h01
),
suspicious_months_enriched AS (
  SELECT
    sm.h01,
    cg.customer_name,
    cg.home_store_id AS h02,
    cg.country_name,
    cg.city_name,
    sm.month_start,
    sm.payment_count,
    sm.month_payment_sum,
    sm.deviation_from_rolling_sum,
    msr.store_month_payment_rank,
    ts.staff_id AS top_staff_id,
    st.o02 || ' ' || st.o03 AS top_staff_name,
    ts.staff_month_payment_sum AS top_staff_month_payment_sum
  FROM suspicious_months sm
  JOIN customer_geo cg ON cg.h01 = sm.h01
  JOIN month_staff_rank_by_store msr
    ON msr.h01 = sm.h01
   AND msr.month_start = sm.month_start
  JOIN top_staff_each_month ts
    ON ts.h01 = sm.h01
   AND ts.month_start = sm.month_start
  JOIN stf st ON st.o01 = ts.staff_id
),
store_suspicious_total AS (
  SELECT
    h02,
    h01,
    SUM(month_payment_sum) AS suspicious_total_sum
  FROM suspicious_months_enriched
  GROUP BY h02, h01
),
store_ranked_totals AS (
  SELECT
    sst.h02,
    sst.h01,
    sst.suspicious_total_sum,
    ROW_NUMBER() OVER (
      PARTITION BY sst.h02
      ORDER BY sst.suspicious_total_sum DESC, sst.h01
    ) AS rn,
    COUNT(*) OVER (
      PARTITION BY sst.h02
    ) AS cnt_customers
  FROM store_suspicious_total sst
),
top_10pct_customers AS (
  SELECT
    h02,
    h01
  FROM store_ranked_totals
  WHERE rn <= CAST((cnt_customers + 9) / 10 AS INTEGER)
)
SELECT
  sme.h01 AS customer_id,
  sme.customer_name,
  sme.h02 AS store_id,
  sme.country_name,
  sme.city_name,
  strftime('%Y-%m', sme.month_start) AS suspicious_month,
  sme.payment_count,
  ROUND(sme.month_payment_sum, 2) AS month_payment_sum,
  ROUND(sme.deviation_from_rolling_sum, 2) AS deviation_from_rolling_sum,
  sme.store_month_payment_rank,
  sme.top_staff_id,
  sme.top_staff_name,
  ROUND(sme.top_staff_month_payment_sum, 2) AS top_staff_month_payment_sum
FROM suspicious_months_enriched sme
JOIN top_10pct_customers t10
  ON t10.h02 = sme.h02
 AND t10.h01 = sme.h01
ORDER BY
  sme.h02,
  sme.country_name,
  sme.suspicious_month,
  sme.store_month_payment_rank,
  sme.h01;