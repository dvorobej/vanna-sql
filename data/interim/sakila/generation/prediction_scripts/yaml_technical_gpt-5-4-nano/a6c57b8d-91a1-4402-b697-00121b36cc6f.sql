WITH filtered_pay AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    p.p05 AS amount,
    p.p06 AS payment_date,
    date(p.p06, 'start of month') AS month_start
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
),
pay_with_geo AS (
  SELECT
    fp.*,
    c.h01 AS h01,
    c.h03 AS first_name,
    c.h04 AS last_name,
    co.c01 AS country_id,
    co.c02 AS country_name,
    ci.d01 AS city_id,
    ci.d02 AS city_name
  FROM filtered_pay AS fp
  JOIN cus AS c
    ON c.h01 = fp.customer_id
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
),
monthly_customer AS (
  SELECT
    pwg.h01,
    pwg.country_id,
    pwg.country_name,
    pwg.city_id,
    pwg.city_name,
    pwg.month_start,
    SUM(pwg.amount) AS month_sum,
    COUNT(pwg.payment_id) AS month_payment_count
  FROM pay_with_geo AS pwg
  GROUP BY
    pwg.h01,
    pwg.country_id,
    pwg.country_name,
    pwg.city_id,
    pwg.city_name,
    pwg.month_start
),
monthly_with_personal_avg AS (
  SELECT
    mc.*,
    AVG(mc.month_sum) OVER (
      PARTITION BY mc.h01
    ) AS personal_avg_month_sum
  FROM monthly_customer AS mc
),
country_top10_threshold AS (
  SELECT
    mc.country_id,
    mc.month_start,
    PERCENT_RANK() OVER (
      PARTITION BY mc.country_id, mc.month_start
      ORDER BY mc.month_sum
    ) AS pr
  FROM monthly_customer AS mc
),
country_top10 AS (
  SELECT
    mc.h01,
    mc.country_id,
    mc.month_start,
    mc.month_sum,
    mc.month_payment_count
  FROM monthly_customer AS mc
  JOIN (
    SELECT country_id, month_start, h01
    FROM (
      SELECT
        mc2.*,
        PERCENT_RANK() OVER (
          PARTITION BY mc2.country_id, mc2.month_start
          ORDER BY mc2.month_sum DESC
        ) AS pr_desc
      FROM monthly_customer AS mc2
    )
    WHERE pr_desc <= 0.10
  ) AS sel
    ON sel.country_id = mc.country_id
   AND sel.month_start = mc.month_start
   AND sel.h01 = mc.h01
),
months_scored AS (
  SELECT
    mwpa.h01,
    mwpa.country_id,
    mwpa.country_name,
    mwpa.city_id,
    mwpa.city_name,
    mwpa.month_start,
    mwpa.month_sum,
    mwpa.month_payment_count,
    mwpa.month_sum - mwpa.personal_avg_month_sum AS deviation_from_personal_avg,
    CASE
      WHEN mwpa.personal_avg_month_sum = 0 THEN NULL
      ELSE (mwpa.month_sum * 1.0) / mwpa.personal_avg_month_sum
    END AS deviation_ratio_from_personal_avg,
    DENSE_RANK() OVER (
      PARTITION BY mwpa.country_id, mwpa.month_start
      ORDER BY mwpa.month_sum DESC
    ) AS country_month_rank
  FROM monthly_with_personal_avg AS mwpa
  JOIN country_top10 AS ct10
    ON ct10.h01 = mwpa.h01
   AND ct10.country_id = mwpa.country_id
   AND ct10.month_start = mwpa.month_start
  WHERE mwpa.personal_avg_month_sum IS NOT NULL
    AND mwpa.personal_avg_month_sum > 0
    AND mwpa.month_sum > 2.0 * mwpa.personal_avg_month_sum
),
top_staff_per_month AS (
  SELECT
    pwg.h01,
    pwg.country_id,
    pwg.month_start,
    pwg.staff_id,
    SUM(pwg.amount) AS staff_month_sum,
    DENSE_RANK() OVER (
      PARTITION BY pwg.h01, pwg.month_start
      ORDER BY SUM(pwg.amount) DESC
    ) AS staff_month_rank
  FROM pay_with_geo AS pwg
  GROUP BY
    pwg.h01,
    pwg.country_id,
    pwg.month_start,
    pwg.staff_id
),
final_staff AS (
  SELECT
    ts.h01,
    ts.country_id,
    ts.month_start,
    ts.staff_id
  FROM top_staff_per_month ts
  WHERE ts.staff_month_rank = 1
)
SELECT
  ms.h01 AS customer_id,
  ms.country_id,
  ms.country_name,
  ms.city_id,
  ms.city_name,
  strftime('%Y-%m', ms.month_start) AS month,
  ROUND(ms.month_sum, 2) AS month_sum,
  ms.month_payment_count,
  ROUND(ms.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  ms.country_month_rank,
  fs.staff_id AS top_staff_id,
  st.f_name AS staff_first_name,
  st.l_name AS staff_last_name
FROM months_scored AS ms
LEFT JOIN final_staff AS fs
  ON fs.h01 = ms.h01
 AND fs.country_id = ms.country_id
 AND fs.month_start = ms.month_start
LEFT JOIN stf AS st
  ON st.o01 = fs.staff_id
ORDER BY
  ms.country_name,
  ms.month_start,
  ms.month_sum DESC,
  ms.h01;