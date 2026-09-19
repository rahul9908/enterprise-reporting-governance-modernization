-- Enterprise Reporting Modernization - reference SQL (SQL Server style)
-- Grain: one row per source system + order + order line.

WITH ranked_orders AS (
    SELECT o.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_system, order_id, line_id
               ORDER BY source_modified_ts DESC, ingestion_ts DESC
           ) AS survivor_rank,
           COUNT(*) OVER (PARTITION BY source_system, order_id, line_id) AS duplicate_count
    FROM stage.sales_orders o
    WHERE o.order_status NOT IN ('CANCELLED','TEST')
), clean_orders AS (
    SELECT * FROM ranked_orders WHERE survivor_rank = 1
), shipment_rollup AS (
    SELECT source_system, order_id, line_id,
           SUM(shipped_qty) AS shipped_qty,
           MAX(actual_delivery_date) AS actual_delivery_date,
           MAX(CASE WHEN shipment_status = 'DELIVERED' THEN 1 ELSE 0 END) AS delivered_flag
    FROM stage.shipments
    GROUP BY source_system, order_id, line_id
), invoice_rollup AS (
    SELECT source_system, order_id, line_id,
           MAX(invoice_id) AS invoice_id,
           MAX(invoice_date) AS invoice_date,
           SUM(CASE WHEN posting_status='POSTED' THEN gross_amount ELSE 0 END) AS gross_revenue,
           SUM(CASE WHEN posting_status='POSTED' THEN discount_amount ELSE 0 END) AS discount_amount,
           SUM(CASE WHEN posting_status='POSTED' AND credit_status='APPROVED' THEN credit_amount ELSE 0 END) AS approved_credit_amount,
           SUM(CASE WHEN posting_status='POSTED' THEN cogs_amount ELSE 0 END) AS cogs_amount
    FROM stage.invoices
    GROUP BY source_system, order_id, line_id
)
SELECT o.source_system, o.order_id, o.line_id AS order_line_id,
       o.order_date, o.customer_id, o.product_id, d.department_key,
       o.ordered_qty, o.unit_price, s.shipped_qty,
       CASE WHEN s.shipped_qty > o.ordered_qty THEN o.ordered_qty ELSE s.shipped_qty END AS capped_shipped_qty,
       o.promised_date, s.actual_delivery_date, s.delivered_flag,
       CASE WHEN s.delivered_flag=1 AND s.actual_delivery_date <= o.promised_date THEN 1 ELSE 0 END AS on_time_flag,
       i.invoice_id, i.invoice_date, i.gross_revenue, i.discount_amount, i.approved_credit_amount,
       i.gross_revenue - i.discount_amount - i.approved_credit_amount AS net_revenue,
       i.cogs_amount, o.source_file_name, o.ingestion_batch_id, o.ingestion_ts,
       o.duplicate_count
FROM clean_orders o
LEFT JOIN shipment_rollup s ON s.source_system=o.source_system AND s.order_id=o.order_id AND s.line_id=o.line_id
LEFT JOIN invoice_rollup i ON i.source_system=o.source_system AND i.order_id=o.order_id AND i.line_id=o.line_id
LEFT JOIN mart.bridge_department_alias a
  ON UPPER(LTRIM(RTRIM(o.department_alias)))=a.department_alias
 AND o.order_date >= a.effective_from AND o.order_date < a.effective_to
LEFT JOIN mart.dim_department d ON d.department_key=a.department_key;

-- Certification reconciliation control.
SELECT report_month,
       SUM(net_revenue) AS mart_net_revenue,
       MAX(gl.control_total) AS gl_net_revenue,
       SUM(net_revenue) - MAX(gl.control_total) AS variance_amount,
       (SUM(net_revenue) - MAX(gl.control_total)) / NULLIF(MAX(gl.control_total),0.0) AS variance_percent,
       CASE WHEN ABS(SUM(net_revenue)-MAX(gl.control_total)) <= 1000
                  AND ABS((SUM(net_revenue)-MAX(gl.control_total))/NULLIF(MAX(gl.control_total),0.0)) <= 0.005
            THEN 'PASS' ELSE 'FAIL' END AS certification_result
FROM mart.fact_order_line f
JOIN control.gl_monthly_total gl ON gl.report_month=f.report_month AND gl.metric_name='Net Revenue'
GROUP BY report_month;

