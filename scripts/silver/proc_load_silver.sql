/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Script Purpose:
    This stored procedure performs the ETL (Extract, Transform, Load) process to 
    populate the 'silver' schema tables from the 'bronze' schema.
	Actions Performed:
		- Truncates Silver tables.
		- Inserts transformed and cleansed data from Bronze into Silver tables.
		
Parameters:
    None. 
	  This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC Silver.load_silver;
===============================================================================
*/

CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
	DECLARE @START_TIME DATETIME, @END_TIME DATETIME, @SILVER_START_TIME DATETIME, @SILVER_END_TIME DATETIME
	BEGIN TRY
		SET @SILVER_START_TIME = GETDATE();

		PRINT '========================================================================================';
		PRINT '>> Loading Silver Layer';
		PRINT '========================================================================================';
		
		PRINT '----------------------------------------------------------------------------------------';
		PRINT '>> Load CRM Tables';
		PRINT '----------------------------------------------------------------------------------------';
		
		SET @START_TIME = GETDATE();
		PRINT '>> Truncating Table: silver.crm_cust_info';
		TRUNCATE TABLE silver.crm_cust_info;
		PRINT '>> Inserting Data into: silver.crm_cust_info';
		INSERT INTO silver.crm_cust_info (
			cst_id ,
			cst_key ,
			cst_firstname ,
			cst_lastname ,
			cst_marital_status ,
			cst_gndr ,
			cst_create_date)

		select
			cst_id ,
			cst_key ,
			LTRIM(RTRIM(cst_firstname)) as cst_firstname,
			LTRIM(RTRIM(cst_lastname)) as cst_lastname,
			CASE
				WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
				WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
				ELSE 'n/a'
			END cst_marital_status ,
			CASE
				WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
				WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
				ELSE 'n/a'
			END cst_gndr,
			cst_create_date 
		from (
		select 
			*,
			ROW_NUMBER() over (partition by cst_id order by cst_create_date desc) as latest_record
		from 
			bronze.crm_cust_info
		) t
		where latest_record = 1 and cst_id IS NOT NULL;

		SET @END_TIME = GETDATE();
		PRINT '>> Load Duration:' + CAST(DATEDIFF(second, @START_TIME, @END_TIME) AS NVARCHAR) + ' seconds';
		PRINT '-----------------';

		SET @START_TIME = GETDATE();
		PRINT '>> Truncating Table: silver.crm_prd_info';
		TRUNCATE TABLE silver.crm_prd_info;
		PRINT '>> Inserting Data into: silver.crm_prd_info';
		Insert into silver.crm_prd_info (
			prd_id ,
			cat_id ,
			prd_key ,
			prd_nm ,
			prd_cost ,
			prd_line ,
			prd_start_dt ,
			prd_end_dt 
		)
		select
			prd_id,
			REPLACE(SUBSTRING(prd_key,1,5), '-', '_') AS cat_id,
			SUBSTRING(prd_key,7,LEN(prd_key)) AS prd_key,
			prd_nm,
			ISNULL(prd_cost,0) AS prd_cost ,
			CASE UPPER(TRIM(prd_line))
				WHEN 'M' THEN 'Mountain'
				WHEN 'R' THEN 'Road'
				WHEN 'S' THEN 'Other Sales'
				WHEN 'T' THEN 'Touring'
				ELSE 'n/a'
			END AS prd_line,
			CAST(prd_start_dt AS DATE) AS prd_start_dt,
			CAST(LEAD (prd_start_dt) Over (Partition by prd_key order by prd_start_dt) - 1 as DATE) as prd_end_dt
		from	
			bronze.crm_prd_info;
		
		SET @END_TIME = GETDATE();
		PRINT 'Load Duration: ' + CAST(DATEDIFF(second, @START_TIME, @END_TIME) AS NVARCHAR) + ' second';
		PRINT '---------------';

		SET @START_TIME = GETDATE();
		PRINT '>> Truncating Table: silver.crm_sales_details';
		TRUNCATE TABLE silver.crm_sales_details;
		PRINT '>> Inserting Data into: silver.crm_sales_details';
		INSERT INTO silver.crm_sales_details (
			sls_ord_num ,
			sls_prd_key ,
			sls_cust_id ,
			sls_order_dt ,
			sls_ship_dt ,
			sls_due_dt ,
			sls_sales ,
			sls_quantity ,
			sls_price
		)
		select
			sls_ord_num ,
			sls_prd_key ,
			sls_cust_id ,
			CASE 
				When sls_order_dt <= 0 OR len(sls_order_dt) <> 8 THEN NULL
				ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
			END AS sls_order_dt,
			CASE 
				When sls_ship_dt <= 0 OR len(sls_ship_dt) <> 8 THEN NULL
				ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
			END AS sls_ship_dt,
			CASE 
				When sls_due_dt <= 0 OR len(sls_due_dt) <> 8 THEN NULL
				ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
			END AS sls_due_dt,
			CASE
				WHEN sls_sales <= 0 OR sls_sales is NULL OR sls_sales <> sls_quantity * ABS(sls_price)
				THEN  sls_quantity * ABS(sls_price)
				ELSE sls_sales
			END AS sls_sales,
			sls_quantity,
			CASE
				WHEN sls_price <= 0 OR sls_price is NULL
					THEN sls_sales / NULLIF(sls_quantity,0)
				ELSE sls_price
			END AS sls_price
		from
			bronze.crm_sales_details;

		SET @END_TIME = GETDATE();
		PRINT 'Load Duration: ' + CAST(DATEDIFF(second, @START_TIME, @END_TIME) AS NVARCHAR) + ' second';
		PRINT '---------------';

		PRINT '----------------------------------------------------------------------------------------';
		PRINT '>> Load ERP Tables';
		PRINT '----------------------------------------------------------------------------------------';

		SET @START_TIME = GETDATE();
		PRINT '>> Truncating Table: silver.erp_cust_az12';
		TRUNCATE TABLE silver.erp_cust_az12;
		PRINT '>> Inserting Data into: silver.erp_cust_az12';
		INSERT into silver.erp_cust_az12 (
			cid,
			bdate,
			gen
		)
		select
			CASE
				WHEN cid like 'NAS%' THEN SUBSTRING(cid, 4, len(cid))
				ELSE cid
			END AS cid,
			CASE
				WHEN bdate > GETDATE() THEN NULL
				ELSE bdate
			END AS bdate,
			CASE
				WHEN UPPER(TRIM(gen)) IN ('M' , 'MALE') THEN 'Male'
				WHEN UPPER(TRIM(gen)) IN ('F' , 'FEMALE') THEN 'Female'
				ELSE 'n/a'
			END AS gen
		from
			bronze.erp_cust_az12;

		SET @END_TIME = GETDATE();
		PRINT 'Load Duration: ' + CAST(DATEDIFF(second, @START_TIME, @END_TIME) AS NVARCHAR) + ' second';
		PRINT '---------------';

		SET @START_TIME = GETDATE();
		PRINT '>> Truncating Table: silver.erp_loc_a101';
		TRUNCATE TABLE silver.erp_loc_a101;
		PRINT '>> Inserting Data into: silver.erp_loc_a101';
		INSERT INTO silver.erp_loc_a101 (
			cid,
			cntry
		)
		select 
			REPLACE (cid, '-' , '') AS cid,
			CASE
				WHEN TRIM(cntry) is NULL OR cntry = ' ' THEN 'n/a'
				WHEN TRIM(cntry) = 'DE' THEN 'Germany'
				WHEN TRIM(cntry) in ('US' , 'USA') THEN 'United States'
				ELSE TRIM(cntry)
			END AS cntry
		from bronze.erp_loc_a101;

		SET @END_TIME = GETDATE();
		PRINT 'Load Duration: ' + CAST(DATEDIFF(second, @START_TIME, @END_TIME) AS NVARCHAR) + ' second';
		PRINT '---------------';

		SET @START_TIME = GETDATE();
		PRINT '>> Truncating Table: silver.erp_px_cat_g1v2';
		TRUNCATE TABLE silver.erp_px_cat_g1v2;
		PRINT '>> Inserting Data into: silver.erp_px_cat_g1v2';
		INSERT INTO silver.erp_px_cat_g1v2 (
			id ,
			cat,
			subcat ,
			maintenance
		)
		Select 
			id ,
			cat,
			subcat ,
			maintenance
		from bronze.erp_px_cat_g1v2;

		SET @END_TIME = GETDATE();
		PRINT 'Load Duration: ' + CAST(DATEDIFF(second, @START_TIME, @END_TIME) AS NVARCHAR) + ' second';
		PRINT '---------------';

		SET @SILVER_END_TIME = GETDATE();
		PRINT 'Silver Total Load Duration: ' + CAST(DATEDIFF(second, @SILVER_START_TIME, @SILVER_END_TIME) AS NVARCHAR) + ' second';
		PRINT '---------------';
	END TRY

	BEGIN CATCH
		PRINT '==================================================================================';
		PRINT 'ERROR OCCURED DURING SILVER LAYER LOADING';
		PRINT '==================================================================================';
		PRINT 'ERROR MESSAGE' + ERROR_MESSAGE();
		PRINT 'ERROR MESSAGE' + CAST(ERROR_NUMBER() AS NVARCHAR);
		PRINT 'ERROR MESSAGE' + CAST(ERROR_STATE() AS NVARCHAR);
	END CATCH
END
