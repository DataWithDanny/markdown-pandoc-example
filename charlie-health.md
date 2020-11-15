# Health Analytics Case Study

There are 2 datasets included in this case study:

**users**

**user_health_logs**

## Part 1

What is the distribution (count) of health logs by datatype? What does this tell you about the data?

```SQL
WITH counts AS (
SELECT
  datatype,
  datatype_name,
  COUNT(*) AS record_counts
FROM health.user_health_logs
GROUP BY datatype, datatype_name
)
SELECT
  *,
  ROUND(
    100 * record_counts::NUMERIC / SUM(record_counts)
    OVER ()
    , 2
   ) AS record_percentage
FROM counts
ORDER BY datatype;
```

|datatype | datatype_name  | record_counts | record_percentage |
| ------- | -------------- | ------------- | ----------------- |
 0        | blood_glucose  |         38692 |             88.15 |
 4        | blood_pressure |          2417 |              5.51 |
 6        | weight         |          2782 |              6.34 |

~88% of values are from blood glucose measurements with the remaining split evenly between blood pressure and weight measurements.

## Part 2

What is the average value for each datatype? Does anything here seem interesting or odd? Should we filter out any edge cases or anomalies?

```sql
SELECT
  datatype,
  datatype_name,
  AVG(measurementvalue) as average_value
FROM health.user_health_logs
GROUP BY
  datatype,
  datatype_name
ORDER BY
  datatype
```

| datatype | datatype_name  |   average_value    |
| -------- | -------------- | ------------------ |
| 0        | blood_glucose  | 177.34859536245202 |
| 4        | blood_pressure |  95.40408151269052 |
| 6        | weight         | 28786.846657296002 |

Blood Glucose and Weight seem to be very high whilst we only seem to have one value for blood pressure.

Further to this it seems that measurementvalue for blood pressure measures are the only records with valid data in the `bloodpressuresystolic` and `bloodpressurediastolic` columns.

Instead we should split the dataset into datatype in ('0', '6') for blood glucose and weight values and look at measurementvalue exclusively, whilst datatype = '4' should inspect the two blood pressure columns.

```sql
SELECT
  datatype,
  datatype_name,
  AVG(measurementvalue) as average_value
FROM health.user_health_logs
WHERE
  datatype IN ('0', '6')
GROUP BY
  datatype,
  datatype_name
ORDER BY
  datatype
```

| datatype | datatype_name  |   average_value    |
| -------- | -------------- | ------------------ |
| 0        | blood_glucose  | 177.34859536245202 |
| 6        | weight         | 28786.846657296002 |

```sql
SELECT
  datatype,
  datatype_name,
  AVG(bloodpressuresystolic) AS average_systolic,
  AVG(bloodpressurediastolic) AS average_diastolic
FROM health.user_health_logs
WHERE
  datatype = '4'
GROUP BY
  datatype,
  datatype_name
ORDER BY
  datatype
```

| datatype | datatype_name  |  average_systolic  | average_diastolic |
| -------- | -------------- | ------------------ | ----------------- |
| 4        | blood_pressure | 126.33926354985519 | 79.5059991725279  |

### Naive Averages

| Data Type Name | Average Measure |
| BP Diastolic   |  79.51          |
| BP Systolic    | 126.34          |
| Blood Glucose  | 177.35          |
| Weight         | 28,786.85       |

### Further Analysis Blood

#### Glucose & Weight

If we go further and take a look at the highest records for each of these values - we can identify whether large outliers are impacting the averages of blood glucose and weight measures.

```sql
WITH ranked_values AS (
SELECT
  datatype_name,
  measurementvalue,
  ROW_NUMBER() OVER (
    PARTITION BY datatype_name ORDER BY measurementvalue DESC
  ) as value_rank
FROM health.user_health_logs
WHERE
    datatype in ('0', '6')
)
SELECT * FROM ranked_values
WHERE value_rank <= 20
ORDER BY
  datatype_name,
  measurementvalue DESC;
```

