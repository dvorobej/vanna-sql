WITH monthly_payments AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_full_name,
    cnt_c.c01 AS customer_country_id,
    cnt_c.c02 AS customer_country,
    strftime('%Y-%m', p.p06) AS payment_month,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS monthly_amount,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count,
    MAX(CASE WHEN cnt_c.c01 <> cnt_s.c01 THEN 1 ELSE 0 END) AS has_other_country_store_payment
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS adr_c
    ON adr_c.e01 = c.h06
  JOIN cty AS cty_c
    ON cty_c.d01 = adr_c.e05
  JOIN cnt AS cnt_c
    ON cnt_c.c01 = cty_c.d03
  JOIN stf AS s
    ON s.o01 = p.p03
  JOIN sto AS st
    ON st.j01 = s.o07
  JOIN adr AS adr_s
    ON adr_s.e01 = st.j03
  JOIN cty AS cty_s
    ON cty_s.d01 = adr_s.e05
  JOIN cnt AS cnt_s
    ON cnt_s.c01 = cty_s.d03
  GROUP BY
    c.h01,
    c.h03,
    c.h04,
    cnt_c.c01,
    cnt_c.c02,
    strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
  SELECT
    mp.*,
    AVG(mp.monthly_amount) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.payment_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS historical_avg_monthly_amount
  FROM monthly_payments AS mp
),
qualified AS (
  SELECT
    *,
    monthly_amount - historical_avg_monthly_amount AS deviation_from_historical_avg
  FROM monthly_with_history
  WHERE payment_count >= 5
    AND historical_avg_monthly_amount > 0
    AND monthly_amount > historical_avg_monthly_amount * 2
    AND has_other_country_store_payment = 1
)
SELECT
  payment_month,
  customer_full_name,
  customer_country,
  payment_count,
  ROUND(monthly_amount, 2) AS monthly_amount,
  ROUND(historical_avg_monthly_amount, 2) AS historical_avg_monthly_amount,
  ROUND(deviation_from_historical_avg, 2) AS deviation_from_historical_avg,
  distinct_staff_count,
  distinct_store_count,
  RANK() OVER (
    ORDER BY deviation_from_historical_avg DESC
  ) AS excess_rank
FROM qualified
ORDER BY
  excess_rank,
  payment_month,
  customer_full_name;