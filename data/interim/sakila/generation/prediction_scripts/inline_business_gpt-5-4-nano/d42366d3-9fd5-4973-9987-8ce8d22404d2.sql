WITH customer_home AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS home_store_id,
    co.c02 AS country,
    ci.d02 AS city
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
),
pay_facts AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    sf.o07 AS staff_store_id,
    CASE WHEN sf.o07 <> ch.home_store_id THEN 1 ELSE 0 END AS is_off_home_store
  FROM pay AS p
  JOIN customer_home AS ch ON ch.customer_id = p.p02
  JOIN stf AS sf ON sf.o01 = p.p03
),
monthly_customer AS (
  SELECT
    pf.customer_id,
    ch.country,
    ch.city,
    pf.month_start,
    COUNT(*) AS payment_count,
    SUM(pf.payment_amount) AS monthly_amount,
    SUM(pf.is_off_home_store) AS off_home_payment_count,
    1.0 * SUM(pf.is_off_home_store) / COUNT(*) AS off_home_payment_share,
    COUNT(DISTINCT pf.staff_id) AS distinct_staff_count,
    SUM(CASE WHEN pf.staff_store_id <> ch.home_store_id THEN 1 ELSE 0 END) AS payments_through_other_stores_count,
    COUNT(DISTINCT pf.staff_store_id) AS distinct_stores_in_month
  FROM pay_facts AS pf
  JOIN customer_home AS ch
    ON ch.customer_id = pf.customer_id
  GROUP BY
    pf.customer_id,
    ch.country,
    ch.city,
    pf.month_start
),
monthly_with_history AS (
  SELECT
    mc.*,
    AVG(monthly_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS avg_prev_2_months_amount
  FROM monthly_customer AS mc
),
country_month_stats AS (
  SELECT
    ch.country,
    mc.month_start,
    mc.monthly_amount,
    mc.customer_id,
    mc.payment_count,
    mc.off_home_payment_share,
    mc.distinct_staff_count,
    RANK() OVER (
      PARTITION BY ch.country, mc.month_start
      ORDER BY mc.monthly_amount DESC
    ) AS country_month_rank_desc,
    COUNT(*) OVER (
      PARTITION BY ch.country, mc.month_start
    ) AS country_month_customers_cnt
  FROM monthly_customer AS mc
  JOIN (SELECT DISTINCT country FROM customer_home) AS ch
    ON ch.country = mc.country
),
country_thresholds AS (
  -- Порог "типичного значения" по стране и месяцу: 75-й перцентиль (практический верхний диапазон).
  -- Берём значение на позиции ceil(0.75*N) в сортировке по возрастанию.
  SELECT
    country,
    month_start,
    MAX(monthly_amount) AS country_q75_amount
  FROM (
    SELECT
      cms.country,
      cms.month_start,
      cms.monthly_amount,
      cms.country_month_customers_cnt,
      ROW_NUMBER() OVER (
        PARTITION BY cms.country, cms.month_start
        ORDER BY cms.monthly_amount ASC
      ) AS rn_asc
    FROM (
      SELECT
        ch.country,
        mc.month_start,
        mc.monthly_amount,
        mc.customer_id,
        mc.payment_count,
        mc.off_home_payment_share,
        mc.distinct_staff_count,
        COUNT(*) OVER (
          PARTITION BY ch.country, mc.month_start
        ) AS country_month_customers_cnt
      FROM monthly_customer AS mc
      JOIN customer_home AS ch
        ON ch.customer_id = mc.customer_id
    ) AS cms
  ) t
  WHERE rn_asc >= CAST( (0.75 * country_month_customers_cnt) + 0.999999 AS INTEGER )
  GROUP BY country, month_start
),
suspicous AS (
  SELECT
    mwh.customer_id,
    mwh.country,
    mwh.city,
    mwh.month_start,
    mwh.monthly_amount,
    mwh.payment_count,
    mwh.off_home_payment_share,
    mwh.distinct_staff_count,
    mwh.distinct_stores_in_month,
    mwh.off_home_payment_count,
    mwh.payments_through_other_stores_count,
    mwh.avg_prev_2_months_amount,
    cs.country_q75_amount,
    RANK() OVER (
      PARTITION BY mwh.country, mwh.month_start
      ORDER BY mwh.monthly_amount DESC
    ) AS country_month_amount_rank
  FROM monthly_with_history AS mwh
  JOIN country_thresholds AS cs
    ON cs.country = mwh.country
   AND cs.month_start = mwh.month_start
  WHERE mwh.avg_prev_2_months_amount IS NOT NULL
    AND mwh.avg_prev_2_months_amount > 0
    AND mwh.monthly_amount > 2.0 * mwh.avg_prev_2_months_amount
    AND mwh.monthly_amount > cs.country_q75_amount
)
SELECT
  strftime('%Y-%m', month_start) AS payment_month,
  customer_id,
  country,
  city,
  ROUND(monthly_amount, 2) AS monthly_payment_sum,
  payment_count,
  ROUND(off_home_payment_share, 4) AS off_home_payment_share,
  distinct_staff_count AS distinct_staff_count,
  distinct_stores_in_month AS distinct_stores_in_month,
  country_month_amount_rank AS country_month_amount_rank
FROM suspicious
ORDER BY
  country,
  payment_month,
  country_month_amount_rank,
  customer_id;