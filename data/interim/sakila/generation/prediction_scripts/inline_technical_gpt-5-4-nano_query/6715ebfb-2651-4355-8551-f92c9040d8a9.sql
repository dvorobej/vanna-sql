SELECT 1 AS dummy
  ) AS dummy
  ON 1=1
  -- Псевдомедиана: оставляем расчет ниже через агрегирование по нижней/верхней позициям
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    cty.c02 AS country_name,
    cty.d02 AS city_name,
    c.h02 AS store_id
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt AS cty_country
    ON cty_country.c01 = cty.d03
)
SELECT
  cg.country_name AS country,
  cg.city_name AS city,
  cg.store_id AS store_id,
  cmh.customer_id,
  cmh.month_start AS month,
  cmh.payment_count AS payment_count,
  ROUND(cmh.month_total_amount, 2) AS total_amount,
  ROUND(cmh.max_single_payment_amount, 2) AS max_single_payment,
  ROUND(
    CASE
      WHEN cmh.payment_count = 0 THEN 0
      ELSE
        (1.0 * SUM(CASE WHEN cat.g02 IN ('Action','New') THEN 1 ELSE 0 END) / cmh.payment_count)
    END,
    4
  ) AS action_new_payment_share,
  RANK() OVER (
    PARTITION BY cg.country_name
    ORDER BY SUM(cmh.month_total_amount) DESC
  ) AS suspicious_customer_rank_in_country
FROM customer_month_history AS cmh
JOIN customer_geo AS cg
  ON cg.customer_id = cmh.customer_id
JOIN pay AS p
  ON p.p02 = cmh.customer_id
 AND date(p.p06, 'start of month') = cmh.month_start
LEFT JOIN ren AS r
  ON r.q01 = p.p04
LEFT JOIN inv AS i
  ON i.n01 = r.q03
LEFT JOIN flc AS fc
  ON fc.l01 = i.n02
LEFT JOIN cat
  ON cat.g01 = fc.l02
LEFT JOIN flm
  ON flm.i01 = i.n02
WHERE
  cmh.hist_months_count >= 1
  AND cmh.personal_avg_monthly_amount_hist > 0
  AND cmh.month_total_amount > 3.0 * cmh.personal_avg_monthly_amount_hist
  AND cmh.payment_count > (
    SELECT
      AVG(t.payment_count) AS median_payment_count
    FROM (
      SELECT
        mp2.payment_count,
        ROW_NUMBER() OVER (PARTITION BY cg2.country_name, mp2.month_start ORDER BY mp2.payment_count) AS rn,
        COUNT(*) OVER (PARTITION BY cg2.country_name, mp2.month_start) AS cnt
      FROM monthly_payments AS mp2
      JOIN customer_geo AS cg2
        ON cg2.customer_id = mp2.customer_id
      WHERE cg2.country_name = cg.country_name
        AND mp2.month_start = cmh.month_start
    ) AS t
    WHERE t.rn IN (
      CAST((t.cnt + 1) / 2 AS INTEGER),
      CAST((t.cnt + 2) / 2 AS INTEGER)
    )
  )
GROUP BY
  cg.country_name,
  cg.city_name,
  cg.store_id,
  cmh.customer_id,
  cmh.month_start,
  cmh.payment_count,
  cmh.month_total_amount,
  cmh.max_single_payment_amount
ORDER BY
  cg.country_name,
  suspicious_customer_rank_in_country,
  cmh.month_start,
  cmh.customer_id;