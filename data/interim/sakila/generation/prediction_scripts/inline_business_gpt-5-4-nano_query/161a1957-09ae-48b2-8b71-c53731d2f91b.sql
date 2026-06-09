WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c02 AS country,
    ct.d02 AS city,
    c.h06 AS address_id
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt ON cnt.c01 = ct.d03
),
pay_daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_sum,
    GROUP_CONCAT(DISTINCT CAST(p.p03 AS TEXT)) AS staff_ids,
    GROUP_CONCAT(DISTINCT CAST(s.o07 AS TEXT)) AS store_ids,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay p
  JOIN stf s ON s.o01 = p.p03
  GROUP BY p.p02, date(p.p06)
),
calendar_daily_avg_prev30 AS (
  SELECT
    pd.customer_id,
    pd.payment_date,
    pd.payment_count,
    pd.day_sum,
    pd.staff_ids,
    pd.staff_count,
    pd.store_ids,
    pd.store_count,
    (
      SELECT AVG(CAST(pdv.day_sum AS REAL))
      FROM pay_daily pdv
      WHERE pdv.customer_id = pd.customer_id
        AND pdv.payment_date >= date(pd.payment_date, '-30 day')
        AND pdv.payment_date < pd.payment_date
    ) AS personal_avg_prev_30
  FROM pay_daily pd
),
country_daily_quant AS (
  SELECT
    cg.country,
    pd.payment_date,
    pd.day_sum,
    ROW_NUMBER() OVER (PARTITION BY cg.country, pd.payment_date ORDER BY pd.day_sum) AS rn_dummy,
    0 AS dummy
  FROM pay_daily pd
  JOIN customer_geo cg ON cg.customer_id = pd.customer_id
),
country_daily_p95 AS (
  -- 95-й перцентиль дневных сумм среди клиентов из той же страны:
  -- берём "нижнюю" оценку как минимальное значение, попадающее в хвост >= 95%
  SELECT
    country,
    MIN(day_sum) AS country_p95_day_sum
  FROM (
    SELECT
      cg.country,
      pd.day_sum,
      ROW_NUMBER() OVER (PARTITION BY cg.country ORDER BY pd.day_sum) AS rn,
      COUNT(*) OVER (PARTITION BY cg.country) AS cnt
    FROM pay_daily pd
    JOIN customer_geo cg ON cg.customer_id = pd.customer_id
  ) x
  WHERE rn >= CAST((0.95 * cnt) + 0.5 AS INTEGER)
  GROUP BY country
),
flagged AS (
  SELECT
    cga.customer_id,
    cga.payment_date,
    cga.payment_count,
    cga.day_sum,
    cga.staff_ids,
    cga.staff_count,
    cga.store_count,
    cga.personal_avg_prev_30,
    cg.country,
    cg.city,
    cdp95.country_p95_day_sum,
    (cga.day_sum - cga.personal_avg_prev_30) AS deviation_from_personal_avg,
    (cga.day_sum / NULLIF(cga.personal_avg_prev_30, 0)) AS day_sum_ratio
  FROM calendar_daily_avg_prev30 cga
  JOIN customer_geo cg ON cg.customer_id = cga.customer_id
  JOIN country_daily_p95 cdp95 ON cdp95.country = cg.country
  WHERE cga.payment_count >= 3
    AND (cga.staff_count >= 2 OR cga.store_count >= 2)
    AND cga.personal_avg_prev_30 IS NOT NULL
    AND cga.personal_avg_prev_30 > 0
    AND cga.day_sum > 2.0 * cga.personal_avg_prev_30
    AND cga.day_sum > cdp95.country_p95_day_sum
),
ranked AS (
  SELECT
    f.*,
    DENSE_RANK() OVER (
      PARTITION BY f.country
      ORDER BY f.deviation_from_personal_avg DESC
    ) AS suspicion_rank_in_country
  FROM flagged f
)
SELECT
  customer_id,
  country,
  city,
  payment_date AS spike_date,
  payment_count,
  ROUND(day_sum, 2) AS day_sum,
  staff_ids AS staff_list,
  ROUND(deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  suspicion_rank_in_country
FROM ranked
ORDER BY
  country,
  suspicion_rank_in_country,
  payment_date,
  customer_id;