SELECT value
      FROM (
        SELECT cm2.month_sum AS value,
               ROW_NUMBER() OVER (PARTITION BY cm2.h02, cm2.country_id, cm2.month_start ORDER BY cm2.month_sum) AS rn,
               COUNT(*) OVER (PARTITION BY cm2.h02, cm2.country_id, cm2.month_start) AS cnt
        FROM cust_month_with_prev cm2
      )
      WHERE rn = CAST(0.95 * (cnt - 1) + 1 AS INTEGER)
    ) AS p95_month_sum
  FROM cust_month_with_prev cm
  GROUP BY cm.h02, cm.country_id, cm.month_start
),
risk_months AS (
  SELECT
    cmwp.*,
    scp95.p95_month_sum
  FROM cust_month_with_prev cmwp
  JOIN store_country_p95 scp95
    ON scp95.h02 = cmwp.h02
   AND scp95.country_id = cmwp.country_id
   AND scp95.month_start = cmwp.month_start
  WHERE cmwp.prev_avg_month_sum IS NOT NULL
    AND cmwp.payment_count > 0
    AND cmwp.month_sum > 3.0 * cmwp.prev_avg_month_sum
    AND cmwp.month_sum > scp95.p95_month_sum
),
ren_delay AS (
  SELECT
    r.q01 AS rental_id,
    CASE
      WHEN r.q05 IS NOT NULL THEN 1 ELSE 0
    END AS is_overdue_return
  FROM ren r
),
monthly_overdue_share AS (
  SELECT
    p.p02 AS h01,
    c.h02 AS h02,
    date(p.p06, 'start of month') AS month_start,
    SUM(CASE WHEN rd.is_overdue_return = 1 THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(p.p01), 0) AS overdue_return_payment_share,
    SUM(CASE WHEN rd.is_overdue_return = 1 THEN p.p05 ELSE 0 END) * 1.0 / NULLIF(SUM(p.p05), 0) AS overdue_return_amount_share
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  JOIN ren_delay rd ON rd.rental_id = p.p04
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    c.h02,
    date(p.p06, 'start of month')
),
store_month_rank AS (
  SELECT
    cm.h01,
    cm.month_start,
    RANK() OVER (
      PARTITION BY cm.h02, cm.month_start
      ORDER BY cm.month_sum DESC
    ) AS store_month_payment_rank
  FROM cust_month cm
)
SELECT
  rm.h01,
  c.h03 AS h03,
  c.h04 AS h04,
  rm.country_id AS c02,
  rm.d01_city AS d02,
  c.h02 AS j01,
  strftime('%Y-%m', rm.month_start) AS month,
  ROUND(rm.month_sum, 2) AS month_sum,
  rm.payment_count,
  rm.distinct_staff_count AS distinct_staff_count,
  COALESCE(mos.overdue_return_payment_share, 0) AS overdue_return_payment_share,
  COALESCE(mos.overdue_return_amount_share, 0) AS overdue_return_amount_share,
  smr.store_month_payment_rank
FROM risk_months rm
JOIN cus c
  ON c.h01 = rm.h01
LEFT JOIN monthly_overdue_share mos
  ON mos.h01 = rm.h01
 AND mos.h02 = rm.h02
 AND mos.month_start = rm.month_start
LEFT JOIN store_month_rank smr
  ON smr.h01 = rm.h01
 AND smr.month_start = rm.month_start
ORDER BY
  rm.month_start,
  rm.h02,
  rm.country_id,
  smr.store_month_payment_rank,
  rm.month_sum DESC;