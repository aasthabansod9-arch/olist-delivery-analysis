# Power BI Dashboard

A one-page report that answers the project question: *why are orders late, and what does it cost in reviews and repeat purchases?*

## Data model

Two fact tables from PostgreSQL (`order_analysis`, one row per delivered order, and `item_analysis`, one row per item) plus a date table.

| From (one side) | To (many side) | Direction |
|---|---|---|
| `Dim_Date[Date]` | `order_analysis[PurchaseDate]` | Single |
| `order_analysis[order_id]` | `item_analysis[order_id]` | Single |

The two fact tables are related, not merged. Merging an order-level table with an item-level table repeats each order's revenue once per item. With the relationship, a State or Year slicer also filters the category chart.

Power Query steps: set data types, add `PurchaseDate = DateTime.Date([order_purchase_timestamp])`, and remove columns from `item_analysis` that duplicate `order_analysis` (`customer_state`, `purchase_month`, `is_late`, `delay_days`, `review_score`).

Date table:

```dax
Dim_Date =
ADDCOLUMNS(
    CALENDAR(DATE(2016,1,1), DATE(2018,12,31)),
    "Year", YEAR([Date]),
    "Month Start", DATE(YEAR([Date]), MONTH([Date]), 1),
    "Month Label", FORMAT([Date], "MMM yy")
)
```

## Measures

```dax
Orders = COUNTROWS(order_analysis)
Revenue = SUM(order_analysis[items_revenue])
Late Orders = SUM(order_analysis[is_late])
Late Rate = DIVIDE([Late Orders], [Orders])
Avg Review = AVERAGE(order_analysis[review_score])
Avg Delivery Days = AVERAGE(order_analysis[delivery_days])

1-Star Share =
DIVIDE(
    CALCULATE(COUNTROWS(order_analysis), order_analysis[review_score] = 1),
    COUNT(order_analysis[review_score])
)

Avg Review On Time = CALCULATE([Avg Review], order_analysis[is_late] = 0)
Avg Review Late    = CALCULATE([Avg Review], order_analysis[is_late] = 1)
Review Gap         = [Avg Review On Time] - [Avg Review Late]

Revenue MoM % =
VAR Prev = CALCULATE([Revenue], DATEADD(Dim_Date[Date], -1, MONTH))
RETURN DIVIDE([Revenue] - Prev, Prev)

Item Late Rate =
DIVIDE(
    SUMX(item_analysis, RELATED(order_analysis[is_late])),
    COUNTROWS(item_analysis)
)

Insight Text =
"Late deliveries lower the average review by "
    & FORMAT([Review Gap], "0.0") & " stars ("
    & FORMAT([Avg Review On Time], "0.0") & " vs "
    & FORMAT([Avg Review Late], "0.0") & ")"
```

## Visuals

| Visual | Fields | Notes |
|---|---|---|
| KPI cards (5) | Revenue, Orders, Avg Delivery Days, Late Rate, Avg Review | |
| Review score by delay bucket | `delay_bucket` x `Avg Review` | Axis fixed at 0 to 5. This is the headline chart. |
| Monthly revenue | `Dim_Date[Month Start]` x `Revenue` | Visual-level filter: Jan 2017 to Aug 2018 |
| Late rate by state | `customer_state` x `Late Rate` | Visual-level filter: Orders at least 200, sorted descending |
| Top 10 categories | `item_analysis[category]` x sum of `price` | Top N filter, coloured by `Item Late Rate` |
| Insight card | `Insight Text` | Updates with the slicers |
| Slicers | `Dim_Date[Year]`, `customer_state` | Dropdown style |

## Checks

KPI cards were validated against the SQL results before building any charts: 96,470 delivered orders, 6.77% late, and average review 4.16 overall (4.29 on time, 2.27 late).