| datatype_name | measurementvalue | value_rank |
|-------------- | ---------------- | ---------- |
| blood_glucose |           227228 |          1 |
| blood_glucose |             5400 |          2 |
| blood_glucose |             4500 |          3 |
| blood_glucose |             2268 |          4 |
| blood_glucose |           2044.8 |          5 |
| blood_glucose |             1944 |          6 |
| blood_glucose |             1530 |          7 |
| blood_glucose |             1494 |          8 |
| blood_glucose |             1080 |          9 |
| blood_glucose |              992 |         10 |
| blood_glucose |              900 |         11 |
| blood_glucose |              900 |         12 |
| blood_glucose |    601.720675231 |         13 |
| blood_glucose |    601.720675231 |         14 |
| blood_glucose |              600 |         15 |
| blood_glucose |              600 |         16 |
| blood_glucose |              600 |         17 |
| blood_glucose |              600 |         18 |
| blood_glucose |        585.50661 |         19 |
| blood_glucose |              573 |         20 |
| weight        |         39642120 |          1 |
| weight        |         39642120 |          2 |
| weight        |           576484 |          3 |
| weight        |       200.487664 |          4 |
| weight        |            190.4 |          5 |
| weight        |        188.69427 |          6 |
| weight        |         186.8799 |          7 |
| weight        |        185.51913 |          8 |
| weight        |       175.086512 |          9 |
| weight        |       173.725736 |         10 |
| weight        |         170.5506 |         11 |
| weight        |         170.5506 |         12 |
| weight        |         170.5506 |         13 |
| weight        |              164 |         14 |
| weight        |      157.5778608 |         15 |
| weight        |        149.68536 |         16 |
| weight        |        145.14944 |         17 |
| weight        |       144.242256 |         18 |
| weight        |      141.1578304 |         19 |
| weight        |       138.799152 |         20 |

Here it seems best to cutoff blood sugar at that 601.74 level as it looks like blood sugar levels higher than 600 can cause death and coma. For the weight values it seems alright to cut off the weight from the 200.48 level as the other weights are equivalent to 500 tonnes!

**Lower Percentiles**

Let's also investigate the lower values also by taking a look at the total distribution by percentiles, specifically the first 5 percent of values in ascending order.

The following query inspects the deciles to show the discrepancies for blood glucose and weight

```sql
WITH percentile_values AS (
  SELECT
    datatype_name,
    measurementvalue,
    NTILE(100) OVER (
      PARTITION BY datatype_name
      ORDER BY
        measurementvalue
    ) AS percentile
  FROM
    health.user_health_logs
  WHERE
    datatype in ('0', '6')
)
SELECT
  datatype_name,
  percentile,
  MIN(measurementvalue) AS floor_value,
  MAX(measurementvalue) AS ceiling_value,
  COUNT(*) AS percentile_counts
FROM
  percentile_values
GROUP BY
  datatype_name,
  percentile
HAVING percentile <= 10
ORDER BY
  datatype_name,
  percentile;
```

|  datatype_name | percentile | floor_value | ceiling_value | percentile_counts |
| -------------- | ---------- | ----------- | ------------- | ----------------- |
|  blood_glucose |          1 |          -1 |            57 |               387 |
|  blood_glucose |          2 |          57 |            68 |               387 |
|  blood_glucose |          3 |          68 |          75.6 |               387 |
|  blood_glucose |          4 |        75.6 |            81 |               387 |
|  blood_glucose |          5 |          81 |            84 |               387 |
|  blood_glucose |          6 |          84 |            87 |               387 |
|  blood_glucose |          7 |          87 |            90 |               387 |
|  blood_glucose |          8 |          90 |            92 |               387 |
|  blood_glucose |          9 |          92 |            94 |               387 |
|  blood_glucose |         10 |          94 |            96 |               387 |
|  weight        |          1 |           0 |     29.029888 |                28 |
|  weight        |          2 |    29.48348 |    32.0689544 |                28 |
|  weight        |          3 |   32.205032 |     35.380177 |                28 |
|  weight        |          4 |   35.380177 |      36.74095 |                28 |
|  weight        |          5 |    36.74095 |     37.194546 |                28 |
|  weight        |          6 |   37.194546 |     38.101727 |                28 |
|  weight        |          7 |   38.101727 |      39.00891 |                28 |
|  weight        |          8 |    39.00891 |      40.36969 |                28 |
|  weight        |          9 |    40.36969 |      41.27687 |                28 |
|  weight        |         10 |    41.27687 |      43.54483 |                28 |

### Blood Glucose

Let's dive deeper into that first percentile by taking a count of records by measurementvalue.

```sql
SELECT
  ROUND(measurementvalue) as rounded_value,
  COUNT(*) AS counts
FROM
  health.user_health_logs
WHERE
  datatype = '0'
  AND measurementvalue <= 57
GROUP BY
  rounded_value
ORDER BY
  rounded_value
```

