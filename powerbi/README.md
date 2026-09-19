# Power BI dashboard handoff

This folder is the implementation specification for the **Enterprise Reporting Modernization** Power BI report. It is designed for a four-page report: Executive Summary, Revenue & Margin, Operations, and Data Quality.

## Model

- `FactOrderLine` at one row per source system + order + order line
- `FactBudget` at month + department
- Conformed `DimDate`, `DimDepartment`, `DimProduct`, `DimCustomer`, and `DimRegion`
- Single-direction one-to-many relationships from dimensions to facts
- Hide technical keys and raw amount columns; expose certified measures only
- Incremental refresh by `InvoiceDate`; retain 24 months and refresh the last 3 months

## Page design

1. **Executive Summary**: certification banner; Net Revenue, Gross Margin %, OTD %, Fill Rate %, and Budget Variance cards; 13-month trend; department variance bar chart; top exceptions.
2. **Revenue & Margin**: monthly revenue/margin trends, budget comparison, department/product matrix, order-line drill-through.
3. **Operations**: OTD, Fill Rate, and Return Rate by region/product/carrier; late-order detail.
4. **Data Quality**: refresh timestamp, batch ID, rule pass rate, rejected/quarantined counts, ledger reconciliation, and exception aging.

## Build checklist

- Import the curated mart views produced by `../sql/reporting_mart.sql`.
- Create measures from `measures.dax`; mark the Date table.
- Configure region-based RLS using `UserRegionBridge[UPN] = USERPRINCIPALNAME()`.
- Add a page-level data-as-of/certification banner to all pages.
- Add drill-through fields: Order ID, Order Line ID, Batch ID, Source File, and Rule ID.
- Validate against `../deliverables/Enterprise_Reporting_UAT_Workbook.xlsx`.

The repository does not contain a binary `.pbix`; Power BI Desktop should be used to bind credentials and publish the report in the target tenant.

