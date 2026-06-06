WITH base_payments AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    p.p05 AS amount,
    p.p06 AS payment_ts,
    date(p.p06) AS payment_date,
    strftime('%Y-%m', p.p06) AS payment_month,
    c.h06 AS address_id,
    city.d03 AS country_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS city
    ON city.d01 = a.e05
),
monthly_customer AS (
  SELECT
    customer_id,
    country_id,
    payment_month,
    COUNT(*) AS month_payment_count,
    SUM(amount) AS month_total_amount,
    AVG(amount) AS month_avg_amount
  FROM base_payments
  GROUP BY customer_id, country_id, payment_month
),
customer_history AS (
  SELECT
    m.*,
    AVG(month_total_amount) OVER (
      PARTITION BY customer_id
      ORDER BY payment_month
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev_3m_avg_amount,
    AVG(month_payment_count) OVER (
      PARTITION BY customer_id
      ORDER BY payment_month
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev_3m_avg_count
  FROM monthly_customer AS m
),
daily_staff_store AS (
  SELECT
    customer_id,
    payment_date,
    COUNT(*) AS day_payment_count,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    COUNT(DISTINCT COALESCE(rental_id, payment_id)) AS distinct_store_proxy_count
  FROM base_payments
  GROUP BY customer_id, payment_date
),
monthly_country AS (
  SELECT
    country_id,
    payment_month,
    AVG(month_total_amount) AS country_avg_month_total,
    SUM(month_total_amount) AS country_month_total
  FROM monthly_customer
  GROUP BY country_id, payment_month
),
scored AS (
  SELECT
    h.customer_id,
    h.country_id,
    h.payment_month,
    h.month_payment_count,
    h.month_total_amount,
    h.month_avg_amount,
    h.prev_3m_avg_amount,
    h.prev_3m_avg_count,
    d.day_payment_count,
    d.distinct_staff_count,
    d.distinct_store_proxy_count,
    mc.country_avg_month_total,
    CASE
      WHEN COALESCE(h.prev_3m_avg_amount, 0) > 0 THEN h.month_total_amount / h.prev_3m_avg_amount
      ELSE NULL
    END AS amount_vs_history,
    CASE
      WHEN COALESCE(h.prev_3m_avg_count, 0) > 0 THEN h.month_payment_count / h.prev_3m_avg_count
      ELSE NULL
    END AS count_vs_history,
    CASE
      WHEN COALESCE(mc.country_avg_month_total, 0) > 0 THEN h.month_total_amount / mc.country_avg_month_total
      ELSE NULL
    END AS amount_vs_country
  FROM customer_history AS h
  LEFT JOIN daily_staff_store AS d
    ON d.customer_id = h.customer_id
   AND strftime('%Y-%m', d.payment_date) = h.payment_month
  LEFT JOIN monthly_country AS mc
    ON mc.country_id = h.country_id
   AND mc.payment_month = h.payment_month
),
ranked AS (
  SELECT
    s.*,
    PERCENT_RANK() OVER (
      PARTITION BY payment_month
      ORDER BY amount_vs_country DESC
    ) AS country_rank_pct
  FROM scored AS s
)
SELECT
  r.customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  r.payment_month,
  r.month_payment_count,
  ROUND(r.month_total_amount, 2) AS month_total_amount,
  ROUND(r.month_avg_amount, 2) AS month_avg_amount,
  ROUND(r.prev_3m_avg_amount, 2) AS prev_3m_avg_amount,
  ROUND(r.prev_3m_avg_count, 2) AS prev_3m_avg_count,
  ROUND(r.amount_vs_history, 2) AS amount_vs_history,
  ROUND(r.count_vs_history, 2) AS count_vs_history,
  ROUND(r.day_payment_count * 1.0 / NULLIF(r.month_payment_count, 0), 2) AS daily_series_share,
  ROUND(r.distinct_staff_count * 1.0 / NULLIF(r.day_payment_count, 0), 2) AS staff_diversity_share,
  ROUND(r.distinct_store_proxy_count * 1.0 / NULLIF(r.day_payment_count, 0), 2) AS store_diversity_share,
  ROUND(r.amount_vs_country, 2) AS amount_vs_country,
  ROUND(r.country_rank_pct, 4) AS country_rank_pct,
  CASE
    WHEN r.country_rank_pct >= 0.95
      OR EXISTS (
        SELECT 1
        FROM base_payments AS b1
        JOIN base_payments AS b2
          ON b2.customer_id = b1.customer_id
         AND b2.payment_ts > b1.payment_ts
         AND julianday(b2.payment_ts) - julianday(b1.payment_ts) <= 1.0
        JOIN base_payments AS b3
          ON b3.customer_id = b1.customer_id
         AND b3.payment_ts > b2.payment_ts
         AND julianday(b3.payment_ts) - julianday(b1.payment_ts) <= 1.0
        WHERE b1.customer_id = r.customer_id
          AND strftime('%Y-%m', b1.payment_ts) = r.payment_month
          AND b1.staff_id <> b2.staff_id
          AND b1.staff_id <> b3.staff_id
          AND b2.staff_id <> b3.staff_id
      )
    THEN 'подозрительно'
    ELSE 'норма'
  END AS risk_mark
FROM ranked AS r
JOIN cus AS c
  ON c.h01 = r.customer_id
WHERE r.country_rank_pct >= 0.95
   OR EXISTS (
      SELECT 1
      FROM base_payments AS b1
      JOIN base_payments AS b2
        ON b2.customer_id = b1.customer_id
       AND b2.payment_ts > b1.payment_ts
       AND julianday(b2.payment_ts) - julianday(b1.payment_ts) <= 1.0
      JOIN base_payments AS b3
        ON b3.customer_id = b1.customer_id
       AND b3.payment_ts > b2.payment_ts
       AND julianday(b3.payment_ts) - julianday(b1.payment_ts) <= 1.0
      WHERE b1.customer_id = r.customer_id
        AND strftime('%Y-%m', b1.payment_ts) = r.payment_month
        AND b1.staff_id <> b2.staff_id
        AND b1.staff_id <> b3.staff_id
        AND b2.staff_id <> b3.staff_id
   )
ORDER BY
  r.payment_month,
  r.month_total_amount DESC,
  r.customer_id;