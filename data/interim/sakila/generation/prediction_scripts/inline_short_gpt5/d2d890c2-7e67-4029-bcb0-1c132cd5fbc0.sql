WITH payment_detail AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    DATE(p.p06) AS payment_day,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    COALESCE(inv.n03, stf.o07) AS store_id
  FROM pay AS p
  JOIN stf AS stf
    ON stf.o01 = p.p03
  LEFT JOIN ren AS ren
    ON ren.q01 = p.p04
  LEFT JOIN inv AS inv
    ON inv.n01 = ren.q03
),
customer_geo AS (
  SELECT
    cus.h01 AS customer_id,
    cus.h03 || ' ' || cus.h04 AS customer_name,
    cus.h05 AS email,
    cty.d02 AS city,
    cnt.c02 AS country
  FROM cus AS cus
  JOIN adr AS adr
    ON adr.e01 = cus.h06
  JOIN cty AS cty
    ON cty.d01 = adr.e05
  JOIN cnt AS cnt
    ON cnt.c01 = cty.d03
),
customer_day AS (
  SELECT
    pd.customer_id,
    pd.payment_day,
    COUNT(*) AS payment_count,
    SUM(pd.payment_amount) AS daily_amount,
    COUNT(DISTINCT pd.staff_id) AS staff_count,
    COUNT(DISTINCT pd.store_id) AS store_count,
    GROUP_CONCAT(DISTINCT CAST(pd.staff_id AS TEXT)) AS staff_ids,
    GROUP_CONCAT(DISTINCT CAST(pd.store_id AS TEXT)) AS store_ids
  FROM payment_detail AS pd
  GROUP BY
    pd.customer_id,
    pd.payment_day
),
staff_distribution AS (
  SELECT
    customer_id,
    payment_day,
    staff_id,
    SUM(payment_amount) AS staff_amount,
    ROW_NUMBER() OVER (
      PARTITION BY customer_id, payment_day
      ORDER BY SUM(payment_amount) DESC, staff_id
    ) AS rn
  FROM payment_detail
  GROUP BY
    customer_id,
    payment_day,
    staff_id
),
store_distribution AS (
  SELECT
    customer_id,
    payment_day,
    store_id,
    SUM(payment_amount) AS store_amount,
    ROW_NUMBER() OVER (
      PARTITION BY customer_id, payment_day
      ORDER BY SUM(payment_amount) DESC, store_id
    ) AS rn
  FROM payment_detail
  GROUP BY
    customer_id,
    payment_day,
    store_id
),
customer_day_with_baseline AS (
  SELECT
    cd.*,
    (
      SELECT AVG(cd2.daily_amount)
      FROM customer_day AS cd2
      WHERE cd2.customer_id = cd.customer_id
        AND cd2.payment_day >= DATE(cd.payment_day, '-30 days')
        AND cd2.payment_day < cd.payment_day
    ) AS personal_30d_avg_amount,
    (
      SELECT COUNT(*)
      FROM customer_day AS cd2
      WHERE cd2.customer_id = cd.customer_id
        AND cd2.payment_day >= DATE(cd.payment_day, '-30 days')
        AND cd2.payment_day < cd.payment_day
    ) AS personal_30d_days
  FROM customer_day AS cd
),
country_day AS (
  SELECT
    cg.country,
    cd.payment_day,
    AVG(cd.daily_amount) AS country_daily_avg_amount
  FROM customer_day AS cd
  JOIN customer_geo AS cg
    ON cg.customer_id = cd.customer_id
  GROUP BY
    cg.country,
    cd.payment_day
),
scored AS (
  SELECT
    cg.customer_id,
    cg.customer_name,
    cg.email,
    cg.country,
    cg.city,
    cd.payment_day,
    cd.payment_count,
    cd.daily_amount,
    cd.personal_30d_avg_amount,
    cda.country_daily_avg_amount,
    cd.staff_count,
    cd.store_count,
    cd.staff_ids,
    cd.store_ids,
    sd.staff_id AS dominant_staff_id,
    ROUND(sd.staff_amount / NULLIF(cd.daily_amount, 0), 4) AS dominant_staff_amount_share,
    std.store_id AS dominant_store_id,
    ROUND(std.store_amount / NULLIF(cd.daily_amount, 0), 4) AS dominant_store_amount_share,
    ROUND(cd.daily_amount / NULLIF(cd.personal_30d_avg_amount, 0), 4) AS ratio_to_personal_30d_avg,
    ROUND(cd.daily_amount / NULLIF(cda.country_daily_avg_amount, 0), 4) AS ratio_to_country_daily_avg,
    (
      cd.daily_amount / NULLIF(cd.personal_30d_avg_amount, 0)
      + cd.daily_amount / NULLIF(cda.country_daily_avg_amount, 0)
      + COALESCE(sd.staff_amount / NULLIF(cd.daily_amount, 0), 0)
      + COALESCE(std.store_amount / NULLIF(cd.daily_amount, 0), 0)
    ) AS risk_score
  FROM customer_day_with_baseline AS cd
  JOIN customer_geo AS cg
    ON cg.customer_id = cd.customer_id
  JOIN country_day AS cda
    ON cda.country = cg.country
   AND cda.payment_day = cd.payment_day
  LEFT JOIN staff_distribution AS sd
    ON sd.customer_id = cd.customer_id
   AND sd.payment_day = cd.payment_day
   AND sd.rn = 1
  LEFT JOIN store_distribution AS std
    ON std.customer_id = cd.customer_id
   AND std.payment_day = cd.payment_day
   AND std.rn = 1
  WHERE cd.personal_30d_days >= 3
    AND cd.personal_30d_avg_amount > 0
    AND cda.country_daily_avg_amount > 0
    AND cd.payment_count >= 3
    AND cd.daily_amount >= cd.personal_30d_avg_amount * 3
    AND cd.daily_amount >= cda.country_daily_avg_amount
)
SELECT
  RANK() OVER (
    ORDER BY risk_score DESC, daily_amount DESC, payment_count DESC
  ) AS suspicious_rank,
  customer_id,
  customer_name,
  email,
  country,
  city,
  payment_day,
  payment_count,
  ROUND(daily_amount, 2) AS daily_amount,
  ROUND(personal_30d_avg_amount, 2) AS personal_30d_avg_amount,
  ROUND(country_daily_avg_amount, 2) AS country_daily_avg_amount,
  ratio_to_personal_30d_avg,
  ratio_to_country_daily_avg,
  staff_count,
  store_count,
  staff_ids,
  store_ids,
  dominant_staff_id,
  dominant_staff_amount_share,
  dominant_store_id,
  dominant_store_amount_share,
  ROUND(risk_score, 4) AS risk_score
FROM scored
ORDER BY
  suspicious_rank,
  payment_day,
  customer_id;