SELECT AVG(mp2.month_payment_sum * 1.0)
      FROM month_payments AS mp2
      WHERE mp2.customer_id = mp.customer_id
        AND mp2.payment_month >= strftime('%Y-%m', date(mp.payment_month || '-01', '-3 months'))
        AND mp2.payment_month <  mp.payment_month
    ) AS prev3_avg_month_sum,
    (
      SELECT AVG(mp2.month_payment_count * 1.0)
      FROM month_payments AS mp2
      WHERE mp2.customer_id = mp.customer_id
        AND mp2.payment_month >= strftime('%Y-%m', date(mp.payment_month || '-01', '-3 months'))
        AND mp2.payment_month <  mp.payment_month
    ) AS prev3_avg_month_count
  FROM month_payments AS mp
),
customer_month_context AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    GROUP_CONCAT(DISTINCT (s.o02 || ' ' || s.o03)) AS staff_list,
    GROUP_CONCAT(DISTINCT CAST(st.j01 AS TEXT)) AS store_list,
    COUNT(*) AS payment_rows_check
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  JOIN sto AS st ON st.j01 = s.o07
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c01 AS country_id
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS city ON city.d01 = a.e05
  JOIN cnt ON cnt.c01 = city.d03
),
country_medians AS (
  SELECT
    cg.country_id,
    mp.payment_month,
    AVG(x.month_payment_sum * 1.0) AS country_median_payment_sum
  FROM customer_geo AS cg
  JOIN month_payments AS mp
    ON mp.customer_id = cg.customer_id
  JOIN (
    SELECT
      cg2.country_id,
      mp2.payment_month,
      mp2.customer_id,
      mp2.month_payment_sum,
      ROW_NUMBER() OVER (
        PARTITION BY cg2.country_id, mp2.payment_month
        ORDER BY mp2.month_payment_sum
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY cg2.country_id, mp2.payment_month
      ) AS cnt
    FROM customer_geo AS cg2
    JOIN month_payments AS mp2
      ON mp2.customer_id = cg2.customer_id
  ) AS x
    ON x.country_id = cg.country_id
   AND x.payment_month = mp.payment_month
   AND x.rn = CAST((x.cnt + 1) / 2 AS INTEGER)
   OR x.rn = CAST((x.cnt + 2) / 2 AS INTEGER)
  GROUP BY
    cg.country_id,
    mp.payment_month
),
country_ranking AS (
  SELECT
    cg.country_id,
    mp.payment_month,
    mp.customer_id,
    mp.month_payment_sum,
    PERCENT_RANK() OVER (
      PARTITION BY cg.country_id, mp.payment_month
      ORDER BY mp.month_payment_sum
    ) AS pr
  FROM customer_geo AS cg
  JOIN month_payments AS mp
    ON mp.customer_id = cg.customer_id
)
SELECT
  mp.customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  cg.country_id,
  cnt.c02 AS country_name,
  mp.payment_month,
  mp.month_payment_count,
  ROUND(mp.month_payment_sum, 2) AS month_payment_sum,
  ROUND(ch.prev3_avg_month_sum, 2) AS prev3_avg_month_sum,
  ROUND(ch.prev3_avg_month_count, 2) AS prev3_avg_month_count,
  cmc.staff_list,
  cmc.store_list,
  ROUND(cmed.country_median_payment_sum, 2) AS country_median_payment_sum,
  ROUND(mp.month_payment_sum / NULLIF(cmed.country_median_payment_sum, 0), 2) AS vs_country_median_ratio,
  ROUND(mp.month_payment_sum / NULLIF(ch.prev3_avg_month_sum, 0), 2) AS vs_prev3_avg_ratio
FROM month_payments AS mp
JOIN cus AS c ON c.h01 = mp.customer_id
JOIN customer_geo AS cg ON cg.customer_id = mp.customer_id
JOIN cnt ON cnt.c01 = cg.country_id
JOIN customer_hist AS ch
  ON ch.customer_id = mp.customer_id
 AND ch.payment_month = mp.payment_month
JOIN customer_month_context AS cmc
  ON cmc.customer_id = mp.customer_id
 AND cmc.payment_month = mp.payment_month
JOIN country_medians AS cmed
  ON cmed.country_id = cg.country_id
 AND cmed.payment_month = mp.payment_month
JOIN country_ranking AS cr
  ON cr.country_id = cg.country_id
 AND cr.payment_month = mp.payment_month
 AND cr.customer_id = mp.customer_id
WHERE
  ch.prev3_avg_month_sum IS NOT NULL
  AND ch.prev3_avg_month_sum > 0
  AND mp.month_payment_sum >= 3.0 * ch.prev3_avg_month_sum
  AND mp.month_payment_sum >= 2.0 * cmed.country_median_payment_sum
  AND cr.pr >= 0.95
ORDER BY
  mp.payment_month,
  cg.country_id,
  mp.month_payment_sum DESC,
  mp.customer_id;