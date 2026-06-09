WITH daily_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT st.o07) AS distinct_store_count
  FROM pay AS p
  JOIN stf AS st
    ON st.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_history AS (
  SELECT
    dp.customer_id,
    dp.payment_date,
    dp.payment_count,
    dp.day_amount,
    dp.distinct_staff_count,
    dp.distinct_store_count,
    (
      SELECT AVG(CAST(dp2.day_amount AS REAL))
      FROM daily_pay AS dp2
      WHERE dp2.customer_id = dp.customer_id
        AND dp2.payment_date >= date(dp.payment_date, '-30 days')
        AND dp2.payment_date < dp.payment_date
    ) AS avg_prev_30d_day_amount
  FROM daily_pay AS dp
),
country_daily_ranked AS (
  SELECT
    d.customer_id,
    d.payment_date,
    d.payment_count,
    d.day_amount,
    d.distinct_staff_count,
    d.distinct_store_count,
    d.avg_prev_30d_day_amount,
    cty.c01 AS country_id,
    cty.c02 AS country_name,
    DENSE_RANK() OVER (
      PARTITION BY cty.c01, d.payment_date
      ORDER BY d.day_amount DESC
    ) AS daily_amount_rank
  FROM daily_with_history AS d
  JOIN cus AS cu
    ON cu.h01 = d.customer_id
  JOIN adr AS a
    ON a.e01 = cu.h06
  JOIN cty
    ON cty.d01 = a.e05
)
SELECT
  cdr.customer_id AS h01,
  cdr.country_name AS country,
  cty.d02 AS city,
  cdr.payment_date AS p06_date,
  cdr.payment_count,
  ROUND(cdr.day_amount, 2) AS day_amount,
  GROUP_CONCAT(DISTINCT stf.o01) AS staff_o01_list,
  ROUND((cdr.day_amount - cdr.avg_prev_30d_day_amount), 2) AS deviation_from_prev_30d_avg,
  cdr.daily_amount_rank AS country_day_amount_rank_by_95p
FROM (
  SELECT
    dwh.*,
    cu.h06
  FROM daily_with_history AS dwh
  JOIN cus AS cu
    ON cu.h01 = dwh.customer_id
  WHERE dwh.payment_count >= 3
    AND (dwh.distinct_staff_count >= 2 OR dwh.distinct_store_count >= 2)
) AS cdr
JOIN cus AS cu
  ON cu.h01 = cdr.customer_id
JOIN adr AS a
  ON a.e01 = cu.h06
JOIN cty
  ON cty.d01 = a.e05
JOIN cnt
  ON cnt.c01 = cty.d03
JOIN pay AS p
  ON p.p02 = cdr.customer_id
 AND date(p.p06) = cdr.payment_date
JOIN stf
  ON stf.o01 = p.p03
JOIN ren AS r
  ON r.q01 = p.p04
JOIN inv AS i
  ON i.n01 = r.q03
JOIN sto
  ON sto.j01 = i.n03
WHERE (
  (p.p03 IN (
    SELECT p3.p03
    FROM pay AS p3
    WHERE p3.p02 = cdr.customer_id
      AND date(p3.p06) = cdr.payment_date
    GROUP BY p3.p03
    HAVING COUNT(*) >= 1
  ))
  OR 1=1
)
GROUP BY
  cdr.customer_id,
  cnt.c02,
  cty.d02,
  cdr.payment_date,
  cdr.payment_count,
  cdr.day_amount,
  cdr.avg_prev_30d_day_amount,
  cdr.daily_amount_rank
ORDER BY
  cnt.c02,
  cdr.payment_date,
  cdr.day_amount DESC,
  cdr.customer_id;