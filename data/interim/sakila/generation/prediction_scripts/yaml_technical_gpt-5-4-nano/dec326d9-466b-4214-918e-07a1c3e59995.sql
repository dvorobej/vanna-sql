WITH win7 AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS win_end_date,
    SUM(CAST(p.p05 AS REAL)) AS win_sum_7d,
    COUNT(p.p01) AS win_pay_count_7d
  FROM pay AS p
  GROUP BY
    p.p02,
    date(p.p06)
),
win7_scored AS (
  SELECT
    w.customer_id,
    w.win_end_date,
    w.win_sum_7d,
    w.win_pay_count_7d,
    (
      SELECT AVG(w2.win_sum_7d)
      FROM win7 AS w2
      WHERE w2.customer_id = w.customer_id
        AND w2.win_end_date >= date(w.win_end_date, '-37 days')
        AND w2.win_end_date < date(w.win_end_date, '-7 days')
    ) AS hist_avg_win_sum_30d,
    (
      SELECT AVG(w2.win_pay_count_7d * 1.0)
      FROM win7 AS w2
      WHERE w2.customer_id = w.customer_id
        AND w2.win_end_date >= date(w.win_end_date, '-37 days')
        AND w2.win_end_date < date(w.win_end_date, '-7 days')
    ) AS hist_avg_win_pay_count_30d
  FROM win7 AS w
),
selected_windows AS (
  SELECT
    customer_id,
    win_end_date AS suspicious_date,
    date(win_end_date, '-6 days') AS win_start_date,
    win_sum_7d AS suspicious_sum_7d,
    win_pay_count_7d AS suspicious_pay_count_7d,
    hist_avg_win_sum_30d
  FROM win7_scored
  WHERE hist_avg_win_sum_30d IS NOT NULL
    AND hist_avg_win_sum_30d > 0
    AND win_sum_7d >= 3.0 * hist_avg_win_sum_30d
    AND win_pay_count_7d >= 5
),
window_films AS (
  SELECT
    sw.customer_id,
    sw.suspicious_date,
    COUNT(DISTINCT f.i01) AS distinct_films_count
  FROM selected_windows AS sw
  JOIN pay AS p
    ON p.p02 = sw.customer_id
   AND date(p.p06) BETWEEN sw.win_start_date AND sw.win_end_date
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN flm AS f
    ON f.i01 = i.n02
  GROUP BY
    sw.customer_id,
    sw.suspicious_date
),
window_staff_stores AS (
  SELECT
    sw.customer_id,
    sw.suspicious_date,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count
  FROM selected_windows AS sw
  JOIN pay AS p
    ON p.p02 = sw.customer_id
   AND date(p.p06) BETWEEN sw.win_start_date AND sw.win_end_date
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    sw.customer_id,
    sw.suspicious_date
),
window_details AS (
  SELECT
    sw.customer_id,
    sw.suspicious_date,
    sw.win_start_date,
    sw.suspicious_sum_7d,
    sw.suspicious_pay_count_7d,
    ws.distinct_staff_count,
    ws.distinct_store_count,
    wf.distinct_films_count,
    cnt.c02 AS country_name,
    cty.d02 AS city_name,
    adr.e01 AS address_id
  FROM selected_windows AS sw
  JOIN cus AS c
    ON c.h01 = sw.customer_id
  JOIN adr
    ON adr.e01 = c.h06
  JOIN cty
    ON cty.d01 = adr.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
  LEFT JOIN window_staff_stores AS ws
    ON ws.customer_id = sw.customer_id
   AND ws.suspicious_date = sw.suspicious_date
  LEFT JOIN window_films AS wf
    ON wf.customer_id = sw.customer_id
   AND wf.suspicious_date = sw.suspicious_date
)
SELECT
  customer_id,
  address_id,
  country_name,
  city_name,
  win_start_date,
  suspicious_date,
  suspicious_pay_count_7d AS payment_count_7d,
  ROUND(suspicious_sum_7d, 2) AS suspicious_sum_7d,
  distinct_staff_count,
  distinct_store_count,
  distinct_films_count,
  RANK() OVER (ORDER BY suspicious_sum_7d DESC, suspicious_pay_count_7d DESC, customer_id) AS suspicious_rank_overall
FROM window_details
ORDER BY
  suspicious_sum_7d DESC,
  suspicious_pay_count_7d DESC,
  customer_id;