|  rounded_value | counts |
| -------------- | ------ |
|             -1 |      1 |
|              0 |      8 |
|              1 |      1 |
|              2 |      5 |
|              3 |      1 |
|              4 |      3 |
|              5 |      8 |
|              6 |     37 |
|              7 |     33 |
|              8 |     22 |
|              9 |      5 |
|             10 |      3 |
|             11 |      4 |
|             12 |      2 |
|             15 |      1 |
|             18 |      1 |
|             21 |      1 |
|             33 |      1 |
|             39 |     17 |
|             40 |      7 |
|             41 |      5 |
|             42 |      1 |
|             43 |      7 |
|             44 |      8 |
|             45 |     12 |
|             46 |      7 |
|             47 |      7 |
|             48 |      9 |
|             49 |      7 |
|             50 |     14 |
|             51 |     14 |
|             52 |     25 |
|             53 |     19 |
|             54 |     25 |
|             55 |     19 |
|             56 |     22 |
|             57 |     27 |


A quick Google shows that low blood sugar levels below 70mg/dL is low and can harm you, going under 20 can mean loss of consciousness and death! 

Let's perhaps err on the safe side and just keep all values which are greater than 0.

### Weight Deep Dive

Let us do the same for the weight fields - this time using the 1st percentile cut off of 29kg

```sql
SELECT
  ROUND(measurementvalue) as rounded_value,
  COUNT(*) AS counts
FROM
  health.user_health_logs
WHERE
  datatype = '6'
  AND measurementvalue <= 29
GROUP BY
  rounded_value
ORDER BY
  rounded_value
```

| rounded_value | counts |
| ------------- | ------ |
|             0 |      2 |
|             2 |      3 |
|             8 |      1 |
|            10 |      1 |
|            11 |      1 |
|            13 |      1 |
|            15 |      1 |
|            18 |      1 |
|            21 |      1 |
|            24 |      1 |
|            25 |      1 |
|            26 |      2 |
|            27 |      4 |
|            28 |      3 |
|            29 |      2 |

It also seems prudent to only keep values which are positive here too.

### Blood Pressure Deep Dive

Let's also complete the same analysis for blood pressure values using their respective columns.

```sql
WITH systolic AS (
  SELECT
    'systolic' as bp_measure,
    bloodpressuresystolic AS bp_value,
    NTILE(10) OVER (
      ORDER BY
        bloodpressuresystolic
    ) AS percentile
  FROM
    health.user_health_logs
  WHERE
    datatype = '4'
),
diastolic AS (
  SELECT
    'diastolic' as bp_measure,
    bloodpressurediastolic as bp_value,
    NTILE(10) OVER (
      ORDER BY
        bloodpressurediastolic
    ) AS percentile
  FROM
    health.user_health_logs
  WHERE
    datatype = '4'
)
, bp_measures AS (
  SELECT * FROM systolic
  UNION ALL
  SELECT * FROM diastolic
)
SELECT
  bp_measure,
  percentile,
  MIN(bp_value) AS floor_value,
  MAX(bp_value) AS ceiling_value,
  COUNT(*) AS percentile_counts
FROM
  bp_measures
GROUP BY
  bp_measure,
  percentile
ORDER BY
  bp_measure,
  percentile;
```

| bp_measure | percentile | floor_value | ceiling_value | percentile_counts |
| ---------- | ---------- | ----------- | ------------- | ----------------- |
| diastolic  |          1 |           1 |            67 |               242 |
| diastolic  |          2 |          67 |            71 |               242 |
| diastolic  |          3 |          71 |            74 |               242 |
| diastolic  |          4 |          74 |            77 |               242 |
| diastolic  |          5 |          77 |            79 |               242 |
| diastolic  |          6 |          79 |            80 |               242 |
| diastolic  |          7 |          80 |            83 |               242 |
| diastolic  |          8 |          83 |            85 |               241 |
| diastolic  |          9 |          85 |            90 |               241 |
| diastolic  |         10 |          90 |          1914 |               241 |
| systolic   |          1 |           0 |           103 |               242 |
| systolic   |          2 |         103 |           111 |               242 |
| systolic   |          3 |         111 |           117 |               242 |
| systolic   |          4 |         117 |           122 |               242 |
| systolic   |          5 |         122 |           126 |               242 |
| systolic   |          6 |         126 |           130 |               242 |
| systolic   |          7 |         130 |           135 |               242 |
| systolic   |          8 |         135 |           140 |               241 |
| systolic   |          9 |         140 |           149 |               241 |
| systolic   |         10 |         149 |           204 |               241 |

