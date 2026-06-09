SELECT AVG(dc_prev.day_amount)
      FROM daily_customer dc_prev
      WHERE dc_prev.customer_id = dc.customer_id
        AND dc_prev.payment_date >= DATE(dc.payment_date, '-30 day')
        AND dc_prev.payment_date < dc.payment_date
    ) AS personal_avg_30d
  FROM daily_customer dc
),
country_thresholds AS (
  -- 95-й перцентиль дневных сумм по стране (по всем клиентам) через ранжирование
  SELECT
    country_name,
    MAX(day_amount) AS p95_day_amount
  FROM (
    SELECT
      country_name,
      day_amount,
      ROW_NUMBER() OVER (
        PARTITION BY country_name
        ORDER BY day_amount
      ) AS rn,
      COUNT(*) OVER (PARTITION BY country_name) AS cnt
    FROM daily_customer
  ) x
  WHERE rn >= ((95 * cnt + 99) / 100) -- ceil(0.95*cnt)
  GROUP BY country_name
),
suspicious_days AS (
  SELECT
    dwp.customer_id,
    dwp.payment_date,
    dwp.country_name,
    dwp.city_name,
    dwp.registration_store_id,
    dwp.payment_count,
    dwp.day_amount,
    dwp.personal_avg_30d,
    (dwp.day_amount - dwp.personal_avg_30d) AS deviation_from_avg,
    (dwp.day_amount / dwp.personal_avg_30d) AS spike_ratio,
    ct.p95_day_amount
  FROM daily_with_personal_avg dwp
  JOIN country_thresholds ct
    ON ct.country_name = dwp.country_name
  WHERE dwp.personal_avg_30d IS NOT NULL
    AND dwp.personal_avg_30d > 0
    AND dwp.day_amount >= 3.0 * dwp.personal_avg_30d
    AND dwp.day_amount > ct.p95_day_amount
),
ranked AS (
  SELECT
    sd.*,
    RANK() OVER (
      PARTITION BY sd.country_name, sd.payment_date
      ORDER BY sd.day_amount DESC
    ) AS client_spike_rank_in_country
  FROM suspicious_days sd
)
SELECT
  r.payment_date AS spike_date,
  c.h03 AS first_name,
  c.h04 AS last_name,
  r.country_name AS country,
  r.city_name AS city,
  r.registration_store_id AS store_id,
  r.payment_count,
  ROUND(r.day_amount, 2) AS day_amount,
  ROUND(r.personal_avg_30d, 2) AS avg_prev_30d,
  ROUND(r.deviation_from_avg, 2) AS deviation_from_avg,
  r.client_spike_rank_in_country
FROM ranked r
JOIN cus c ON c.h01 = r.customer_id
ORDER BY
  r.country_name,
  r.payment_date,
  r.client_spike_rank_in_country,
  r.customer_id;