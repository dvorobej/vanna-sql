WITH pay_daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS daily_amount
  FROM pay AS p
  GROUP BY p.p02, date(p.p06)
),
pay_daily_staff_store AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS daily_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY p.p02, date(p.p06)
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c02 AS country_name,
    cty.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
),
customer_day_with_personal_avg AS (
  SELECT
    pds.customer_id,
    pds.payment_date,
    pds.payment_count,
    pds.daily_amount,
    pds.staff_count,
    pds.store_count,
    cg.country_name,
    cg.city_name,
    (
      SELECT AVG(pd2.daily_amount)
      FROM pay_daily AS pd2
      WHERE pd2.customer_id = pds.customer_id
        AND pd2.payment_date >= date(pds.payment_date, '-30 day')
        AND pd2.payment_date < pds.payment_date
    ) AS personal_avg_prev_30
  FROM pay_daily_staff_store AS pds
  JOIN customer_geo AS cg
    ON cg.customer_id = pds.customer_id
),
country_day_avg AS (
  SELECT
    cg.country_name,
    pd.payment_date,
    AVG(pd.daily_amount) AS country_avg_daily_amount
  FROM pay_daily AS pd
  JOIN customer_geo AS cg
    ON cg.customer_id = pd.customer_id
  GROUP BY cg.country_name, pd.payment_date
),
scored AS (
  SELECT
    cdp.customer_id,
    cdp.city_name,
    cdp.country_name,
    cdp.payment_date,
    cdp.payment_count,
    cdp.daily_amount,
    cdp.personal_avg_prev_30,
    cdp.daily_amount - cdp.personal_avg_prev_30 AS deviation_personal,
    cda.country_avg_daily_amount AS country_avg_daily_amount,
    cdp.daily_amount - cda.country_avg_daily_amount AS deviation_country,
    cdp.staff_count,
    cdp.store_count
  FROM customer_day_with_personal_avg AS cdp
  JOIN country_day_avg AS cda
    ON cda.country_name = cdp.country_name
   AND cda.payment_date = cdp.payment_date
  WHERE cdp.personal_avg_prev_30 IS NOT NULL
)
SELECT
  customer_id,
  country_name AS country,
  city_name AS city,
  payment_date AS spike_date,
  ROUND(daily_amount, 2) AS daily_amount,
  payment_count,
  ROUND(deviation_personal, 2) AS deviation_from_personal_avg,
  ROUND(deviation_country, 2) AS deviation_from_country_avg,
  staff_count AS distinct_staff_count,
  store_count AS distinct_store_count,
  RANK() OVER (
    PARTITION BY country_name, payment_date
    ORDER BY daily_amount DESC
  ) AS suspicion_rank_within_country
FROM scored
WHERE daily_amount > 3.0 * personal_avg_prev_30
  AND daily_amount > country_avg_daily_amount
  AND (staff_count >= 2 OR store_count >= 2)
ORDER BY country, spike_date, daily_amount DESC, customer_id;