From initial inspection that 1914 max diastolic blood pressure seems out of place - let's inspect that top percentile a bit further.

```sql
SELECT
  bloodpressuresystolic,
  COUNT(*) as counts
FROM health.user_health_logs
WHERE
  bloodpressuresystolic <= 103
  AND datatype = '4'
GROUP BY bloodpressuresystolic
ORDER BY bloodpressuresystolic;
```

| bloodpressurediastolic  | counts |
| ----------------------- | ------ |
|                    1914 |      1 |
|                     161 |      1 |
|                     160 |      1 |
|                     151 |      1 |
|                     150 |      1 |
|                     140 |      2 |
|                     128 |      1 |
|                     125 |      2 |
|                     121 |      1 |
|                     120 |     11 |
|                     118 |      1 |
|                     113 |      3 |
|                     112 |      2 |
|                     111 |      1 |
|                     110 |      1 |
|                     109 |      4 |
|                     108 |      2 |
|                     107 |      1 |
|                     106 |      5 |
|                     105 |      3 |
|                     104 |      4 |
|                     102 |      2 |
|                     101 |      3 |
|                     100 |     10 |
|                      99 |      4 |
|                      98 |      7 |
|                      97 |     11 |

This 1914 value looks out of place so it might be prudent to filter that out by putting a upper bound at 200 arbitrarily.

Probably we can take a look further at the distribution of values in the bottom percentiles for both values just to confirm there is nothing amiss...

```sql
SELECT
  bloodpressurediastolic,
  COUNT(*) as counts
FROM health.user_health_logs
WHERE
  bloodpressurediastolic >= 90
  AND datatype = '4'
GROUP BY bloodpressurediastolic
ORDER BY bloodpressurediastolic DESC;
```

| bloodpressuresystolic | counts |
| --------------------- | ------ |
|                     0 |      1 |
|                     2 |      1 |
|                    12 |      2 |
|                    13 |      1 |
|                    60 |      1 |
|                    67 |      1 |
|                    80 |      8 |
|                    81 |      1 |
|                    83 |      1 |
|                    84 |      1 |
|                    85 |      3 |
|                    86 |      1 |
|                    87 |      7 |
|                    88 |      1 |
|                    90 |     10 |
|                    91 |      8 |
|                    92 |      8 |
|                    93 |      6 |
|                    94 |      2 |
|                    95 |     13 |
|                    96 |     15 |
|                    97 |     27 |
|                    98 |     10 |
|                    99 |     18 |
|                   100 |     24 |
|                   101 |     26 |
|                   102 |     26 |
|                   103 |     31 |

```sql
SELECT
  bloodpressurediastolic,
  COUNT(*) as counts
FROM health.user_health_logs
WHERE
  bloodpressurediastolic <= 67
  AND datatype = '4'
GROUP BY bloodpressurediastolic
ORDER BY bloodpressurediastolic;
```

 bloodpressurediastolic | counts
------------------------+--------
                      1 |      2
                      8 |      2
                     31 |      3
                     36 |      1
                     42 |      1
                     44 |      1
                     46 |      2
                     50 |      1
                     51 |      1
                     53 |      1
                     55 |      2
                     57 |      1
                     58 |      3
                     59 |      4
                     60 |     12
                     61 |      8
                     62 |     24
                     63 |     21
                     64 |     28
                     65 |     33
                     66 |     40
                     67 |     55

### Conclusion

So to conclude: it looks like we can apply the following filters to the dataset accordingly

Blood Glucose and Weight Values

```sql
SELECT
  datatype,
  datatype_name,
  AVG(measurementvalue) as average_value
FROM health.user_health_logs
WHERE
  (
    -- glucose
    datatype = '0'
    AND measurementvalue > 0
    AND measurementvalue < 602
  )
  OR
    (
    -- weight
    datatype = '6'
    AND measurementvalue > 0
    AND measurementvalue < 201
  )
GROUP BY
  datatype,
  datatype_name
ORDER BY
  datatype
```

**Before adjustments**

| datatype | datatype_name  |   average_value    |
| -------- | -------------- | ------------------ |
| 0        | blood_glucose  | 177.34859536245202 |
| 6        | weight         | 28786.846657296002 |

**After adjustments**

| datatype | datatype_name  |   average_value    |
| -------- | -------------- | ------------------ |
| 0        | blood_glucose  | 170.97287506824213 |
| 6        | weight         | 80.76463831377048  |

