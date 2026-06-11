WITH daily_base AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS payment_sum
  FROM pay AS p
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_stats AS (
  SELECT
    db.*,
    AVG(db.payment_sum) OVER (
      PARTITION BY db.customer_id
      ORDER BY db.day_date
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ) AS rolling_avg_sum_30d,
    -- sample stddev (SQLite doesn't have built-in STDDEV;