SELECT COALESCE(AVG(CAST(d2.day_amount AS REAL)), 0.0)
            FROM daily_by_customer AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.payment_day >= DATE(d.payment_day, '-30 days')
              AND d2.payment_day <  d.payment_day
        ) AS avg_prev_30d_day_amount
    FROM daily_by_customer AS d
),
suspicious_days AS (
    SELECT
        d.*,
        CASE
            WHEN d.avg_prev_30d_day_amount > 0
            THEN d.day_amount / d.avg_prev_30d_day_amount
            ELSE NULL
        END AS exceed_ratio
    FROM daily_with_personal_avg AS d
    WHERE d.payment_count >= 3
      AND d.day_amount >= 2 * d.avg_prev_30d_day_amount
      AND d.distinct_staff_count >= 2
      AND d.distinct_store_count >= 2
      AND d.cross_country_store_payment_count >= 1
),
days_ranked AS (
    SELECT
        sd.*,
        RANK() OVER (
            PARTITION BY sd.customer_id
            ORDER BY sd.exceed_ratio DESC, sd.day_amount DESC, sd.payment_day
        ) AS customer_day_exceed_rank
    FROM suspicious_days AS sd
)
SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country_name,
    cty.d02 AS city_name,
    dr.payment_day,
    dr.payment_count,
    ROUND(dr.day_amount, 2) AS day_amount,
    dr.distinct_staff_count,
    dr.distinct_store_count,
    dr.cross_country_store_payment_count,
    ROUND(dr.exceed_ratio, 3) AS exceed_ratio,
    dr.customer_day_exceed_rank
FROM days_ranked AS dr
JOIN cus AS c
  ON c.h01 = dr.customer_id
JOIN adr AS a
  ON a.e01 = c.h06
JOIN cty
  ON cty.d01 = a.e05
JOIN cnt
  ON cnt.c01 = cty.d03
ORDER BY
    country_name,
    first_name,
    exceed_ratio DESC,
    dr.payment_day,
    customer_id;