There is a huge change in the weight measure once these adjustments are made and a slight decrease in the blood glucose metric by a value of ~7 also.

Let's also do the same for the blood pressure values

```sql
SELECT
  datatype,
  datatype_name,
  AVG(bloodpressuresystolic) AS average_systolic,
  AVG(bloodpressurediastolic) AS average_diastolic
FROM health.user_health_logs
WHERE
  datatype = '4'
  AND bloodpressurediastolic > 0 AND bloodpressuresystolic > 0
  AND bloodpressurediastolic < 200
GROUP BY
  datatype,
  datatype_name
ORDER BY
  datatype
```

**Before Adjustments**

| datatype | datatype_name  |  average_systolic  | average_diastolic |
| -------- | -------------- | ------------------ | ----------------- |
| 4        | blood_pressure | 126.33926354985519 | 79.5059991725279  |

**After adjustments**

| datatype | datatype_name  |  average_systolic  | average_diastolic |
| -------- | -------------- | ------------------ | ----------------- |
| 4        | blood_pressure | 126.39155629139073 | 78.74668874172185 |

Overall - it does not seem to make a huge difference for values after the adjustment.

## Part 3

Median makes the most sense if we were to not apply any adjustments manually like above for all of the metrics.

```sql
WITH blood_glucose_data AS (
SELECT
  'blood glucose' AS measure_name,
  PERCENTILE_CONT(0.5) WITHIN GROUP(
    ORDER BY measurementvalue
  ) AS median_value
FROM health.user_health_logs
WHERE datatype = '0'
),
weights_data AS (
SELECT
  'weight' AS measure_name,
  PERCENTILE_CONT(0.5) WITHIN GROUP(
    ORDER BY measurementvalue
  ) AS median_value
FROM health.user_health_logs
WHERE datatype = '6'
),
bp_diastolic_data AS (
SELECT
  'blood pressure diastolic' AS measure_name,
  PERCENTILE_CONT(0.5) WITHIN GROUP(
    ORDER BY bloodpressurediastolic
  ) AS median_value
FROM health.user_health_logs
WHERE datatype = '4'
),
bp_systolic_data AS (
SELECT
  'blood pressure systolic' AS measure_name,
  PERCENTILE_CONT(0.5) WITHIN GROUP(
    ORDER BY bloodpressuresystolic
  ) AS median_value
FROM health.user_health_logs
WHERE datatype = '4'
)
SELECT * FROM blood_glucose_data
UNION ALL
SELECT * FROM weights_data
UNION ALL
SELECT * FROM bp_diastolic_data
UNION ALL
SELECT * FROM bp_systolic_data
;

|       measure_name       | median_value |
| ------------------------ | ------------ |
| blood pressure systolic  |          126 |
| blood pressure diastolic |           79 |
| weight                   | 75.976721975 |
| blood glucose            |          154 |
```

Considerations would include the number of passes you'd have to perform over the dataset - in this PostgreSQL example - we had to calculate each median with a separate pass over the data which could be costly for multiple metrics.

In our current example - we still would require 2 separate passes over the data as we are calculating averages for the weight & blood glucose separately to the blood pressure values.

In addition there is also a reduced sorting complexity for the average calculation - we do not need to do an implicit sorting process to rank order all values in each measure set to identifyh which is the middle value required for the median calculation. As the data increases in size - it will become more and more costly as there are more records to sort in order to calculate the median, as opposed to simply running the calculation in a single pass for the average.

Applying the simple filters and then running the simple average calculation may be preferable in future for fast calculations at scale but will need to be monitored to ensure any underlying issues are identified and any filter rules updated to reflect these changes.

# Part 4 - Insights

When we look at the total distributions separately we can come up with some statistics about the user base in terms of averages, standard deviation values, specific percentiles such as 80th or 95th values to better understand where the majority of user measurements lie as well as maybe some correlation statistics with one value to another.

Some example statistics could perhaps include:

* Median Values - calculated prior

|       measure_name       | median_value |
| ------------------------ | ------------ |
| blood pressure systolic  |          126 |
| blood pressure diastolic |           79 |
| weight                   | 75.976721975 |
| blood glucose            |          154 |

* Adjusted Mean Values - also calculated prior

| measure_name   |   average_value    |
| -------------- | ------------------ |
| blood glucose  | 170.97287506824213 |
| weight         | 80.76463831377048  |
| bp diastolic   | 78.74668874172185  |
| bp systolic    | 126.39155629139073 |

* Standard Deviation (based off adjusted data)

