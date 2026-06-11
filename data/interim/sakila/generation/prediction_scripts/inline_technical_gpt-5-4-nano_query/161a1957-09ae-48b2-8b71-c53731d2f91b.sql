WITH pay_daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS pay_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay p
  JOIN stf s ON s.o01 = p.p03
  GROUP BY p.p02, date(p.p06)
),
avg_prev_30d AS (
  SELECT
    d.customer_id,
    d.pay_date,
    d.payment_count,
    d.day_amount,
    d.staff_count,
    d.store_count,
    (
      SELECT AVG(d2.day_amount)
      FROM pay_daily d2
      WHERE d2.customer_id = d.customer_id
        AND d2.pay_date >= date(d.pay_date, '-30 day')
        AND d2.pay_date < d.pay_date
    ) AS personal_avg_prev_30d
  FROM pay_daily d
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    co.c02 AS country,
    ci.d02 AS city
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ci ON ci.d01 = a.e05
  JOIN cnt co ON co.c01 = ci.d03
),
country_daily_sums AS (
  SELECT
    cg.country,
    d.pay_date,
    d.day_amount
  FROM pay_daily d
  JOIN customer_geo cg ON cg.customer_id = d.customer_id
),
country_p95 AS (
  SELECT
    country,
    pay_date,
    day_amount AS p95_daily_amount
  FROM (
    SELECT
      cds.*,
      ROW_NUMBER() OVER (
        PARTITION BY country, pay_date
        ORDER BY day_amount
      ) AS rn,
      COUNT(*) OVER (PARTITION BY country, pay_date) AS cnt
    FROM country_daily_sums cds
  ) x
  WHERE rn >= CAST((95 * cnt + 99) / 100 AS INTEGER)
  GROUP BY country, pay_date, day_amount
),
candidates AS (
  SELECT
    ap.customer_id,
    cg.country,
    cg.city,
    ap.pay_date,
    ap.payment_count,
    ap.day_amount,
    ap.staff_count,
    ap.store_count,
    ap.personal_avg_prev_30d,
    (ap.day_amount - ap.personal_avg_prev_30d) AS deviation_from_personal_avg,
    cp.p95_daily_amount
  FROM avg_prev_30d ap
  JOIN customer_geo cg ON cg.customer_id = ap.customer_id
  JOIN country_p95 cp
    ON cp.country = cg.country
   AND cp.pay_date = ap.pay_date
  WHERE ap.payment_count >= 3
    AND (ap.staff_count > 1 OR ap.store_count > 1)
    AND ap.personal_avg_prev_30d IS NOT NULL
    AND ap.personal_avg_prev_30d > 0
    AND ap.day_amount >= 2.0 * ap.personal_avg_prev_30d
    AND ap.day_amount > cp.p95_daily_amount
),
staff_list AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS pay_date,
    GROUP_CONCAT(DISTINCT (st.o02 || ' ' || st.o03)) AS staff_names
  FROM pay p
  JOIN stf st ON st.o01 = p.p03
  GROUP BY p.p02, date(p.p06)
)
SELECT
  c.customer_id,
  c.country,
  c.city,
  c.pay_date AS spike_date,
  c.payment_count,
  ROUND(c.day_amount, 2) AS day_amount,
  ROUND(c.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  DENSE_RANK() OVER (
    PARTITION BY c.country
    ORDER BY c.deviation_from_personal_avg DESC
  ) AS suspicion_rank_in_country,
  COALESCE(sl.staff_names, '') AS staff_list
FROM candidates c
LEFT JOIN staff_list sl
  ON sl.customer_id = c.customer_id
 AND sl.pay_date = c.pay_date
ORDER BY
  c.country,
  suspicion_rank_in_country,
  c.pay_date,
  c.customer_id;