WITH
pay_daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS pay_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS daily_sum
  FROM pay AS p
  GROUP BY p.p02, date(p.p06)
),
customer_geo AS (
  SELECT
    cus.h01 AS customer_id,
    cnt.c02 AS country,
    cty.d02 AS city
  FROM cus
  JOIN adr  ON adr.e01 = cus.h06
  JOIN cty  ON cty.d01 = adr.e05
  JOIN cnt  ON cnt.c01 = cty.d03
),
daily_with_avgs AS (
  SELECT
    pd.customer_id,
    pd.pay_date,
    pd.payment_count,
    pd.daily_sum,
    AVG(pd2.daily_sum) AS personal_avg_prev_30d,
    AVG(cd2.daily_sum) AS country_avg_prev_30d
  FROM pay_daily AS pd
  JOIN customer_geo AS cg
    ON cg.customer_id = pd.customer_id
  JOIN pay_daily AS pd2
    ON pd2.customer_id = pd.customer_id
   AND pd2.pay_date >= date(pd.pay_date, '-30 days')
   AND pd2.pay_date <  pd.pay_date
  JOIN customer_geo AS cdg
    ON cdg.customer_id = pd2.customer_id
  JOIN pay_daily AS cd2
    ON cd2.customer_id = pd2.customer_id
   AND cd2.pay_date = pd2.pay_date
   AND cdg.country = cg.country
  GROUP BY
    pd.customer_id,
    pd.pay_date,
    pd.payment_count,
    pd.daily_sum
),
daily_multi_staff_store AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS pay_date,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY p.p02, date(p.p06)
),
base AS (
  SELECT
    d.customer_id,
    cg.country,
    cg.city,
    d.pay_date,
    d.daily_sum,
    d.payment_count,
    d.personal_avg_prev_30d,
    d.country_avg_prev_30d,
    (d.daily_sum - d.personal_avg_prev_30d) AS deviation_from_personal_avg,
    (d.daily_sum - d.country_avg_prev_30d) AS deviation_from_country_avg,
    ms.distinct_staff_count,
    ms.distinct_store_count
  FROM daily_with_avgs AS d
  JOIN customer_geo AS cg
    ON cg.customer_id = d.customer_id
  JOIN daily_multi_staff_store AS ms
    ON ms.customer_id = d.customer_id
   AND ms.pay_date = d.pay_date
)
SELECT
  b.customer_id,
  b.country,
  b.city,
  b.pay_date AS suspicious_date,
  ROUND(b.daily_sum, 2) AS daily_sum,
  b.payment_count,
  ROUND(b.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  ROUND(b.deviation_from_country_avg, 2) AS deviation_from_country_avg,
  b.distinct_staff_count,
  b.distinct_store_count,
  DENSE_RANK() OVER (
    PARTITION BY b.country
    ORDER BY b.daily_sum DESC
  ) AS country_client_rank_by_suspicious_sum
FROM base AS b
WHERE
  b.personal_avg_prev_30d IS NOT NULL
  AND b.personal_avg_prev_30d > 0
  AND b.country_avg_prev_30d IS NOT NULL
  AND b.country_avg_prev_30d > 0
  AND b.daily_sum > 3.0 * b.personal_avg_prev_30d
  AND b.daily_sum > b.country_avg_prev_30d
  AND (b.distinct_staff_count >= 2 OR b.distinct_store_count >= 2)
ORDER BY
  b.country,
  country_client_rank_by_suspicious_sum,
  b.pay_date,
  b.customer_id;