```sql
WITH adjusted_data AS (
SELECT * FROM health.user_health_logs
WHERE
  (
    datatype = '4'
      AND bloodpressurediastolic > 0 AND bloodpressuresystolic > 0
      AND bloodpressurediastolic < 200
  )
  OR
  (
    -- glucose
    datatype = '0'
    AND measurementvalue > 0
    AND measurementvalue < 602
  )
  OR
    (
    -- weight
    datatype = '6'
    AND measurementvalue > 0
    AND measurementvalue < 201
  )
),
basic_measures_data AS (
SELECT
  CASE
    WHEN datatype = '0' THEN 'blood glucose'
    WHEN datatype = '6' THEN 'weight'
    END AS measure_name,
  STDDEV(measurementvalue) AS standard_deviation
FROM adjusted_data
WHERE datatype in ('0', '6')
GROUP BY 1
),
bp_diastolic_data AS (
SELECT
  'blood pressure diastolic' AS measure_name,
  STDDEV(bloodpressurediastolic) AS standard_deviation
FROM adjusted_data
WHERE datatype = '4'
),
bp_systolic_data AS (
SELECT
  'blood pressure systolic' AS measure_name,
  STDDEV(bloodpressuresystolic) AS standard_deviation
FROM adjusted_data
WHERE datatype = '4'
)
SELECT * FROM basic_measures_data
UNION ALL
SELECT * FROM bp_diastolic_data
UNION ALL
SELECT * FROM bp_systolic_data
ORDER BY measure_name
;
```

|       measure_name       | standard_deviation |
| ------------------------ | ------------------ |
| blood glucose            |  72.93649014636898 |
| blood pressure diastolic | 10.687640614694873 |
| blood pressure systolic  | 19.106041533614437 |
| weight                   | 26.912715337488176 |

There seems to be a much larger spread in the blood glucose levels compared to both blood pressure values. The weight also seems to fluctuate slightly more also.

... TBC

## Part 5

```sql
SELECT
  t1.*,
  -- check columns
  -- t2.min_glucose_range,
  -- t2.max_glucose_range,
  CASE
    WHEN t1.datatype = '0'
      AND t1.measurementvalue between t2.min_glucose_range AND t2.max_glucose_range
      THEN true
    WHEN t1.datatype = '0'
      AND t1.measurementvalue not between t2.min_glucose_range AND t2.max_glucose_range
      THEN false
    ELSE NULL
    END AS is_bg_in_range
FROM health.user_health_logs t1
INNER JOIN health.users t2
ON t1.user_id = t2.user_id
```

## Part 6

let's add this new eA1C value into the table that we've already added in that `is_bg_in_range` column

```sql
SELECT
  t1.*,
  CASE
    WHEN t1.datatype = '0'
      AND t1.measurementvalue between t2.min_glucose_range AND t2.max_glucose_range
      THEN true
    WHEN t1.datatype = '0'
      AND t1.measurementvalue not between t2.min_glucose_range AND t2.max_glucose_range
      THEN false
    ELSE NULL
    END AS is_bg_in_range,
  CASE
    WHEN t1.datatype = '0'
      THEN (t1.measurementvalue + 46.7) / 28.7
    ELSE NULL
    END as ea1c
FROM health.user_health_logs t1
INNER JOIN health.users t2
ON t1.user_id = t2.user_id
```

## Part 7

First join all the data types and only return the records which appear in the first 2 weeks of the first_app_open timestamp.

We simplify things by just looking for the interval of 14 days from that exact timestamp and also inspect just how many of these records exist for specific customers - we also take a look at the unique days so we can strategise how we will handle ties.

```sql
WITH first_2_week_records AS (
  SELECT t1.*
  FROM health.user_health_logs t1
  WHERE EXISTS (
    SELECT t2.user_id, t2.first_app_open
    FROM health.users t2
    WHERE t1.user_id = t2.user_id
    AND t1.display_date BETWEEN t2.first_app_open
      AND t2.first_app_open + INTERVAL '14 days'
  )
),
aggregated_counts AS (
  SELECT
    user_id,
    datatype,
    COUNT(*) as total_counts,
    COUNT(DISTINCT display_date) AS unique_dates
  FROM first_2_week_records
  GROUP BY 1,2
)
SELECT
  total_counts,
  unique_dates,
  datatype,
  COUNT(user_id) as users
FROM aggregated_counts
WHERE unique_dates <= 3
AND total_counts >= 3
GROUP BY 1,2,3
ORDER BY 3 DESC
;
```

There seems to be quite a small number of users with multiple counts on the same day according to this initial slice of the data.

| total_counts | unique_dates | datatype | users |
| ------------ | ------------ | -------- | ----- |
|            3 |            2 | 6        |     1 |
|            3 |            3 | 6        |     2 |
|           14 |            3 | 6        |     1 |
|            4 |            2 | 4        |     1 |
|            5 |            3 | 4        |     1 |
|            6 |            3 | 4        |     1 |
|            3 |            2 | 0        |     4 |
|            3 |            3 | 0        |     8 |
|            4 |            2 | 0        |     1 |
|            4 |            3 | 0        |     1 |
|            5 |            2 | 0        |     1 |
|            5 |            3 | 0        |     2 |
|            6 |            2 | 0        |     1 |
|            6 |            3 | 0        |     1 |
|           19 |            3 | 0        |     1 |
|           90 |            2 | 0        |     1 |

To handle ties - it seems easiest to just take a naiive row_number for the window function as opposed to a rank or dense_rank option.

We could also take a look at averages on each day and roll it up as a more accurate alternative, but the question is not asking for this measure. We will take a summary count just to confirm that we did the right thing with our query.

```sql
WITH ordered_first_2_week_records AS (
  SELECT t1.*,
  ROW_NUMBER() OVER (PARTITION BY t1.user_id, t1.datatype ORDER BY t1.display_date) as record_number
  FROM health.user_health_logs t1
  WHERE EXISTS (
    SELECT t2.user_id, t2.first_app_open
    FROM health.users t2
    WHERE t1.user_id = t2.user_id
    AND t1.display_date BETWEEN t2.first_app_open
      AND t2.first_app_open + INTERVAL '14 days'
  )
),
top_3_records AS (
  SELECT * FROM ordered_first_2_week_records
  WHERE record_number <= 3
),
aggregated_counts AS (
  SELECT
    user_id,
    COUNT(DISTINCT datatype) as datatypes,
    COUNT(*) as total_counts,
    COUNT(DISTINCT display_date) AS unique_dates
  FROM top_3_records
  GROUP BY 1,2
)
SELECT
  total_counts,
  unique_dates,
  datatypes,
  COUNT(user_id) as users
FROM aggregated_counts
GROUP BY 1,2,3
ORDER BY 3 DESC
;
```

| total_counts | unique_dates | users |
| ------------ | ------------ | ----- |
|            1 |            1 |    52 |
|            3 |            2 |    46 |
|            3 |            1 |    40 |
|            3 |            3 |    27 |
|            2 |            2 |    21 |
|            2 |            1 |    17 |

This gives us confidence that we can apply the baseline averages to this dataset.

```sql
WITH ordered_first_2_week_records AS (
  SELECT t1.*,
  ROW_NUMBER() OVER (PARTITION BY t1.user_id ORDER BY t1.display_date) as record_number
  FROM health.user_health_logs t1
  WHERE EXISTS (
    SELECT t2.user_id, t2.first_app_open
    FROM health.users t2
    WHERE t1.user_id = t2.user_id
    AND t1.display_date BETWEEN t2.first_app_open
      AND t2.first_app_open + INTERVAL '14 days'
  )
),
top_3_records AS (
  SELECT * FROM ordered_first_2_week_records
  WHERE record_number <= 3
),
average_values AS (
  SELECT
    user_id,
    AVG(
      CASE WHEN datatype = '0' THEN measurementvalue ELSE NULL END
    ) AS blood_sugar,
    AVG(
      CASE WHEN datatype = '0' THEN (measurementvalue + 46.7) / 28.7 ELSE NULL END
    ) AS ea1c,
    AVG(
      CASE WHEN datatype = '6' THEN measurementvalue ELSE NULL END
    ) AS weight,
    AVG(
      CASE WHEN datatype = '4' THEN bloodpressurediastolic ELSE NULL END
    ) AS diastolic,
    AVG(
      CASE WHEN datatype = '4' THEN bloodpressuresystolic ELSE NULL END
    ) AS systolic
FROM top_3_records
GROUP BY 1
)
SELECT * FROM average_values;
```

8a

We can inner join our users with benchmark values to the logs data to investigate their following records after their final display date used for the benchmark dataset. Since this might be a bit repetitive let's just create a temporary table to refer back to this same dataset repeatedly.



```
CREATE TEMP TABLE benchmark_users AS
WITH ordered_first_2_week_records AS (
  SELECT t1.*,
  ROW_NUMBER() OVER (PARTITION BY t1.user_id ORDER BY t1.display_date) as record_number
  FROM health.user_health_logs t1
  WHERE EXISTS (
    SELECT t2.user_id, t2.first_app_open
    FROM health.users t2
    WHERE t1.user_id = t2.user_id
    AND t1.display_date BETWEEN t2.first_app_open
      AND t2.first_app_open + INTERVAL '14 days'
  )
),
top_3_records AS (
  SELECT * FROM ordered_first_2_week_records
  WHERE record_number <= 3
),
average_values AS (
  SELECT
    user_id,
    AVG(
      CASE WHEN datatype = '0' THEN measurementvalue ELSE NULL END
    ) AS blood_sugar,
    AVG(
      CASE WHEN datatype = '0' THEN (measurementvalue + 46.7) / 28.7 ELSE NULL END
    ) AS ea1c,
    AVG(
      CASE WHEN datatype = '6' THEN measurementvalue ELSE NULL END
    ) AS weight,
    AVG(
      CASE WHEN datatype = '4' THEN bloodpressurediastolic ELSE NULL END
    ) AS diastolic,
    AVG(
      CASE WHEN datatype = '4' THEN bloodpressuresystolic ELSE NULL END
    ) AS systolic
FROM top_3_records
GROUP BY 1
)
SELECT * FROM average_values;

-- next left join onto our logs dataset to get back all values to calculate weekly averages and medians for each metric
CREATE TEMPORARY TABLE joint_dataset AS
SELECT
  t1.user_id,
  t1.blood_sugar,
  t1.ea1c,
  t1.weight,
  t1.diastolic,
  t1.systolic,
  CASE
      WHEN t2.datatype = '0'
        AND t2.measurementvalue between t3.min_glucose_range AND t3.max_glucose_range
        THEN true
      WHEN t2.datatype = '0'
        AND t2.measurementvalue not between t3.min_glucose_range AND t3.max_glucose_range
        THEN false
      ELSE NULL
      END AS is_bg_in_range,
  DATE_TRUNC('week', t2.display_date) as start_of_week,
  AVG(
      CASE WHEN datatype = '0' THEN measurementvalue ELSE NULL END
    ) AS blood_sugar_weekly,
    AVG(
      CASE WHEN datatype = '0' THEN (measurementvalue + 46.7) / 28.7 ELSE NULL END
    ) AS ea1c_weekly,
    AVG(
      CASE WHEN datatype = '6' THEN measurementvalue ELSE NULL END
    ) AS weight_weekly,
    AVG(
      CASE WHEN datatype = '4' THEN bloodpressurediastolic ELSE NULL END
    ) AS diastolic_weekly,
    AVG(
      CASE WHEN datatype = '4' THEN bloodpressuresystolic ELSE NULL END
    ) AS systolic_weekly
FROM benchmark_users t1
LEFT JOIN health.user_health_logs t2
  ON t1.user_id = t2.user_id
LEFT JOIN health.users t3
  ON t1.user_id = t3.user_id
GROUP BY
  t1.user_id,
  t1.blood_sugar,
  t1.ea1c,
  t1.weight,
  t1.diastolic,
  t1.systolic,
  is_bg_in_range,
  start_of_week;

-- lastly compute all of the comparisons of each weekly metric against the benchmark values
CREATE TEMPORARY TABLE comparison_results AS
SELECT
  user_id,
  start_of_week,
  is_bg_in_range,
  blood_sugar_weekly / blood_sugar - 1 AS blood_sugar_comparison,
  ea1c_weekly / ea1c - 1 AS ea1c_comparison,
  weight_weekly / weight - 1 AS weight_comparison,
  diastolic_weekly / diastolic - 1 AS diastolic_comparison,
  systolic_weekly / systolic - 1 AS systolic_comparison
FROM joint_dataset
ORDER BY 1,2,3;

a) 

Got tired... but almost there...


Timezone 

```sql
WITH base AS (
select
  current_time_zone,
  COALESCE(
    -- first match all time zones with more than 1 forward slash
    (REGEXP_MATCH(current_time_zone, '(\w+/\w+/\w+)'))[1],
    -- next match all single / timezones
    -- need extra hyphen for second word regex to recognise port-au-prince
    (REGEXP_MATCH(current_time_zone, '(\w+/[\w-]+)'))[1]
  ) AS tz,
  first_app_open
from health.users
)
select *
  ,TIMEZONE(tz, first_app_open)
from base
;
```
