USE [HNCDev]
GO
/****** Object:  StoredProcedure [dbo].[SP_CESubmint]    Script Date: 2024/11/12 11:17:31 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[SP_CESubmint]
    @xxbad_domain VARCHAR(50),
    @interfaceid VARCHAR(50),
    @xxbad_type VARCHAR(50),
    @xxbad_ltype VARCHAR(50),
    @xxbad_date DATETIME,
    @xxbad_effbata DATETIME,
    @xxbad_status VARCHAR(50),
    @xxbad_part VARCHAR(50),
    @xxbad_desc VARCHAR(50),
    @xxbad_site VARCHAR(50),
    @xxbad_tosite VARCHAR(50),
    @xxbad_loc VARCHAR(50),
    @xxbad_toloc VARCHAR(50),
    @xxbad_lot VARCHAR(50),
    @xxbad_ref VARCHAR(50),
    @xxbad_tolot VARCHAR(50),
    @xxbad_toref VARCHAR(50),
    @xxbad_qty VARCHAR(50),
    @xxbad_rj_qty VARCHAR(50),
    @xxbad_order VARCHAR(50),
    @xxbad_id VARCHAR(500),
    @xxbad_line INT,
    @xxbad_op INT,
    @xxbad_proline VARCHAR(80),
    @xxbad_bom VARCHAR(50),
    @xxbad_routing VARCHAR(50),
    @xxbad_emp VARCHAR(50),
    @xxbad_rmks VARCHAR(50), --前台通用弹框提醒绑定字段 不可改动
    @xxbad_user VARCHAR(50),
    @xxbad_ship_id VARCHAR(200),
    @xxbad_time DATETIME,
    @xxbad_fromsite VARCHAR(50),
    @xxbad_recieveloc VARCHAR(50),
    @xxbad_fromloc VARCHAR(50),
    @xxbad_purchacorder VARCHAR(28),
    @xxbad_fromlot VARCHAR(50),
    @xxbad_fromref VARCHAR(50),
    @xxbad_shipper_lot VARCHAR(50),
    @xxbad_nbr VARCHAR(50),
    @xxbad_woid VARCHAR(100),
    @xxbad_clientnbr VARCHAR(50),
    @xxbad_saleship_id VARCHAR(50),
    @xxbad_sendloc VARCHAR(50),
    @xxbad_kanban_id VARCHAR(50),
    @xxbad_form_id VARCHAR(50),
    @xxbad_supplier VARCHAR(50),
    @xxbad_supplier_part VARCHAR(50),
    @xxbad_shift VARCHAR(50),
    @xxbad_isslueloc VARCHAR(50),
    @xxbad_vehicleID VARCHAR(50),
    @xxbad_arrivedate DATETIME,
    @xxbad_arrivetime VARCHAR(50),
    @xxbad_shiptime VARCHAR(50),
    @xxbad_shipdate DATETIME,
    @xxbad_scrapqty VARCHAR(50),
    @xxbad_extension1 VARCHAR(50),
    @xxbad_extension2 VARCHAR(50),
    @xxbad_extension3 VARCHAR(50),
    @xxbad_extension4 VARCHAR(50),
    @xxbad_extension5 VARCHAR(50),
    @xxbad_extension6 VARCHAR(50),
    @xxbad_extension7 VARCHAR(50),
    @xxbad_extension8 NVARCHAR(MAX),
    @ScanData VARCHAR(255)
AS
BEGIN
    DECLARE @msg_error VARCHAR(300);
    DECLARE @ErrorMessage NVARCHAR(4000);
    DECLARE @ErrorSeverity INT;
    DECLARE @ErrorState INT;
    SET @xxbad_domain = 'china';
    SET @xxbad_rmks = '';
    DECLARE @cacheuser VARCHAR(50); --缓存人

    IF ISNULL(@xxbad_site, '') = ''
    BEGIN
        SET @xxbad_site = 'VIAM';
    END;
    IF ISNULL(@xxbad_site, '') = '1'
    BEGIN
        SET @xxbad_site = 'VIAM';
    END;
    IF ISNULL(@xxbad_tosite, '') = ''
    BEGIN
        SET @xxbad_tosite = 'VIAM';
    END;
    IF ISNULL(@xxbad_fromsite, '') = ''
    BEGIN
        SET @xxbad_fromsite = 'VIAM';
    END;
    BEGIN TRY

        BEGIN TRAN; --开始事务
        --IF @interfaceid IN ( 10072 )
        --BEGIN
        --  RAISERROR('程序员正在调试，3分钟后再次尝试此功能', 11, 1);
        --END
        --
        --全局判断当前原材料是否被被人缓存了
        IF @ScanData = 'xxbad_id'
           AND @interfaceid NOT IN ( 10038, 10040, 10041 )
        BEGIN
            SELECT TOP 1
                   @cacheuser = OpUser
            FROM [Barcode_OperateCache]
            WHERE LableID = @xxbad_id;
            IF (ISNULL(@cacheuser, @xxbad_user) <> @xxbad_user)
            BEGIN
                SET @ErrorMessage = N'ERROR_MESSAGE#该箱码被用户' + @cacheuser + N'扫描，请提醒其操作!#The box code has been scanned by user ' + @cacheuser + N'. Please remind them to take action!';
                RAISERROR(@ErrorMessage, 11, 1);
            END;

        END;

        IF @interfaceid IN ( 74 ) --采购整单收货
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --再次判断发运单状态是否合法
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_ShippingMain
                    WHERE SN = @xxbad_ship_id
                          AND ISNULL(Status, 0) >= 3 --采购收货单不需要打印，取消打印状态控制

                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#发运单已经收货，不能重复收货!#The shipment has already been received and cannot be received again!', 11, 1);
                END;
                --采购收货：如果有需要检验的物料，点质检收货时提示需要打印质检单，如无，则不需要提示
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_ShippingMain
                    WHERE SN = @xxbad_ship_id
                          AND ISNULL(Status, 0) = 0
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#发运单，必须打印报检单!#For the shipping order, the inspection report must be printed!', 11, 1);
                END;
                --汇总求和 本次收货中全部标签的数量  如果发现和计划明细中不一致要报错
                SELECT SUM(qty) qty,
                       partnum,
                       ponum,
                       poline
                INTO #Barcode_ShippingDetail
                FROM dbo.barocde_materiallable
                WHERE shipsn = @xxbad_ship_id
                GROUP BY ponum,
                         poline,
                         partnum;
                --判断必须生成标签 并且打印了
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.barocde_materiallable
                    WHERE shipsn = @xxbad_ship_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#没有任何有效标签，不允许收货!#No valid labels, receipt not allowed!', 11, 1);
                END;
                DECLARE @Unfinish74 VARCHAR(2000);
                SELECT @Unfinish74
                    = COALESCE(
                                  '零件：' + a.Item + '|订单号' + a.PurchaseOrder + '和计划数量不相等['
                                  + CONVERT(NVARCHAR(30), a.CurrentQty) + ':' + CONVERT(NVARCHAR(30), ISNULL(b.qty, 0)),
                                  ''
                              )
                FROM Barcode_ShippingDetail a,
                     #Barcode_ShippingDetail b
                WHERE a.PurchaseOrder = b.ponum
                      AND a.Line = b.poline
                      AND ISNULL(a.CurrentQty, 0) <> ISNULL(b.qty, 0)
                      AND a.ShipSN = @xxbad_ship_id;
                IF ISNULL(@Unfinish74, '') <> ''
                BEGIN
                    RAISERROR(@Unfinish74, 11, 1);

                END;

                --判断箱码中数量 是否有空箱
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.barocde_materiallable
                    WHERE shipsn = @xxbad_ship_id
                          AND ISNULL(qty, 0) <= 0
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#箱码中数量不能为0!#The quantity in the box code cannot be 0!', 11, 1);

                END;
                --更新已经正产收货的标签的备料状态 收货人 收货时间 到库位
                UPDATE dbo.barocde_materiallable
                SET status = 2,
                    currentloc = 'djk',
                    lot = CONVERT(CHAR(8), GETDATE(), 112),
                    receiveuser = @xxbad_user,
                    receivetime = GETDATE()
                WHERE shipsn = @xxbad_ship_id;
                SET @xxbad_extension8 = '';
                --更新发运单主表状态收货人 收货时间
                UPDATE Barcode_ShippingMain
                SET Status = 3,
                    Type = 0,
                    ReceiveTime = GETDATE(),
                    recivetotal =
                    (
                        SELECT SUM(qty) FROM #Barcode_ShippingDetail
                    ),
                    ReceiveUser = @xxbad_user
                WHERE SN = @xxbad_ship_id;

                --更新采购单明细表中收货数量
                UPDATE a
                SET a.HouseQty = ISNULL(a.HouseQty, 0) + b.CurrentQty,
                    a.Isshipped = 0
                FROM dbo.pod_det a,
                     Barcode_ShippingDetail b
                WHERE a.pod_nbr = b.PurchaseOrder
                      AND a.pod_line = b.Line
                      AND b.ShipSN = @xxbad_ship_id;

                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @xxbad_domain,
                       'PQ_IC_POPORC',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       ponum,
                       poline,
                       partnum,
                       supplynum,
                       dbo.GetQADloc('djk'),
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       SUM(qty),
                       CONVERT(CHAR(8), GETDATE(), 112),
                       CONVERT(CHAR(8), GETDATE(), 112),
                       @xxbad_ref,
                       @xxbad_ref
                FROM barocde_materiallable
                WHERE shipsn = @xxbad_ship_id
                GROUP BY ponum,
                         poline,
                         partnum,
                         supplynum;
                --插入子队列日志 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    xxinbxml_extid,
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'PQ_IC_POPORC',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       ponum,
                       poline,
                       partnum,
                       supplynum,
                       'djk',
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       usn,
                       qty,
                       supplylot,
                       CONVERT(CHAR(8), GETDATE(), 112),
                       @xxbad_ref,
                       @xxbad_ref
                FROM barocde_materiallable
                WHERE shipsn = @xxbad_ship_id;

                --清除缓存
                --DELETE FROM Barcode_OperateCache
                --WHERE AppID = @interfaceid
                --      AND OpUser = @xxbad_user;
                --生成质检单 检测项在触发器
                INSERT INTO [dbo].[Barocde_InspectMain]
                (
                    ShipID,
                    [PartNum],
                    [SupplierNum],
                    [SupplierLot],
                    [InspectStatus],
                    [TotalQty],
                    [Loc],
                    Purchaseorder
                )
                SELECT @xxbad_ship_id,
                       Item,
                       MAX(Supplier),
                       MAX(SupplierLot),
                       0,
                       SUM(CurrentQty),
                       'djk',
                       --(
                       --    SELECT TOP 1
                       --        ReciveLoc
                       --    FROM SupplyPartSet
                       --    WHERE PartNum = PartNum
                       --          AND SupplyCode = SupplyCode
                       --),
                       MAX(PurchaseOrder)
                FROM Barcode_ShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                GROUP BY Item;
                RAISERROR(N'收货完成!', 11, 1);
            --RAISERROR(N'Info_MESSAGE#收货完成!#Receipt completed!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_ship_id' focus;
            END;
            ELSE
            BEGIN
                --判断发运单状态是否合法
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_ShippingMain
                    WHERE SN = @xxbad_ship_id
                          AND Status = 2
                          AND ISNULL(Type, 0) = 0
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#发运单状态不正确!#The shipment order status is incorrect!', 11, 1);

                END;
                --判断当前发运单的是不是 使用单箱收货功能 并且缓存了标签
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_OperateCache
                    WHERE AppID = 10006
                          AND ShipID = @xxbad_ship_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#发运单使用单箱收货功能并且缓存了标签,请先解除缓存!#The shipment order uses the single-box receiving function and has cached labels. Please clear the cache first!', 11, 1);

                END;
                --将涉及到的标签存放到临时表
                SELECT *
                INTO #Barocde_MaterialLable
                FROM dbo.barocde_materiallable
                WHERE shipsn = @xxbad_ship_id;
                --汇总计算出应收总箱数
                SELECT @xxbad_rj_qty = COUNT(1)
                FROM #Barocde_MaterialLable
                WHERE shipsn = @xxbad_ship_id;
                --返回第一个dataset到前台
                SELECT SN xxbad_ship_id,
                       SupplierName xxbad_supplier,
                       @xxbad_rj_qty xxbad_rj_qty,
                       'xxbad_supplier,xxbad_supplier' READONLY
                FROM Barcode_ShippingMain
                WHERE SN = @xxbad_ship_id;
                --返回第二个dataset到前台
                SELECT usn,
                       partnum,
                       qty
                FROM #Barocde_MaterialLable;
            END;
        END;
        --订单行退货  只要是有标签的 没有退货的 都可以退货
        IF @interfaceid IN ( 10056 )
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --限制对应标签 必须是未上架的
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.barocde_materiallable
                    WHERE ponum = @xxbad_order
                          AND poline = @xxbad_line
                          AND shipsn = @xxbad_ship_id
                          AND status >= 4
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#发运单对应的标签已经上架，请使用单箱退货!#The label corresponding to the shipment order has already been shelved. Please use single-box return!', 11, 1);

                END;
                SET @xxbad_extension8 = '';
                --更新发运明细表状态，退货原因
                UPDATE Barcode_ShippingDetail
                SET Status = 2,
                    ReleaseID = @xxbad_user + '订单行退货' + CONVERT(VARCHAR(50), GETDATE(), 21)
                WHERE ShipSN = @xxbad_ship_id
                      AND Line = @xxbad_line
                      AND PurchaseOrder = @xxbad_purchacorder;
                --如果全部明细行 都已经退货  则主表自动标记为已经退货
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_ShippingDetail
                    WHERE ShipSN = @xxbad_ship_id
                          AND Status <> 2
                )
                BEGIN
                    UPDATE dbo.Barcode_ShippingMain
                    SET Status = 5
                    WHERE SN = @xxbad_ship_id;
                END;
                --更新采购单明细表中退货数量
                UPDATE a
                SET a.RetrunQty = ISNULL(a.RetrunQty, 0) + b.CurrentQty
                FROM dbo.pod_det a,
                     Barcode_ShippingDetail b
                WHERE a.pod_nbr = b.PurchaseOrder
                      AND a.pod_line = b.Line
                      AND b.ShipSN = @xxbad_ship_id
                      AND b.PurchaseOrder = @xxbad_order
                      AND b.Line = @xxbad_line;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @xxbad_domain,
                       'PQ_IC_POPORC',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       ponum,
                       poline,
                       MAX(partnum),
                       MAX(supplynum),
                       dbo.GetQADloc('djk'),
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       -SUM(qty),
                       '',
                       '',
                       @xxbad_ref,
                       @xxbad_ref
                FROM barocde_materiallable
                WHERE shipsn = @xxbad_ship_id
                      AND ponum = @xxbad_order
                      AND poline = @xxbad_line
                GROUP BY shipsn,
                         ponum,
                         poline;

                --插入子队列日志 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    xxinbxml_extid,
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'PQ_IC_POPORC',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       ponum,
                       poline,
                       partnum,
                       currentloc,
                       '',
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       usn,
                       qty,
                       lot,
                       lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM barocde_materiallable
                WHERE shipsn = @xxbad_ship_id
                      AND ponum = @xxbad_order
                      AND poline = @xxbad_line;



                --更新已经正产收货的标签的状态 库位
                UPDATE dbo.barocde_materiallable
                SET status = 8,
                    inspectresult = @xxbad_extension7,
                    qty = 0,
                    currentloc = ''
                WHERE shipsn = @xxbad_ship_id
                      AND ponum = @xxbad_order
                      AND poline = @xxbad_line;

                RAISERROR(N'Info_MESSAGE#退货完成!#Return completed!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;

            END;

            ELSE
            BEGIN

                --判断发运单状态是否合法
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.barocde_materiallable
                    WHERE usn = @xxbad_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不存在!#Tag does not exist!', 11, 1);

                END;
                --判断当前发运单 当前采购订单， 订单行 是不是已经采用了 单箱退货
                SELECT @xxbad_ship_id = shipsn,
                       @xxbad_line = poline,
                       @xxbad_purchacorder = ponum,
                       @xxbad_status = inspectresult
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
                --AND status = 3;
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM barocde_materiallable
                    WHERE status = 8
                          AND ponum = @xxbad_purchacorder
                          AND poline = @xxbad_line
                          AND shipsn = @xxbad_ship_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#已经使用了单箱退货，不能使用订单行退货!#Single box return has already been used, order line return cannot be used!', 11, 1);

                END;
                --将涉及到的标签存放到临时表
                SELECT *
                INTO #Barocde_MaterialLable10056
                FROM dbo.barocde_materiallable
                WHERE ponum = @xxbad_purchacorder
                      AND poline = @xxbad_line
                      AND shipsn = @xxbad_ship_id;
                --汇总计算出应退总箱数
                SELECT @xxbad_rj_qty = COUNT(1)
                FROM #Barocde_MaterialLable10056
                WHERE shipsn = @xxbad_ship_id;
                --返回第一个dataset到前台
                SELECT ShipSN xxbad_ship_id,
                       Supplier xxbad_supplier,
                       @xxbad_rj_qty xxbad_rj_qty,
                       PurchaseOrder xxbad_order,
                       Line xxbad_line,
                       CurrentQty xxbad_qty,
                       @xxbad_status xxbad_inspect
                FROM Barcode_ShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                      AND Line = @xxbad_line
                      AND PurchaseOrder = @xxbad_purchacorder;
                --返回第二个dataset到前台
                SELECT usn,
                       partnum,
                       qty
                FROM #Barocde_MaterialLable10056;
            END;

        END;
        IF @interfaceid IN ( 10055 ) --整单退货 
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --限制对应标签 必须是未上架的
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.barocde_materiallable
                    WHERE shipsn = @xxbad_ship_id
                          AND status >= 4
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#发运单对应的标签状态不正确!#The label status corresponding to the shipment order is incorrect!', 11, 1);

                END;
                SET @xxbad_extension8 = '';
                --更新发运单主表状态，退货原因
                UPDATE Barcode_ShippingMain
                SET Status = 5,
                    Memo = @xxbad_user + '整单退货' + CONVERT(VARCHAR(50), GETDATE(), 21)
                WHERE SN = @xxbad_ship_id;
                --更新采购单明细表中退货数量
                UPDATE a
                SET a.RetrunQty = ISNULL(a.RetrunQty, 0) + b.CurrentQty
                FROM dbo.pod_det a,
                     Barcode_ShippingDetail b
                WHERE a.pod_nbr = b.PurchaseOrder
                      AND a.pod_line = b.Line
                      AND b.ShipSN = @xxbad_ship_id;
                --插入子队列日志 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    xxinbxml_extid,
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT 0,
                       @interfaceid,
                       @xxbad_domain,
                       'PQ_IC_POPORC',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       ponum,
                       poline,
                       partnum,
                       currentloc,
                       '',
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       qty,
                       '',
                       '',
                       @xxbad_ref,
                       @xxbad_ref
                FROM barocde_materiallable
                WHERE shipsn = @xxbad_ship_id;

                --更新已经正产收货的标签的状态 库位
                UPDATE dbo.barocde_materiallable
                SET status = 8,
                    currentloc = ''
                WHERE shipsn = @xxbad_ship_id;

                RAISERROR(N'Info_MESSAGE#退货完成!#Return completed!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_supplier,xxbad_qty' READONLY,
                       'Inspect' xxbad_toloc;

            END;

            ELSE
            BEGIN

                --判断发运单状态是否合法
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_ShippingMain
                    WHERE SN = @xxbad_ship_id
                          AND Status = 3
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#发运单状态不正确!#The shipment order status is incorrect!', 11, 1);

                END;
                --限制对应标签 必须是未上架的
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.barocde_materiallable
                    WHERE shipsn = @xxbad_ship_id
                          AND status >= 4
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#发运单对应的标签状态不正确!#The label status corresponding to the shipment order is incorrect!', 11, 1);

                END;
                --将涉及到的标签存放到临时表
                SELECT *
                INTO #Barocde_MaterialLable10055
                FROM dbo.barocde_materiallable
                WHERE shipsn = @xxbad_ship_id;
                --汇总计算出应退总箱数
                SELECT @xxbad_rj_qty = COUNT(1)
                FROM #Barocde_MaterialLable10055
                WHERE shipsn = @xxbad_ship_id;
                --返回第一个dataset到前台
                SELECT SN xxbad_ship_id,
                       SupplierName xxbad_supplier,
                       @xxbad_rj_qty xxbad_rj_qty,
                       'xxbad_supplier,xxbad_supplier' READONLY
                FROM Barcode_ShippingMain
                WHERE SN = @xxbad_ship_id;
                --返回第二个dataset到前台
                SELECT usn,
                       partnum,
                       qty
                FROM #Barocde_MaterialLable10055;
            END;

        END;
        IF @interfaceid IN ( 10026 ) --采购单箱退货  支持 打印状态，收货，质检，上架 4种状态的退货
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --采购收货和退货识别html中库位是xxinbxml_locto至库位，不是xxinbxml_locfrm从库位。38164队列至库位为空，qad默认库位是bjzy01
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg]
                )
                SELECT @xxbad_domain,
                       'PQ_IC_POPORC',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       ponum,
                       poline,
                       partnum,
                       '',
                       dbo.GetQADloc(@xxbad_fromloc),
                       lot,
                       lot,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       usn,
                       -qty
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id
                      AND status >= 2;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT ISNULL(@@IDENTITY, 10026),
                       @interfaceid,
                       @xxbad_domain,
                       'PQ_IC_PORVIS',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       usn,
                       @xxbad_user,
                       ponum,
                       poline,
                       partnum,
                       @xxbad_fromloc,
                       '',
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       shipsn,
                       @xxbad_id,
                       qty,
                       ISNULL(lot, ''),
                       '',
                       @xxbad_ref,
                       ''
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
                --清空标签的库位 该变状态
                UPDATE dbo.barocde_materiallable
                SET fromloc = currentloc,
                    status = 8,
                    memo = '采购退货',
                    retruntime = GETDATE(),
                    retrunuser = @xxbad_user,
                    destroymemo = '采购退货',
                    currentloc = NULL
                WHERE usn = @xxbad_id;
                --更新标签对应采购订单的退回数量
                UPDATE pod_det
                SET RetrunQty = ISNULL(RetrunQty, 0) + @xxbad_qty
                WHERE pod_nbr = @xxbad_woid
                      AND pod_line = @xxbad_extension1;
                --抛出信息到前台
                RAISERROR(N'Info_MESSAGE#提交成功!#Submission successful!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;

            END;
            ELSE --认为扫描的是条码数据
            BEGIN
                --认为扫描的是标签
                --读取标签中的信息
                SELECT @xxbad_id = usn,
                       @xxbad_qty = qty,
                       @xxbad_part = partnum,
                       @xxbad_fromloc = currentloc,
                       @xxbad_fromsite = site,
                       @xxbad_toloc = currentloc,
                       @xxbad_fromlot = lot,
                       @xxbad_woid = ponum,
                       @xxbad_extension1 = poline
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id
                      AND status IN ( 2, 3, 4, 5, 6 );

                --判断标签是否合法
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    RAISERROR(N'Info_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;

                --判断零件是否可以从从库位移除
                SELECT @msg_error = dbo.CheckLocArea(@xxbad_part, @xxbad_fromloc, 0);
                IF ISNULL(@msg_error, '') <> ''
                BEGIN
                    RAISERROR(@msg_error, 11, 1);

                END;
                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       @xxbad_qty xxbad_qty,
                       @xxbad_part xxbad_part,
                       @xxbad_fromloc xxbad_fromloc,
                       @xxbad_fromsite xxbad_fromsite,
                       @xxbad_toloc xxbad_toloc,
                       @xxbad_fromlot xxbad_fromlot,
                       @xxbad_woid xxbad_woid,
                       @xxbad_extension1 xxbad_extension1;
            END;

        END;
        IF @interfaceid IN ( 10006 ) --采购逐箱收货
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --提交的时候再次判断发运单状态是否合法
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_ShippingMain
                    WHERE SN = @xxbad_ship_id
                          AND Status = 2
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#发运单状态不正确!#The shipment order status is incorrect!', 11, 1);

                END;
                --判断实收箱数 不能小于0
                DECLARE @total INT; --实际扫描总数量
                SELECT @total = SUM(1)
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                IF ISNULL(@total, 0) < 1
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#没有扫描任何标签!#No tags scanned!', 11, 1);

                END;
                --更新已经正产收货的标签的备料状态 备料人 备料时间 到库位
                UPDATE dbo.barocde_materiallable
                SET status = 2,
                    currentloc = 'djk',
                    --(
                    --    SELECT TOP 1
                    --        ReciveLoc
                    --    FROM SupplyPartSet
                    --    WHERE SupplyPartSet.PartNum = Barocde_MaterialLable.PartNum
                    --          AND SupplyPartSet.SupplyCode = Barocde_MaterialLable.SupplyNum
                    --),
                    receiveuser = @xxbad_user,
                    receivetime = GETDATE()
                WHERE usn IN
                      (
                          SELECT LableID
                          FROM Barcode_OperateCache
                          WHERE AppID = @interfaceid
                                AND OpUser = @xxbad_user
                      )
                      AND status = 1;
                SET @xxbad_extension8 = '';
                --更新发运单主表状态收货人 收货时间
                UPDATE Barcode_ShippingMain
                SET Status = 3,
                    Type = 1,
                    ReceiveTime = GETDATE(),
                    ReceiveUser = @xxbad_user
                WHERE SN = @xxbad_ship_id;
                --插入条码主队列 不用上传QAD的了
                --INSERT INTO [dbo].[xxinbxml_mstr]
                --(   [xxinbxml_domain],
                --    BarcodeInterFaceID,
                --    [xxinbxml_appid],
                --    [xxinbxml_status],
                --    [xxinbxml_crtdate],
                --    [xxinbxml_cimdate],
                --    [xxinbxml_type],
                --    [xxinbxml_extusr],
                --    [xxinbxml_ord],
                --    [xxinbxml_line],
                --    [xxinbxml_part],
                --    [xxinbxml_locfrm],
                --    [xxinbxml_locto],
                --    [xxinbxml_sitefrm],
                --    [xxinbxml_siteto],
                --    [xxinbxml_pallet],
                --    [xxinbxml_box],
                --    [xxinbxml_qty_chg],
                --    xxinbxml_lotfrm,
                --    xxinbxml_lotto,
                --    xxinbxml_reffrm,
                --    xxinbxml_refto
                --)
                --SELECT @xxbad_domain,
                --    @interfaceid,
                --    'PQ_IC_POPORC',
                --    0,
                --    GETDATE(),
                --    GETDATE(),
                --    'CIM',
                --    @xxbad_user,
                --    PoNum,
                --    PoLine,
                --    PartNum,
                --    @xxbad_fromloc,
                --    (
                --        SELECT TOP 1
                --            QadLoc
                --        FROM SupplyPartSet
                --        WHERE PartNum = PartNum
                --              AND SupplyCode = SupplyCode
                --    ),
                --    @xxbad_fromsite,
                --    @xxbad_tosite,
                --    @xxbad_ship_id,
                --    @xxbad_id,
                --    SUM(Qty),
                --    FromLot,
                --    '',
                --    @xxbad_ref,
                --    @xxbad_ref
                --FROM Barcode_OperateCache
                --WHERE AppID = @interfaceid
                --      AND OpUser = @xxbad_user
                --GROUP BY PoNum,
                --    PoLine,
                --    PartNum,
                --    FromLot;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT 10006,
                       @interfaceid,
                       @xxbad_domain,
                       'PQ_IC_POPORC',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       LableID,
                       @xxbad_user,
                       PoNum,
                       PoLine,
                       PartNum,
                       @xxbad_fromloc,
                       'djk',
                       --(
                       --    SELECT TOP 1
                       --        ReciveLoc
                       --    FROM SupplyPartSet
                       --    WHERE PartNum = Barcode_OperateCache.PartNum
                       --          AND SupplyCode = Barcode_OperateCache.SupplyCode
                       --),
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       Qty,
                       '',
                       '',
                       @xxbad_ref,
                       @xxbad_ref
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;

                --生成质检单 检测项在触发器
                INSERT INTO [dbo].[Barocde_InspectMain]
                (
                    ShipID,
                    [PartNum],
                    [SupplierNum],
                    [SupplierLot],
                    [InspectStatus],
                    [TotalQty],
                    [Loc],
                    Purchaseorder
                )
                SELECT @xxbad_ship_id,
                       PartNum,
                       SupplyCode,
                       FromLot,
                       0,
                       SUM(Qty),
                       'djk',
                       --(
                       --    SELECT TOP 1
                       --        ReciveLoc
                       --    FROM SupplyPartSet
                       --    WHERE PartNum = PartNum
                       --          AND SupplyCode = SupplyCode
                       --),
                       MAX(PoNum)
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                GROUP BY PartNum,
                         SupplyCode,
                         FromLot;
                --清除缓存
                DELETE FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                RAISERROR(N'Info_MESSAGE#收货完成!#Receipt completed!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                --返回第一个dataset到前台
                SELECT ShipID xxbad_ship_id,
                       SupplyName xxbad_supplier,
                       @xxbad_rj_qty xxbad_rj_qty,
                       COUNT(1) xxbad_qty,
                       'xxbad_supplier,xxbad_rj_qty,xxbad_supplier' READONLY
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                GROUP BY ShipID,
                         SupplyName;
                --返回第二个dataset到前台
                SELECT LableID USN,
                       PartNum,
                       Qty
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;

            END;

            ELSE IF @ScanData = 'xxbad_ship_id'
            BEGIN

                --判断发运单状态是否合法
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_ShippingMain
                    WHERE SN = @xxbad_ship_id
                          AND Status = 2
                          AND ISNULL(Type, 1) = 1
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#发运单状态不正确!#The shipment order status is incorrect!', 11, 1);

                END;
                --汇总计算出应收总箱数
                SELECT @xxbad_rj_qty = COUNT(1)
                FROM dbo.barocde_materiallable
                WHERE shipsn = @xxbad_ship_id;
                --汇总计算出实收总箱数
                SELECT @xxbad_qty = COUNT(1)
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                --返回第一个dataset到前台
                SELECT SN xxbad_ship_id,
                       SupplierName xxbad_supplier,
                       @xxbad_rj_qty xxbad_rj_qty,
                       @xxbad_qty xxbad_qty,
                       'xxbad_supplier,xxbad_rj_qty,xxbad_supplier' READONLY
                FROM Barcode_ShippingMain
                WHERE SN = @xxbad_ship_id;
                --返回第二个dataset到前台
                SELECT LableID USN,
                       PartNum,
                       Qty
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;

            END;
            ELSE
            BEGIN
                SET @xxbad_rmks = '';
                -- 判断标签合法性
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM barocde_materiallable
                    WHERE usn = @xxbad_id
                          AND status = 1
                          AND shipsn = @xxbad_ship_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#Invalid tag!#Invalid tag!', 11, 1);

                END;
                --判断当前原材料是否被被人缓存了
                SELECT TOP 1
                       @cacheuser = OpUser
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND LableID = @xxbad_id;
                IF (ISNULL(@cacheuser, @xxbad_user) <> @xxbad_user)
                BEGIN
                    SET @ErrorMessage
                        = N'ERROR_MESSAGE#该箱码被用户' + @cacheuser + N'扫描，请提醒其操作!#The box code has been scanned by user ' + @cacheuser + N'. Please remind them to take action!';
                    RAISERROR(@ErrorMessage, 11, 1);

                END;
                --如果在动态高速缓存表不存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                          AND LableID = @xxbad_id
                )
                BEGIN
                    --从标签中获取标签信息 插入动态高速缓存表
                    INSERT INTO [dbo].[Barcode_OperateCache]
                    (
                        [AppID],
                        [OpUser],
                        [LableID],
                        [PartNum],
                        [PartDescrition],
                        [Qty],
                        [FromLoc],
                        [CurrentLoc],
                        [ToLoc],
                        [FromSite],
                        [ToSite],
                        FromLot,
                        ToLot,
                        [ScanTime],
                        ShipID,
                        SupplyCode,
                        SupplyName,
                        PoNum,
                        PoLine
                    )
                    SELECT TOP 1
                           @interfaceid,
                           @xxbad_user,
                           @xxbad_id,
                           partnum,
                           partdescription,
                           qty,
                           currentloc,
                           currentloc,
                           'djk',
                           --(
                           --    SELECT TOP 1
                           --        ReciveLoc
                           --    FROM SupplyPartSet
                           --    WHERE PartNum = PartNum
                           --          AND SupplyCode = SupplyCode
                           --),
                           site,
                           @xxbad_site,
                           supplylot,
                           lot,
                           GETDATE(),
                           shipsn,
                           supplynum,
                           supplyname,
                           ponum,
                           poline
                    FROM dbo.barocde_materiallable
                    WHERE usn = @xxbad_id;
                END;
                ELSE
                BEGIN
                    --二次扫描解除缓存
                    DELETE FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                          AND LableID = @xxbad_id;
                    SET @xxbad_rmks = @xxbad_id + '标签二次扫描，自动解除成功!#The reception is completed!';
                END;

                --返回第一个dataset到前台
                SELECT ShipID xxbad_ship_id,
                       SupplyName xxbad_supplier,
                       @xxbad_rj_qty xxbad_rj_qty,
                       COUNT(1) xxbad_qty,
                       '' xxbad_id,
                       'xxbad_ship_id' Readonly,
                       @xxbad_rmks xxbad_rmks
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                GROUP BY ShipID,
                         SupplyName;
                --返回第二个dataset到前台
                SELECT LableID USN,
                       PartNum,
                       Qty
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
            END;

        END;
        DECLARE @MaxUSN VARCHAR(50);
        DECLARE @seqNum VARCHAR(8);
        DECLARE @days VARCHAR(50) = SUBSTRING(CONVERT(VARCHAR, GETDATE(), 112), 3, 6); --格式化日期
        IF @interfaceid IN ( 10024 ) --原材料标签拆分
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --再次判断标签是否合法 
                SELECT @xxbad_id = usn,
                       @xxbad_part = partnum,
                       @xxbad_desc = partdescription,
                       @xxbad_qty = qty,
                       @xxbad_fromloc = currentloc
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id
                      AND status > 1
                      AND status < 7;
                --判断标签是否合法
                IF ISNULL(@xxbad_desc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                --判断输入的拆分数量是否为空
                IF ISNULL(@xxbad_extension1, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#拆分数量不能为空!#The split quantity cannot be empty!', 11, 1);

                END;
                --判断输入的数量是否合法
                IF CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension1, 0)) <= 0
                   OR CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension1, 0)) > CONVERT(DECIMAL(18, 5), @xxbad_qty)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#Invalid split quantity!#Invalid split quantity!', 11, 1);

                END;
                --生成第一张新标签
                SELECT @xxbad_extension2 = dbo.GetNextUSN(@xxbad_id, 1);
                INSERT barocde_materiallable
                (
                    id,
                    usn,
                    partnum,
                    partdescription,
                    parttype,
                    lot,
                    currentloc,
                    fromloc,
                    toloc,
                    whloc,
                    qty,
                    site,
                    isalive,
                    status,
                    productusn,
                    memo,
                    pkgqty,
                    ponum,
                    poline,
                    shipsn,
                    po_duedate,
                    recipient,
                    supplynum,
                    supplylot,
                    supplypartnum,
                    supplyname,
                    extendfiled1,
                    extendfiled2,
                    extendfiled3,
                    createtime,
                    receiveuser,
                    receivetime,
                    inspectsn,
                    inspecttype,
                    okqty,
                    unokqty,
                    inspectresult,
                    inspectuser,
                    inspecttime,
                    inbounduser,
                    inboundtime,
                    destroytime,
                    destroyuser,
                    destroymemo,
                    printtime,
                    pt_desc2
                )
                SELECT NEWID(),
                       @xxbad_extension2,
                       partnum,
                       partdescription,
                       parttype,
                       lot,
                       currentloc,
                       fromloc,
                       toloc,
                       whloc,
                       CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension1, 0)),
                       site,
                       isalive,
                       status,
                       productusn,
                       '标签拆分',
                       pkgqty,
                       ponum,
                       poline,
                       shipsn,
                       po_duedate,
                       recipient,
                       supplynum,
                       supplylot,
                       supplypartnum,
                       supplyname,
                       @xxbad_id,
                       extendfiled2,
                       extendfiled3,
                       createtime,
                       receiveuser,
                       receivetime,
                       inspectsn,
                       inspecttype,
                       okqty,
                       unokqty,
                       inspectresult,
                       inspectuser,
                       inspecttime,
                       inbounduser,
                       inboundtime,
                       destroytime,
                       destroyuser,
                       destroymemo,
                       printtime,
                       pt_desc2
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
                EXEC dbo.PrintMaterialLable @xxbad_extension2;
                --生成第二张新标签
                SELECT @xxbad_extension3 = dbo.GetNextUSN(@xxbad_id, 1);
                INSERT dbo.barocde_materiallable
                (
                    id,
                    usn,
                    partnum,
                    partdescription,
                    parttype,
                    lot,
                    currentloc,
                    fromloc,
                    toloc,
                    whloc,
                    qty,
                    site,
                    isalive,
                    status,
                    productusn,
                    memo,
                    pkgqty,
                    ponum,
                    poline,
                    shipsn,
                    po_duedate,
                    recipient,
                    supplynum,
                    supplylot,
                    supplypartnum,
                    supplyname,
                    extendfiled1,
                    extendfiled2,
                    extendfiled3,
                    createtime,
                    receiveuser,
                    receivetime,
                    inspectsn,
                    inspecttype,
                    okqty,
                    unokqty,
                    inspectresult,
                    inspectuser,
                    inspecttime,
                    inbounduser,
                    inboundtime,
                    destroytime,
                    destroyuser,
                    destroymemo,
                    printtime,
                    pt_desc2
                )
                SELECT NEWID(),
                       @xxbad_extension3,
                       partnum,
                       partdescription,
                       parttype,
                       lot,
                       currentloc,
                       fromloc,
                       toloc,
                       whloc,
                       CONVERT(DECIMAL(18, 5), @xxbad_qty) - CONVERT(DECIMAL(18, 5), @xxbad_extension1),
                       site,
                       isalive,
                       status,
                       productusn,
                       '标签拆分',
                       pkgqty,
                       ponum,
                       poline,
                       shipsn,
                       po_duedate,
                       recipient,
                       supplynum,
                       supplylot,
                       supplypartnum,
                       supplyname,
                       @xxbad_id,
                       extendfiled2,
                       extendfiled3,
                       createtime,
                       receiveuser,
                       receivetime,
                       inspectsn,
                       inspecttype,
                       okqty,
                       unokqty,
                       inspectresult,
                       inspectuser,
                       inspecttime,
                       inbounduser,
                       inboundtime,
                       destroytime,
                       destroyuser,
                       destroymemo,
                       printtime,
                       pt_desc2
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
                EXEC dbo.PrintMaterialLable @xxbad_extension3;
                --需要将老标签注销
                UPDATE dbo.barocde_materiallable
                SET status = 7,
                    isalive = 0,
                    qty = 0,
                    destroytime = GETDATE(),
                    destroyuser = @xxbad_user,
                    destroymemo = '标签拆分：第一个' + @xxbad_extension2 + '第二个' + @xxbad_extension3
                WHERE usn = @xxbad_id;
                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       @xxbad_part xxbad_part,
                       @xxbad_qty xxbad_qty,
                       @xxbad_fromloc xxbad_fromloc,
                       'xxbad_extension1' READONLY,
                       @xxbad_supplier xxbad_supplier,
                       @xxbad_extension2 xxbad_extension2,
                       @xxbad_extension3 xxbad_extension3;
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;

            END;

            ELSE
            BEGIN
                --默认第一次扫描是标签 
                SELECT @xxbad_id = usn,
                       @xxbad_part = partnum,
                       @xxbad_supplier = supplynum,
                       @xxbad_qty = qty,
                       @xxbad_fromloc = currentloc
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id
                      AND status > 1
                      AND status < 7;
                --判断标签是否合法
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       @xxbad_part xxbad_part,
                       @xxbad_qty xxbad_qty,
                       @xxbad_fromloc xxbad_fromloc,
                       'xxbad_extension1' READONLY,
                       @xxbad_supplier xxbad_supplier;
            END;

        END;
        IF @interfaceid IN ( 10044 ) --原材料标签合并  支持多批次合并
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --再次判断提交的数据是否合法 
                IF ISNULL(@xxbad_id, '') = ''
                   OR ISNULL(@xxbad_extension1, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请扫描标签 !#Please scan the label!', 11, 1);

                END;
                --两次扫描的箱码不能相同
                IF ISNULL(@xxbad_id, '') = ISNULL(@xxbad_extension1, '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#第一箱和第二箱箱码不能相同 !#The box codes for the first and second boxes cannot be the same!', 11, 1);

                END;
                --生成一个移库队列 用来调整库存的批次
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg]
                )
                SELECT @xxbad_domain,
                       'IC_TR',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       '',
                       partnum,
                       dbo.GetQADloc(@xxbad_loc),
                       dbo.GetQADloc(@xxbad_loc),
                       lot,
                       @xxbad_lot,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       usn,
                       qty
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_extension1;
                --标签插入子队列 用于调整库存的批次
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       usn,
                       @xxbad_user,
                       '',
                       '',
                       partnum,
                       currentloc,
                       @xxbad_loc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       @xxbad_id,
                       qty,
                       lot,
                       @xxbad_lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_extension1;
                ----取出最大当前供应商当天最大的标签ID 在此基础上面递增
                --DECLARE @MaxUSN10044 VARCHAR(50);
                --DECLARE @days10044 VARCHAR(50) = SUBSTRING(CONVERT(VARCHAR, GETDATE(), 112), 3, 6); --格式化日期
                --SELECT TOP 1
                --       @MaxUSN = usn
                --FROM barocde_materiallable
                --WHERE usn < @xxbad_supplier + @days + '9999'
                --ORDER BY usn DESC;
                ----取最大流水号 如果跨天重置0000
                --DECLARE @seqNum10044 VARCHAR(8);
                --IF (@MaxUSN IS NULL)
                --   OR ((@xxbad_supplier + @days) <> LEFT(@MaxUSN, LEN(@MaxUSN) - 4))
                --    SET @seqNum = '0000';
                --ELSE
                --    SET @seqNum = RIGHT(@MaxUSN, 4);
                ----判断数量是否溢出
                --IF (@seqNum + 2) > 9999
                --BEGIN
                --    RAISERROR(N'ERROR_MESSAGE#Quantity overflow, please split again tomorrow!#Quantity overflow, please split again tomorrow!', 11, 1);

                --END;

                ----生成第一张新标签
                --SET @seqNum = @seqNum + 1;
                --SET @xxbad_extension3 = 'RM-' + @xxbad_supplier + @days + REPLICATE('0', 4 - LEN(@seqNum)) + @seqNum;
                --IF ISNULL(@xxbad_extension3, '') = ''
                --BEGIN
                --    RAISERROR(N'ERROR_MESSAGE#Failed to generate a new tag!#Failed to generate a new tag!', 11, 1);

                --END;
                CREATE TABLE #t22
                (
                    fid VARCHAR(30)
                );
                INSERT INTO #t22
                EXEC dbo.MakeSeqenceNum '00000001', @xxbad_supplier;
                SELECT @xxbad_extension3 = fid
                FROM #t22;
                IF ISNULL(@xxbad_extension3, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#Failed to generate a new tag!#Failed to generate a new tag!', 11, 1);
                END;

                INSERT barocde_materiallable
                (
                    id,
                    usn,
                    partnum,
                    partdescription,
                    parttype,
                    lot,
                    currentloc,
                    fromloc,
                    toloc,
                    whloc,
                    qty,
                    site,
                    isalive,
                    status,
                    productusn,
                    memo,
                    pkgqty,
                    ponum,
                    poline,
                    shipsn,
                    po_duedate,
                    recipient,
                    supplynum,
                    supplylot,
                    supplypartnum,
                    supplyname,
                    extendfiled1,
                    extendfiled2,
                    extendfiled3,
                    createtime,
                    receiveuser,
                    receivetime,
                    inspectsn,
                    inspecttype,
                    okqty,
                    unokqty,
                    inspectresult,
                    inspectuser,
                    inspecttime,
                    inbounduser,
                    inboundtime,
                    destroytime,
                    destroyuser,
                    destroymemo,
                    printtime,
                    pt_desc2
                )
                SELECT NEWID(),
                       @xxbad_extension3,
                       partnum,
                       partdescription,
                       parttype,
                       lot,
                       currentloc,
                       fromloc,
                       toloc,
                       whloc,
                       CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, 0)) + CONVERT(DECIMAL(18, 5), @xxbad_qty),
                       site,
                       isalive,
                       status,
                       productusn,
                       @xxbad_extension1 + @xxbad_id + '标签合并',
                       pkgqty,
                       ponum,
                       poline,
                       shipsn,
                       po_duedate,
                       recipient,
                       supplynum,
                       supplylot,
                       supplypartnum,
                       supplyname,
                       @xxbad_id,
                       extendfiled2,
                       extendfiled3,
                       createtime,
                       receiveuser,
                       receivetime,
                       inspectsn,
                       inspecttype,
                       okqty,
                       unokqty,
                       inspectresult,
                       inspectuser,
                       inspecttime,
                       inbounduser,
                       inboundtime,
                       destroytime,
                       destroyuser,
                       destroymemo,
                       printtime,
                       pt_desc2
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
                --EXEC dbo.PrintMaterialLable @xxbad_extension3;
                --需要将老标签注销
                UPDATE dbo.barocde_materiallable
                SET status = 7,
                    isalive = 0,
                    qty = 0,
                    destroytime = GETDATE(),
                    destroyuser = @xxbad_user,
                    destroymemo = '标签合并' + @xxbad_supplier + @days + REPLICATE('0', 4 - LEN(@seqNum)) + @seqNum
                WHERE usn IN ( @xxbad_id, @xxbad_extension1 );
                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       @xxbad_part xxbad_part,
                       @xxbad_qty xxbad_qty,
                       @xxbad_loc xxbad_loc,
                       @xxbad_lot xxbad_lot,
                       @xxbad_extension1 xxbad_extension1,
                       @xxbad_extension2 xxbad_extension2,
                       @xxbad_extension3 xxbad_extension3,
                       '合并成功' xxbad_extension7;
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;

            END;
            ELSE IF @ScanData = 'xxbad_extension1'
            BEGIN
                --否则扫描的是第二张标签
                SET @xxbad_extension4 = '';
                SELECT @xxbad_extension1 = usn,
                       @xxbad_extension2 = qty,
                       @xxbad_extension4 = partnum,
                       @xxbad_extension5 = currentloc,
                       @xxbad_extension6 = lot,
                       @xxbad_extension7 = supplynum
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_extension1
                      AND status > 3
                      AND status < 7;
                --判断标签是否合法
                IF ISNULL(@xxbad_extension4, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                --判断标签是否合法
                IF ISNULL(@xxbad_extension6, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签批次不能为空!#Label batch cannot be empty!', 11, 1);

                END;
                --判断第二张标签是否和第一张标签零件号 库位 供应商是否一样
                IF ISNULL(@xxbad_extension4, '') <> @xxbad_part
                   OR ISNULL(@xxbad_extension5, '') <> @xxbad_loc
                   OR ISNULL(@xxbad_extension7, '') <> @xxbad_supplier
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#第二张标签和第一张标签零件号,库位,供应商不匹配!#The part number, storage location, and supplier of the second label do not match those of the first label!', 11, 1);

                END;
                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       @xxbad_part xxbad_part,
                       @xxbad_qty xxbad_qty,
                       @xxbad_loc xxbad_loc,
                       @xxbad_supplier xxbad_supplier,
                       @xxbad_lot xxbad_lot,
                       @xxbad_extension1 xxbad_extension1,
                       @xxbad_extension2 xxbad_extension2;
            END;
            ELSE
            BEGIN
                --如果第一张标签是空
                IF @ScanData = 'xxbad_id'
                BEGIN
                    SET @xxbad_part = '';
                    SET @xxbad_lot = '';
                    --默认第一次扫描是标签 
                    SELECT @xxbad_id = usn,
                           @xxbad_part = partnum,
                           @xxbad_qty = qty,
                           @xxbad_loc = currentloc,
                           @xxbad_lot = lot,
                           @xxbad_supplier = supplynum
                    FROM dbo.barocde_materiallable
                    WHERE usn = @xxbad_id
                          AND status > 3
                          AND status < 7;

                    --判断标签是否合法
                    IF ISNULL(@xxbad_part, '') = ''
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                    END;
                    --判断标签是否合法
                    IF ISNULL(@xxbad_lot, '') = ''
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#标签批次不能为空!#Label batch cannot be empty!', 11, 1);

                    END;
                    --返回第一个dataset 到前台
                    SELECT @xxbad_id xxbad_id,
                           @xxbad_part xxbad_part,
                           @xxbad_qty xxbad_qty,
                           @xxbad_loc xxbad_loc,
                           @xxbad_lot xxbad_lot,
                           @xxbad_supplier xxbad_supplier;
                END;
            END;
        END;
        IF @interfaceid IN ( 10096 ) --成品标签合并
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --再次判断提交的数据是否合法 
                IF ISNULL(@xxbad_id, '') = ''
                   OR ISNULL(@xxbad_extension1, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请扫描标签 !#Please scan the label!', 11, 1);

                END;
                --两次扫描的箱码不能相同
                IF ISNULL(@xxbad_id, '') = ISNULL(@xxbad_extension1, '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#第一箱和第二箱箱码不能相同 !#The box codes for the first and second boxes cannot be the same!', 11, 1);

                END;
                --生成一个移库队列 用来调整第二个标签库存中的批次
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg]
                )
                SELECT @xxbad_domain,
                       'IC_TR',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       dbo.GetQADloc(CurrentLoc),
                       dbo.GetQADloc(@xxbad_loc),
                       Lot,
                       @xxbad_lot,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       USN,
                       Qty
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_extension1;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       USN,
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       CurrentLoc,
                       @xxbad_loc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       @xxbad_id,
                       Qty,
                       Lot,
                       @xxbad_lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_extension1;
                CREATE TABLE #t1
                (
                    fid VARCHAR(30)
                );
                INSERT INTO #t1
                EXEC dbo.MakeSeqenceNum '00000016', @xxbad_part;
                --EXEC GetFGSeqenceNum @xxbad_supplier, @xxbad_part, 1;

                --生成第一张新标签
                SELECT @xxbad_extension3 = fid
                FROM #t1;
                --判断新生成的标签不能为空
                IF ISNULL(@xxbad_extension3, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#合并出错，没有生成新标签 !#Merge error, no new tag generated!', 11, 1);

                END;
                INSERT dbo.Barocde_BoxlLable
                (
                    ID,
                    USN,
                    Qty,
                    Memo,
                    ExtendFiled1,
                    PartNum,
                    PartDescription,
                    Lot,
                    CurrentLoc,
                    FromLoc,
                    ToLoc,
                    WHloc,
                    Site,
                    LastStatus,
                    Status,
                    WorkOp,
                    PkgQty,
                    WoNum,
                    ShipSN,
                    Wo_DueDate,
                    ProLine,
                    CustomNum,
                    CustomLot,
                    CustomPartNum,
                    CustomName,
                    ExtendFiled2,
                    ExtendFiled3,
                    CreateTime,
                    FlushStatus,
                    BackwashResult,
                    BackwashUser,
                    BackwashTime,
                    InspectSN,
                    InspectType,
                    OkQty,
                    UnOkQty,
                    InspectResult,
                    InspectUser,
                    InspectTime,
                    InboundUser,
                    InboundTime,
                    DestroyTime,
                    DestroyUser,
                    DestroyMemo,
                    PrintTime,
                    PurchaseOrder,
                    PoLine,
                    CheckLoc,
                    BoxTime,
                    BoxUser,
                    PrintQty,
                    PalletLable,
                    IsComplex,
                    ShipTo,
                    DockLoaction,
                    SupplyNum,
                    CustomPO
                )
                SELECT NEWID(),
                       @xxbad_extension3,
                       CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, 0)) + CONVERT(DECIMAL(18, 5), @xxbad_qty),
                       @xxbad_extension1 + @xxbad_id + '标签合并',
                       @xxbad_id,
                       PartNum,
                       PartDescription,
                       Lot,
                       CurrentLoc,
                       FromLoc,
                       ToLoc,
                       WHloc,
                       Site,
                       LastStatus,
                       Status,
                       WorkOp,
                       PkgQty,
                       WoNum,
                       ShipSN,
                       Wo_DueDate,
                       ProLine,
                       CustomNum,
                       CustomLot,
                       CustomPartNum,
                       CustomName,
                       ExtendFiled2,
                       ExtendFiled3,
                       CreateTime,
                       FlushStatus,
                       BackwashResult,
                       BackwashUser,
                       BackwashTime,
                       InspectSN,
                       InspectType,
                       OkQty,
                       UnOkQty,
                       InspectResult,
                       InspectUser,
                       InspectTime,
                       InboundUser,
                       InboundTime,
                       DestroyTime,
                       DestroyUser,
                       DestroyMemo,
                       PrintTime,
                       PurchaseOrder,
                       PoLine,
                       CheckLoc,
                       BoxTime,
                       BoxUser,
                       PrintQty,
                       PalletLable,
                       IsComplex,
                       ShipTo,
                       DockLoaction,
                       SupplyNum,
                       CustomPO
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                EXEC PrintFGLable @@IDENTITY, '1594943751915634689'; --半成品打印路径
                --需要将老标签注销
                UPDATE dbo.Barocde_BoxlLable
                SET Status = 7,
                    DestroyTime = GETDATE(),
                    Qty = 0,
                    ExtendFiled3 = @xxbad_extension3,
                    DestroyUser = @xxbad_user,
                    DestroyMemo = '标签合并' + @xxbad_extension3
                WHERE USN IN ( @xxbad_id, @xxbad_extension1 );
                --返回第一个dataset 到前台
                SELECT '' xxbad_id,
                       @xxbad_part xxbad_part,
                       @xxbad_qty xxbad_qty,
                       @xxbad_loc xxbad_loc,
                       @xxbad_lot xxbad_lot,
                       '' xxbad_extension1,
                       @xxbad_extension2 xxbad_extension2,
                       @xxbad_extension3 xxbad_extension3,
                       '合并成功' xxbad_extension7;
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;
            END;

            ELSE IF @ScanData = 'xxbad_id'
            BEGIN
                SET @xxbad_part = '';
                --默认第一次扫描是标签 
                SELECT @xxbad_id = USN,
                       @xxbad_part = PartNum,
                       @xxbad_qty = Qty,
                       @xxbad_loc = CurrentLoc,
                       @xxbad_lot = Lot,
                       @xxbad_supplier = CustomNum
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id
                      AND Status > 1
                      AND Status < 7;
                --判断标签是否合法
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       @xxbad_part xxbad_part,
                       @xxbad_qty xxbad_qty,
                       @xxbad_loc xxbad_loc,
                       @xxbad_lot xxbad_lot,
                       @xxbad_supplier xxbad_supplier;
            END;
            ELSE
            BEGIN
                SET @xxbad_extension4 = '';
                --否则扫描的是第二张标签
                SELECT @xxbad_extension1 = USN,
                       @xxbad_extension2 = Qty,
                       @xxbad_extension4 = PartNum,
                       @xxbad_extension5 = CurrentLoc,
                       @xxbad_extension6 = Lot,
                       @xxbad_extension7 = CustomNum
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_extension1
                      AND Status > 1
                      AND Status < 7;
                --判断标签是否合法
                IF ISNULL(@xxbad_extension4, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                --判断第二张标签是否和第一张标签零件号 库位 供应商是否一样
                IF ISNULL(@xxbad_extension4, '') <> @xxbad_part
                   OR ISNULL(@xxbad_extension5, '') <> @xxbad_loc
                   OR ISNULL(@xxbad_extension7, '') <> @xxbad_supplier
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#第二张标签和第一张标签零件号,库位,客户不匹配!#The part number, storage location, and customer of the second label do not match those of the first label!', 11, 1);

                END;
                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       @xxbad_part xxbad_part,
                       @xxbad_qty xxbad_qty,
                       @xxbad_loc xxbad_loc,
                       @xxbad_lot xxbad_lot,
                       @xxbad_supplier xxbad_supplier,
                       @xxbad_extension1 xxbad_extension1,
                       @xxbad_extension2 xxbad_extension2;
            END;

        END;
        IF @interfaceid IN ( 101 ) --质检逐箱判定
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                IF ISNULL(@xxbad_extension1, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#必须选择检验状态!#You must select a verification status!', 11, 1);

                END;
                --更新标签表中的判定结果  合格数量 不合格数量
                UPDATE barocde_materiallable
                SET inspectresult = @xxbad_extension1,
                    inspectuser = @xxbad_user,
                    inspectsn = @xxbad_order,
                    inspecttime = GETDATE()
                WHERE usn = @xxbad_id;
                --判断当前标签 是不是已经在检验子表  不存在 插入 存在则更新
                IF NOT EXISTS (SELECT TOP 1 1 FROM inspectlable WHERE usn = @xxbad_id)
                BEGIN
                    INSERT INTO [dbo].[inspectlable]
                    (
                        [id],
                        [create_by],
                        [create_time],
                        [usn],
                        [qty],
                        [inspectresult],
                        [okqty],
                        [unokqty],
                        [inspectuser],
                        [inspecttime],
                        [inspectsn]
                    )
                    SELECT NEWID(),
                           @xxbad_user,
                           GETDATE(),
                           usn,
                           qty,
                           inspectresult,
                           okqty,
                           unokqty,
                           inspectuser,
                           GETDATE(),
                           inspectsn
                    FROM barocde_materiallable
                    WHERE usn = @xxbad_id;
                END;
                IF EXISTS (SELECT TOP 1 1 FROM inspectlable WHERE usn = @xxbad_id)
                BEGIN
                    UPDATE a
                    SET a.inspectresult = b.inspectresult,
                        a.okqty = b.okqty,
                        a.unokqty = b.unokqty,
                        a.inspectuser = b.inspectuser
                    FROM barocde_materiallable b,
                         inspectlable a
                    WHERE b.usn = @xxbad_id
                          AND a.usn = b.usn;
                END;
                --检验全部在手持枪操作，单箱判定合格则整单合格 ，卷没有数量的概念 ,PC上补充质检项信息
                EXEC InspectJuge @xxbad_order, @xxbad_user, @xxbad_extension1;
                RAISERROR(N'Info_MESSAGE#判定完成!#Judgment completed!', 11, 1);

            END;
            ELSE IF @ScanData = 'xxbad_extension1'
            BEGIN
                PRINT 1;
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;
            END;
            ELSE
            BEGIN
                DECLARE @inspectstatus INT = 0;
                SELECT TOP 1
                       @xxbad_order = inspectsn,
                       @inspectstatus = status
                FROM barocde_materiallable
                WHERE usn = @xxbad_id;

                IF ISNULL(@xxbad_order, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签关联的质检单不存在!#The quality inspection sheet associated with the tag does not exist!', 11, 1);

                END;
                IF ISNULL(@inspectstatus, 0) = 0
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不存在或者状态不正确!#The tag does not exist or the status is incorrect!', 11, 1);

                END;
                IF ISNULL(@inspectstatus, 0) >= 3
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签关联的质检单已经检验!#The inspection sheet associated with the label has already been inspected!', 11, 1);

                END;
                --从标签中加载数据到前台
                SELECT usn xxbad_id,
                       partdescription xxbad_desc,
                       supplylot xxbad_lot,
                       qty xxbad_qty,
                       partnum xxbad_part,
                       supplynum xxbad_supplier,
                       inspectsn xxbad_order,
                       okqty xxbad_extension2,
                       unokqty xxbad_extension3,
                       inspectresult xxbad_extension1,
                       @xxbad_ship_id xxbad_ship_id,
                       'xxbad_extension2' READONLY
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
            END;
        END;
        IF @interfaceid IN ( 100000 ) --整单判定 暂时不启用接口正确的ID10000
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --更新质检判定主表
                UPDATE Barocde_InspectMain
                SET InspectResult = @xxbad_extension1,
                    InspectStatus = 1,
                    Reason = @xxbad_extension2
                WHERE SN = @xxbad_woid;
                --更新质检明细
                UPDATE Barcode_QualityPaperDetail
                SET InspectResult = '合格',
                    Conclude = '合格'
                WHERE MainCode = @xxbad_woid;

                RAISERROR(N'Info_MESSAGE#判定完成!#Judgment completed!', 11, 1);

            END;

            ELSE IF @ScanData = 'ComboBox'
            BEGIN
                SELECT 1;

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_woid,xxbad_purchacorder,xxbad_supplier,xxbad_desc,xxbad_extension2' READONLY;

            END;
            ELSE
            BEGIN
                --从检验单中加载信息  并且判断检验单状态
                SELECT @xxbad_woid = SN,
                       @xxbad_purchacorder = Purchaseorder,
                       @xxbad_supplier = SupplierNum,
                       @xxbad_extension1 = InspectResult,
                       @xxbad_extension2 = Reason
                FROM Barocde_InspectMain
                WHERE SN = @ScanData;

                IF (ISNULL(@xxbad_woid, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#质检单不存在!#The quality inspection sheet does not exist!', 11, 1);

                END;
                --返回第一个dataset到前台
                SELECT @xxbad_woid xxbad_woid,
                       @xxbad_purchacorder xxbad_purchacorder,
                       @xxbad_supplier xxbad_supplier,
                       @xxbad_extension1 xxbad_extension1,
                       @xxbad_extension2 xxbad_extension2,
                       'xxbad_woid,xxbad_purchacorder,xxbad_supplier,xxbad_desc' READONLY;
            END;

        END;
        DECLARE @InspectResult BIT,       --质检结果
                @InspectType BIT,         --质检类型
                @InspectUser VARCHAR(50); --质检人
        IF @interfaceid IN ( 10002 ) --原材料批量上架
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                IF ISNULL(@xxbad_toloc, '') <>
                (
                    SELECT TOP 1
                           ToLoc
                    FROM Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#不能临时修改到库位!#Temporary modification to the storage location is not allowed!', 11, 1);

                END;
                --判断是否扫描了标签
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#您没有扫描任何标签!#You have not scanned any tags!', 11, 1);

                END;
                --更新标签表的库位和上架时间批次 检验结果为合格
                UPDATE b
                SET b.fromloc = b.currentloc,
                    b.currentloc = a.ToLoc,
                    b.status = 4,
                    b.inspectresult = 1,
                    inbounduser = @xxbad_user,
                    inboundtime = GETDATE()
                FROM Barcode_OperateCache a,
                     barocde_materiallable b
                WHERE a.LableID = b.usn
                      AND a.AppID = @interfaceid
                      AND a.OpUser = @xxbad_user;
                --更新当前标签收货单的实际上架数量
                UPDATE Barcode_ShippingMain
                SET allottotal = ISNULL(allottotal, 0) + ISNULL(
                                                         (
                                                             SELECT SUM(Qty)
                                                             FROM Barcode_OperateCache
                                                             WHERE AppID = @interfaceid
                                                                   AND OpUser = @xxbad_user
                                                                   AND ExtendedField1 = Barcode_ShippingMain.SN
                                                         ),
                                                         0
                                                               );
                UPDATE Barcode_ShippingMain
                SET Status = 6
                WHERE allottotal > 0
                      AND Status = 3;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    BarcodeInterFaceID,
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @xxbad_domain,
                       @interfaceid,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       PoNum,
                       PoLine,
                       PartNum,
                       dbo.GetQADloc(MAX(CurrentLoc)),
                       dbo.GetQADloc(MAX(ToLoc)),
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       SUM(Qty),
                       ToLot,
                       ToLot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                GROUP BY PoNum,
                         PoLine,
                         PartNum,
                         ToLot;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       LableID,
                       @xxbad_user,
                       PoNum,
                       PoLine,
                       PartNum,
                       CurrentLoc,
                       ToLoc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       ExtendedField1,
                       @xxbad_id,
                       Qty,
                       ToLot,
                       ToLot,
                       @xxbad_fromref,
                       @xxbad_toref
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;

                --清除缓存表
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                RAISERROR(N'Info_MESSAGE#上架完成!#Listing completed!', 11, 1);
            END;
            ELSE IF @ScanData = 'Back'
            BEGIN
                --清除缓存表
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    SELECT 'xxbad_toloc' focus;
                END;
                --返回第一个dataset
                SELECT TOP 1
                       ToLoc xxbad_toloc,
                       PartNum xxbad_part,
                       FromSite xxbad_site,
                       'xxbad_id' focus,
                       ExtendedField1 xxbad_ship_id,
                       (
                           SELECT SUM(Qty)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_extension1,
                       (
                           SELECT COUNT(1)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_extension2
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                --返回第二个dataset
                SELECT *
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;

            END;
            ELSE IF @ScanData = 'xxbad_toloc'
            BEGIN
                --判断库位是否存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_Location
                    WHERE xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#库位不存在!#Location does not exist!', 11, 1);

                END;
                --返回第一个dateset 到前台
                SELECT @xxbad_toloc xxbad_toloc,
                       'xxbad_toloc' READONLY,
                       'xxbad_id' focus;;

            END;
            ELSE
            BEGIN
                --从标签中加载信息  并且判断标签状态
                SELECT @xxbad_ship_id = shipsn,
                       @xxbad_id = usn,
                       @xxbad_part = partnum,
                       @xxbad_desc = partdescription,
                       @xxbad_supplier = supplynum,
                       @xxbad_qty = qty,
                       @InspectType = inspecttype,
                       @InspectUser = inspectuser,
                       @xxbad_extension8 = inspectsn,
                       @InspectResult = inspectresult,
                       @xxbad_fromloc = currentloc
                FROM barocde_materiallable
                WHERE usn = @xxbad_id
                      AND
                      (
                          (status = 3
                          --AND ISNULL(InspectType, 0) = 0
                          )
                          OR
                          (
                              status = 2
                              AND ISNULL(inspecttype, 0) = 1
                          )
                      );
                --标签不正确
                IF (ISNULL(@xxbad_part, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不正确或未检验判定!#Incorrect or unverified label!', 11, 1);

                END;
                --判断从库位不能为空
                IF (ISNULL(@xxbad_fromloc, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签库位不能为空!#The label location cannot be empty!', 11, 1);

                END;
                --判断到库位不能为空
                IF (ISNULL(@xxbad_toloc, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#到库位不能为空!#The destination location cannot be empty!', 11, 1);

                END;
                --不合格品不能上架
                IF ((ISNULL(@InspectResult, 0) = 0) AND ISNULL(@InspectType, 0) = 0)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#不合格品不能上架!#Non-conforming products cannot be listed!', 11, 1);

                END;
                --判断当前零件的状态是否在QAD激活
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.pt_mstr
                    WHERE pt_part = @xxbad_part
                          AND pt_status = 'AC'
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前零件未激活，请先到QAD激活!#The current part is not activated. Please activate it in QAD first!', 11, 1);

                END;
                --如果没有配置 的检验规则的话  需要检验 质检单号
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM SupplyPartSet
                    WHERE PartNum = @xxbad_part
                          AND InspectStatus = 1
                )
                BEGIN
                    IF (ISNULL(@xxbad_extension8, '') = '')
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#当前标签对应的质检单不存在!#The quality inspection sheet corresponding to the current label does not exist!', 11, 1);

                    END;
                    --如果没有判定合格
                    IF EXISTS
                    (
                        SELECT TOP 1
                               1
                        FROM dbo.Barocde_InspectMain
                        WHERE SN = @xxbad_extension8
                              AND ISNULL(InspectStatus, 0) = 0
                              AND ISNULL(InspectResult, 0) = 0
                    )
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#当前标签对应的质检单未检验，或者检验不合格!#The quality inspection sheet corresponding to the current label has not been inspected or has failed inspection!', 11, 1);

                    END;
                END;
                --判断QAD中 从库位和到库位是否相同
                IF (dbo.GetQADloc(@xxbad_fromloc) = dbo.GetQADloc(@xxbad_toloc))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#从库位和到库位的库区相同，不能生成上架队列!#The source and destination storage areas are the same, unable to generate the shelving queue!', 11, 1);

                END;
                --判断当前原材料是否被被人缓存了
                SELECT TOP 1
                       @cacheuser = OpUser
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND LableID = @xxbad_id;
                IF (ISNULL(@cacheuser, @xxbad_user) <> @xxbad_user)
                BEGIN
                    SET @ErrorMessage
                        = N'ERROR_MESSAGE#该箱码被用户' + @cacheuser + N'扫描，请提醒其操作!#The box code has been scanned by user ' + @cacheuser + N'. Please remind them to take action!';
                    RAISERROR(@ErrorMessage, 11, 1);

                END;

                --如果在动态高速缓存表不存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND LableID = @xxbad_id
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    --从标签中获取标签信息 插入动态高速缓存表
                    INSERT INTO [dbo].[Barcode_OperateCache]
                    (
                        id,
                        [AppID],
                        [OpUser],
                        [LableID],
                        [PartNum],
                        [PartDescrition],
                        [Qty],
                        ToLot,
                        [FromLoc],
                        PoNum,
                        PoLine,
                        [CurrentLoc],
                        [ToLoc],
                        [FromSite],
                        [ToSite],
                        [ScanTime],
                        ExtendedField1
                    )
                    SELECT TOP 1
                           NEWID(),
                           @interfaceid,
                           @xxbad_user,
                           @xxbad_id,
                           partnum,
                           partdescription,
                           qty,
                           lot,
                           currentloc,
                           ponum,
                           poline,
                           currentloc,
                           @xxbad_toloc,
                           site,
                           @xxbad_site,
                           GETDATE(),
                           shipsn
                    FROM dbo.barocde_materiallable
                    WHERE usn = @xxbad_id;
                END;
                ELSE
                BEGIN
                    --DELETE [Barcode_OperateCache]
                    --WHERE AppID = @interfaceid
                    --      AND LableID = @xxbad_id
                    --      AND OpUser = @xxbad_user;
                    --SET @xxbad_rmks = '二次扫描自动解除上架当前标签';
                    RAISERROR(N'ERROR_MESSAGE#不能重复扫描当前标签!#Cannot scan the current label again!', 11, 1);
                END;
                --返回第一个dataset到前台
                SELECT TOP 1
                       ToLoc xxbad_toloc,
                       '' xxbad_id,
                       PartNum xxbad_part,
                       @xxbad_rmks xxbad_rmks,
                       'xxbad_id' focus,
                       FromSite xxbad_site,
                       ExtendedField1 xxbad_ship_id,
                       (
                           SELECT SUM(Qty)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_extension1,
                       (
                           SELECT COUNT(1)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_extension2
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                --返回第二个dataset到前台
                SELECT LableID,
                       PartNum,
                       PartDescrition
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
            END;
        END;
        IF @interfaceid IN ( 10114 ) --原材料批量移库
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断库位是否存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_Location
                    WHERE xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#库位不存在!#Location does not exist!', 11, 1);
                END;
                --判断是否扫描了标签
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#您没有扫描任何标签!#You have not scanned any tags!', 11, 1);

                END;
                --限制到库位 不能是产线库位
                IF EXISTS (SELECT TOP 1 1 FROM dbo.ProdLine WHERE LineCode = @xxbad_toloc)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#到库位不能是产线库位!#The destination location cannot be a production line location!', 11, 1);

                END;
                --更新标签表的库位和上架时间批次
                UPDATE b
                SET b.fromloc = b.currentloc,
                    b.currentloc = a.ToLoc,
                    b.lot = a.ToLot,
                    inbounduser = @xxbad_user,
                    inboundtime = GETDATE()
                FROM Barcode_OperateCache a,
                     barocde_materiallable b
                WHERE a.LableID = b.usn
                      AND a.AppID = @interfaceid
                      AND a.OpUser = @xxbad_user;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    BarcodeInterFaceID,
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @xxbad_domain,
                       @interfaceid,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       dbo.GetQADloc(MAX(CurrentLoc)),
                       dbo.GetQADloc(@xxbad_toloc),
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       SUM(Qty),
                       '',
                       ToLot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                GROUP BY CurrentLoc,
                         PartNum,
                         ToLot;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       LableID,
                       @xxbad_user,
                       PoNum,
                       PoLine,
                       PartNum,
                       CurrentLoc,
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       ExtendedField1,
                       @xxbad_id,
                       Qty,
                       ToLot,
                       ToLot,
                       @xxbad_fromref,
                       @xxbad_toref
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;

                --清除缓存表
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                RAISERROR(N'Info_MESSAGE#移库完成!#Relocation completed!', 11, 1);

            END;
            ELSE IF @ScanData = 'Back'
            BEGIN
                --清除缓存表
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    SELECT 'xxbad_toloc' focus;
                END;
                --返回第一个dataset
                SELECT TOP 1
                       ToLoc xxbad_toloc,
                       PartNum xxbad_part,
                       FromSite xxbad_site,
                       'xxbad_toloc' focus,
                       ExtendedField1 xxbad_ship_id,
                       (
                           SELECT SUM(Qty)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_extension1,
                       (
                           SELECT COUNT(1)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_extension2
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                --返回第二个dataset
                SELECT *
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
            END;
            ELSE IF @ScanData = 'xxbad_toloc'
            BEGIN
                --判断库位是否存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_Location
                    WHERE xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#库位不存在!#Location does not exist!', 11, 1);
                END;
                --返回第一个dateset 到前台
                SELECT @xxbad_toloc xxbad_toloc,
                       'xxbad_id' focus;
            END;
            ELSE
            BEGIN

                --从标签中加载信息  并且判断标签状态
                SELECT @xxbad_ship_id = shipsn,
                       @xxbad_id = usn,
                       @xxbad_part = partnum,
                       @xxbad_desc = partdescription,
                       @xxbad_supplier = supplynum,
                       @xxbad_qty = qty,
                       @InspectType = inspecttype,
                       @InspectUser = inspectuser,
                       @InspectResult = inspectresult,
                       @xxbad_fromloc = currentloc
                FROM barocde_materiallable
                WHERE usn = @xxbad_id
                      AND status = 4;

                --标签不正确
                IF (ISNULL(@xxbad_part, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不正确!#Invalid tag!', 11, 1);

                END;
                --判断从库位不能为空
                IF (ISNULL(@xxbad_fromloc, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签库位不能为空!#The label location cannot be empty!', 11, 1);

                END;
                --判断当前零件的状态是否在QAD激活
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.pt_mstr
                    WHERE pt_part = @xxbad_part
                          AND pt_status = 'AC'
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前零件未激活，请先到QAD激活!#The current part is not activated. Please activate it in QAD first!', 11, 1);

                END;
                --判断QAD中 从库位和到库位是否相同
                --IF (dbo.GetQADloc(@xxbad_fromloc) = dbo.GetQADloc(@xxbad_toloc))
                --BEGIN
                --    RAISERROR(N'ERROR_MESSAGE#从库位和到库位的库区相同，不能生成上架队列!#The source and destination storage areas are the same, unable to generate the shelving queue!', 11, 1);

                --END;
                --判断当前原材料是否被被人缓存了
                SELECT TOP 1
                       @cacheuser = OpUser
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND LableID = @xxbad_id;
                IF (ISNULL(@cacheuser, @xxbad_user) <> @xxbad_user)
                BEGIN
                    SET @ErrorMessage
                        = N'ERROR_MESSAGE#该箱码被用户' + @cacheuser + N'扫描，请提醒其操作!#The box code has been scanned by user ' + @cacheuser + N'. Please remind them to take action!';
                    RAISERROR(@ErrorMessage, 11, 1);

                END;

                --如果在动态高速缓存表不存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND LableID = @xxbad_id
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    --从标签中获取标签信息 插入动态高速缓存表
                    INSERT INTO [dbo].[Barcode_OperateCache]
                    (
                        id,
                        [AppID],
                        [OpUser],
                        [LableID],
                        [PartNum],
                        [PartDescrition],
                        [Qty],
                        ToLot,
                        [FromLoc],
                        PoNum,
                        PoLine,
                        [CurrentLoc],
                        [ToLoc],
                        [FromSite],
                        [ToSite],
                        [ScanTime],
                        ExtendedField1
                    )
                    SELECT TOP 1
                           NEWID(),
                           @interfaceid,
                           @xxbad_user,
                           @xxbad_id,
                           partnum,
                           partdescription,
                           qty,
                           lot,
                           currentloc,
                           ponum,
                           poline,
                           currentloc,
                           @xxbad_toloc,
                           site,
                           @xxbad_site,
                           GETDATE(),
                           shipsn
                    FROM dbo.barocde_materiallable
                    WHERE usn = @xxbad_id;
                END;
                ELSE
                BEGIN
                    --DELETE [Barcode_OperateCache]
                    --WHERE AppID = @interfaceid
                    --      AND LableID = @xxbad_id
                    --      AND OpUser = @xxbad_user;
                    --RAISERROR(N'Info_MESSAGE#重复扫描标签自动解除缓存!#Rescanning the label will automatically clear the cache!', 11, 1);
                    RAISERROR(N'ERROR_MESSAGE#不能重复扫描当前标签!#Cannot scan the current label again!', 11, 1);
                END;
                --返回第一个dataset到前台
                SELECT TOP 1
                       ToLoc xxbad_toloc,
                       '' xxbad_id,
                       PartNum xxbad_part,
                       FromSite xxbad_site,
                       ExtendedField1 xxbad_ship_id,
                       (
                           SELECT SUM(Qty)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_extension1,
                       (
                           SELECT COUNT(1)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_extension2
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;

                --返回第二个dataset到前台
                SELECT LableID,
                       PartNum,
                       PartDescrition
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
            END;

        END;
        IF @interfaceid IN ( 10098 ) --成品拆箱
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --再次判断标签是否合法 
                SELECT @xxbad_id = USN,
                       @xxbad_part = PartNum,
                       @xxbad_qty = Qty,
                       @xxbad_desc = PartDescription,
                       @xxbad_fromloc = CurrentLoc
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id
                      AND Status > 1
                      AND Status < 4;
                --判断标签是否合法
                IF ISNULL(@xxbad_desc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                --判断输入的拆分数量是否为空
                IF ISNULL(@xxbad_extension1, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#拆分数量不能为空!#The split quantity cannot be empty!', 11, 1);

                END;
                --判断输入的数量是否合法
                IF CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension1, 0)) <= 0
                   OR CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension1, 0)) > CONVERT(DECIMAL(18, 5), @xxbad_qty)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#Invalid split quantity!#Invalid split quantity!', 11, 1);

                END;

                SELECT @xxbad_extension2 = dbo.GetNextUSN(@xxbad_id, 0);
                INSERT dbo.Barocde_BoxlLable
                (
                    ID,
                    USN,
                    Qty,
                    Memo,
                    ExtendFiled1,
                    PartNum,
                    PartDescription,
                    Lot,
                    CurrentLoc,
                    FromLoc,
                    ToLoc,
                    WHloc,
                    Site,
                    LastStatus,
                    Status,
                    WorkOp,
                    PkgQty,
                    WoNum,
                    ShipSN,
                    Wo_DueDate,
                    ProLine,
                    CustomNum,
                    CustomLot,
                    CustomPartNum,
                    CustomName,
                    ExtendFiled2,
                    ExtendFiled3,
                    CreateTime,
                    FlushStatus,
                    BackwashResult,
                    BackwashUser,
                    BackwashTime,
                    InspectSN,
                    InspectType,
                    OkQty,
                    UnOkQty,
                    InspectResult,
                    InspectUser,
                    InspectTime,
                    InboundUser,
                    InboundTime,
                    DestroyTime,
                    DestroyUser,
                    DestroyMemo,
                    PrintTime,
                    PurchaseOrder,
                    PoLine,
                    CheckLoc,
                    BoxTime,
                    BoxUser,
                    PrintQty,
                    PalletLable,
                    IsComplex,
                    ShipTo,
                    DockLoaction,
                    SupplyNum,
                    CustomPO,
                    labletype
                )
                SELECT NEWID(),
                       @xxbad_extension2,
                       CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension1, 0)),
                       @xxbad_extension1 + @xxbad_id + '标签合并',
                       @xxbad_id,
                       PartNum,
                       PartDescription,
                       Lot,
                       CurrentLoc,
                       FromLoc,
                       ToLoc,
                       WHloc,
                       Site,
                       LastStatus,
                       Status,
                       WorkOp,
                       PkgQty,
                       WoNum,
                       ShipSN,
                       Wo_DueDate,
                       ProLine,
                       CustomNum,
                       CustomLot,
                       CustomPartNum,
                       CustomName,
                       ExtendFiled2,
                       ExtendFiled3,
                       CreateTime,
                       FlushStatus,
                       BackwashResult,
                       BackwashUser,
                       BackwashTime,
                       InspectSN,
                       InspectType,
                       OkQty,
                       UnOkQty,
                       InspectResult,
                       InspectUser,
                       InspectTime,
                       InboundUser,
                       InboundTime,
                       DestroyTime,
                       DestroyUser,
                       DestroyMemo,
                       PrintTime,
                       PurchaseOrder,
                       PoLine,
                       CheckLoc,
                       BoxTime,
                       BoxUser,
                       PrintQty,
                       PalletLable,
                       IsComplex,
                       ShipTo,
                       DockLoaction,
                       SupplyNum,
                       CustomPO,
                       labletype
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;

                EXEC PrintFGLable @@IDENTITY, '1594943751915634689'; --半成品打印路径
                --生成第二张新标签

                SET @xxbad_extension3 = dbo.GetNextUSN(@xxbad_id, 0);
                INSERT dbo.Barocde_BoxlLable
                (
                    ID,
                    USN,
                    Qty,
                    Memo,
                    ExtendFiled1,
                    PartNum,
                    PartDescription,
                    Lot,
                    CurrentLoc,
                    FromLoc,
                    ToLoc,
                    WHloc,
                    Site,
                    LastStatus,
                    Status,
                    WorkOp,
                    PkgQty,
                    WoNum,
                    ShipSN,
                    Wo_DueDate,
                    ProLine,
                    CustomNum,
                    CustomLot,
                    CustomPartNum,
                    CustomName,
                    ExtendFiled2,
                    ExtendFiled3,
                    CreateTime,
                    FlushStatus,
                    BackwashResult,
                    BackwashUser,
                    BackwashTime,
                    InspectSN,
                    InspectType,
                    OkQty,
                    UnOkQty,
                    InspectResult,
                    InspectUser,
                    InspectTime,
                    InboundUser,
                    InboundTime,
                    DestroyTime,
                    DestroyUser,
                    DestroyMemo,
                    PrintTime,
                    PurchaseOrder,
                    PoLine,
                    CheckLoc,
                    BoxTime,
                    BoxUser,
                    PrintQty,
                    PalletLable,
                    IsComplex,
                    ShipTo,
                    DockLoaction,
                    SupplyNum,
                    CustomPO,
                    labletype
                )
                SELECT NEWID(),
                       @xxbad_extension3,
                       CONVERT(DECIMAL(18, 5), @xxbad_qty) - CONVERT(DECIMAL(18, 5), @xxbad_extension1),
                       @xxbad_extension1 + @xxbad_id + '标签合并',
                       @xxbad_id,
                       PartNum,
                       PartDescription,
                       Lot,
                       CurrentLoc,
                       FromLoc,
                       ToLoc,
                       WHloc,
                       Site,
                       LastStatus,
                       Status,
                       WorkOp,
                       PkgQty,
                       WoNum,
                       ShipSN,
                       Wo_DueDate,
                       ProLine,
                       CustomNum,
                       CustomLot,
                       CustomPartNum,
                       CustomName,
                       ExtendFiled2,
                       ExtendFiled3,
                       CreateTime,
                       FlushStatus,
                       BackwashResult,
                       BackwashUser,
                       BackwashTime,
                       InspectSN,
                       InspectType,
                       OkQty,
                       UnOkQty,
                       InspectResult,
                       InspectUser,
                       InspectTime,
                       InboundUser,
                       InboundTime,
                       DestroyTime,
                       DestroyUser,
                       DestroyMemo,
                       PrintTime,
                       PurchaseOrder,
                       PoLine,
                       CheckLoc,
                       BoxTime,
                       BoxUser,
                       PrintQty,
                       PalletLable,
                       IsComplex,
                       ShipTo,
                       DockLoaction,
                       SupplyNum,
                       CustomPO,
                       labletype
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                EXEC PrintFGLable @@IDENTITY, '1594943751915634689'; --半成品打印路径
                --需要将老标签注销
                UPDATE dbo.Barocde_BoxlLable
                SET Status = 7,
                    DestroyTime = GETDATE(),
                    Qty = 0,
                    DestroyUser = @xxbad_user,
                    DestroyMemo = '标签拆分：第一个' + @xxbad_extension2 + '第二个' + @xxbad_extension3
                WHERE USN = @xxbad_id;
                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       @xxbad_part xxbad_part,
                       @xxbad_qty xxbad_qty,
                       @xxbad_fromloc xxbad_fromloc,
                       'xxbad_extension1' READONLY,
                       @xxbad_supplier xxbad_supplier,
                       @xxbad_extension2 xxbad_extension2,
                       @xxbad_extension3 xxbad_extension3;
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;
            END;

            ELSE
            BEGIN
                --默认第一次扫描是标签 
                SELECT @xxbad_id = USN,
                       @xxbad_part = PartNum,
                       @xxbad_supplier = SupplyNum,
                       @xxbad_qty = Qty,
                       @xxbad_fromloc = CurrentLoc
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id
                      AND Status > 1
                      AND Status < 4;
                --判断标签是否合法
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       @xxbad_part xxbad_part,
                       @xxbad_qty xxbad_qty,
                       @xxbad_fromloc xxbad_fromloc,
                       @xxbad_supplier xxbad_supplier;
            END;
        END;
        IF @interfaceid IN ( 10004 ) --原材料单箱上架
        BEGIN

            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --将到库位转化成库区
                DECLARE @locarea VARCHAR(50);
                SELECT TOP 1
                       @locarea = LocArea
                FROM dbo.Barcode_Location
                WHERE xxlocation_loc = @xxbad_toloc;
                IF ISNULL(@locarea, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前到库位库区不存在!#The current storage location does not exist!', 11, 1);

                END;
                --将从库位转化成QAD库位
                DECLARE @QADfrom VARCHAR(50);
                SELECT TOP 1
                       @QADfrom = LocArea
                FROM dbo.Barcode_Location
                WHERE xxlocation_loc = @xxbad_fromloc;
                --判断 到库位 是否在零件的配置的库区内
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_Location
                    WHERE LocArea IN
                          (
                              SELECT LocArea
                              FROM Barcode_ItemLocArea
                              WHERE ItemNum = @xxbad_part
                                    AND tenant_id = @xxbad_site
                          )
                          AND xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前原材料不能上架到此库区!#The current raw materials cannot be stocked in this warehouse area!', 11, 1);

                END;
                --判断从库位的业务限制逻辑
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_LocStatusCode
                    WHERE IsAvailble = 1
                          AND ISS_TR = 1
                          AND StatusCode =
                          (
                              SELECT TOP 1 StatusCode FROM Barcode_LocArea WHERE Name = @QADfrom
                          )
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前从库位限制移除!#Current location restriction removed!', 11, 1);

                END;
                --判断到库位的业务限制逻辑
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_LocStatusCode
                    WHERE IsAvailble = 1
                          AND RCT_TR = 1
                          AND StatusCode =
                          (
                              SELECT TOP 1 StatusCode FROM Barcode_LocArea WHERE Name = @locarea
                          )
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前到库位限制移入!#Current location limit reached for moving in!', 11, 1);

                END;
                --更新标签表的库位和上架时间批次
                UPDATE barocde_materiallable
                SET fromloc = currentloc,
                    currentloc = @xxbad_toloc,
                    status = 4,
                    lot = CONVERT(CHAR(8), GETDATE(), 112),
                    inbounduser = @xxbad_user,
                    inboundtime = GETDATE()
                WHERE usn = @xxbad_id;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotto
                )
                SELECT @xxbad_domain,
                       'PQ_IC_POPORC',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       ponum,
                       poline,
                       partnum,
                       @QADfrom,
                       @locarea,
                       site,
                       site,
                       '',
                       usn,
                       qty,
                       lot
                FROM barocde_materiallable
                WHERE usn = @xxbad_id;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       usn,
                       @xxbad_user,
                       ponum,
                       poline,
                       partnum,
                       @xxbad_fromloc,
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       qty,
                       lot,
                       lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM barocde_materiallable
                WHERE usn = @xxbad_id;
                RAISERROR(N'Info_MESSAGE#上架完成!#Listing completed!', 11, 1);
            END;

            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 1;
            END;
            ELSE
            BEGIN

                --从标签中加载信息  并且判断标签状态
                SELECT @xxbad_ship_id = shipsn,
                       @xxbad_id = usn,
                       @xxbad_part = partnum,
                       @xxbad_desc = partdescription,
                       @xxbad_supplier = supplynum,
                       @xxbad_qty = qty,
                       @InspectUser = inspectuser,
                       @InspectType = inspecttype,
                       @InspectResult = inspectresult,
                       @xxbad_fromloc = currentloc
                FROM barocde_materiallable
                WHERE usn = @xxbad_id
                      AND
                      (
                          (
                              status = 3
                              AND ISNULL(inspecttype, 0) = 0
                          )
                          OR
                          (
                              status = 2
                              AND ISNULL(inspecttype, 0) = 1
                          )
                      );
                IF (ISNULL(@xxbad_part, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不正确!#Invalid tag!', 11, 1);

                END;
                --判断从库位不能为空
                IF (ISNULL(@xxbad_fromloc, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签库位不能为空!#The label location cannot be empty!', 11, 1);

                END;
                --如果是非免检的零件 进行是否检验合格判断
                IF ISNULL(@InspectType, 0) = 0
                BEGIN

                    IF (ISNULL(@InspectResult, 0) = 0)
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#不合格品不能上架!#Non-conforming products cannot be listed!', 11, 1);

                    END;
                END;
                --返回第一个dataset到前台
                SELECT @xxbad_ship_id xxbad_ship_id,
                       @xxbad_id xxbad_id,
                       @xxbad_part xxbad_part,
                       @xxbad_desc xxbad_desc,
                       @xxbad_supplier xxbad_supplier,
                       @xxbad_qty xxbad_qty,
                       pt_loc xxbad_toloc,
                       @xxbad_fromloc xxbad_fromloc,
                       'xxbad_toloc' READONLY
                FROM pt_mstr
                WHERE pt_part = @xxbad_part
                      AND pt_domain = @xxbad_domain
                      AND pt_site = @xxbad_site;
            END;
        END;
        IF @interfaceid IN ( 1989 ) --电子仓库调拨备料
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断补料单是否可用
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           AllotNum
                    FROM dbo.BarocodeFeedLine
                    WHERE Useble = 1
                          AND Status = 1
                          AND AllotNum = @xxbad_extension2
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#备料单不可用!#Material list unavailable!', 11, 1);

                END;

                --判断备料总量是否大于需求量
                IF CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_rj_qty, 0)) < CONVERT(
                                                                                  DECIMAL(18, 5),
                                                                                  ISNULL(@xxbad_extension1, 0)
                                                                              )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#备料量不能大于需求量!#The preparation quantity cannot exceed the required quantity!', 11, 1);

                END;
                --更新备料单表状态,并且关闭备料单 设置为在途
                UPDATE BarocodeFeedLine
                SET Status = 2,
                    AllotEndTime = GETDATE()
                WHERE AllotNum = @xxbad_extension2
                      AND OkQty IS NOT NULL;
                --更新备料明细表中的状态为备料完成
                UPDATE dbo.Barcode_AllotDetail
                SET Stauts = 1
                WHERE AllotNum = @xxbad_extension2
                      AND Stauts = 0;
                RAISERROR(N'Info_MESSAGE#备料完成!#Material preparation completed!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                --返回第一个dataset数据给前台
                SELECT SUM(1) xxbad_qty,
                       SUM(Qty) xxbad_extension1,
                       MAX(ToLoc) xxbad_toloc,
                       MAX(Site) xxbad_site,
                       (
                           SELECT SUM(NeedQty)
                           FROM dbo.BarocodeFeedLine
                           WHERE AllotNum = @xxbad_extension2
                                 AND TvNum = 3
                       ) xxbad_rj_qty,
                       MAX(ScanTime) ScanTime,
                       MAX(PartNum) xxbad_part
                FROM Barcode_AllotDetail
                WHERE AllotNum = @xxbad_extension2
                ORDER BY ScanTime;
                --返回第二个dataset数据给前台
                SELECT DISTINCT
                       a.PartNum,
                       a.NeedQty,
                       a.OkQty,
                       b.currentloc,
                       b.lot
                FROM dbo.BarocodeFeedLine a
                    LEFT JOIN dbo.barocde_materiallable b
                        ON b.status = 4
                           AND b.partnum = a.PartNum
                WHERE a.AllotNum = @xxbad_extension2
                      AND a.Status < 2
                      AND a.TvNum = 3
                ORDER BY b.lot;

            END;
            ELSE IF @ScanData = 'ComboBox'
            BEGIN
                --返回第一个dataset数据给前台
                SELECT SUM(1) xxbad_qty,
                       SUM(Qty) xxbad_extension1,
                       MAX(ToLoc) xxbad_toloc,
                       MAX(Site) xxbad_site,
                       (
                           SELECT SUM(NeedQty)
                           FROM dbo.BarocodeFeedLine
                           WHERE AllotNum = @xxbad_extension2
                                 AND TvNum = 3
                       ) xxbad_rj_qty,
                       MAX(ScanTime) ScanTime,
                       MAX(PartNum) xxbad_part
                FROM Barcode_AllotDetail
                WHERE AllotNum = @xxbad_extension2
                ORDER BY ScanTime;
                --返回第二个dataset数据给前台
                SELECT PartNum,
                       (
                           SELECT TOP 1
                                  usn + ';' + currentloc
                           FROM barocde_materiallable
                           WHERE partnum = BarocodeFeedLine.PartNum
                                 AND status = 4
                           ORDER BY lot,
                                    usn
                       ) USN
                FROM dbo.BarocodeFeedLine
                WHERE AllotNum = @xxbad_extension2
                      AND TvNum = 3
                ORDER BY USN DESC;
            END;
            ELSE
            BEGIN
                SET @xxbad_part = ''; --标签的零件号
                DECLARE @NeedQty1989 DECIMAL; --总需求量
                DECLARE @Qty1989 DECIMAL; --标签的数量
                DECLARE @TotalQty DECIMAL; --总备料量
                DECLARE @lot VARCHAR(50); --标签的批次
                DECLARE @Box INT; --箱数
                --判断标签不在电子仓内且不在异常库位
                SELECT TOP 1
                       @xxbad_part = partnum,
                       @Qty1989 = qty,
                       @lot = lot
                FROM dbo.barocde_materiallable
                WHERE usn = @ScanData
                      AND status = 4
                      AND LEFT(currentloc, 2) <> 'NG';
                PRINT @ScanData;
                IF ISNULL(@Qty1989, 0) = 0
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不存在!#Tag does not exist!', 11, 1);

                END;

                --判断标签零件是否和备料单匹配 顺便取出需求量
                SELECT TOP 1
                       @NeedQty1989 = NeedQty
                FROM dbo.BarocodeFeedLine
                WHERE AllotNum = @xxbad_extension2
                      AND PartNum = @xxbad_part
                      AND TvNum = 3;
                IF (ISNULL(@NeedQty1989, 0) = 0)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#零件和备料单不匹配!#Parts and material list do not match!', 11, 1);

                END;
                --判断标签批次是否满足先进先出规则 顺便取出零件号和标签数量
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.barocde_materiallable
                    WHERE lot < @lot
                          AND partnum = @xxbad_part
                          AND status = 4
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请扫码更早批次的标签!#Please scan the label from an earlier batch!', 11, 1);

                END;


                --如果备料明细表中已经存在 则解除备料 如果不存在则插入
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_AllotDetail
                    WHERE USN = @ScanData
                          AND AllotNum = @xxbad_extension2
                )
                BEGIN
                    --解除备料明细
                    DELETE FROM Barcode_AllotDetail
                    WHERE USN = @ScanData
                          AND AllotNum = @xxbad_extension2;
                    --还原标签的状态 
                    UPDATE dbo.barocde_materiallable
                    SET status = 4
                    WHERE usn = @ScanData;
                END;
                ELSE
                BEGIN
                    --获取当前零件 已经备料总量
                    SELECT @TotalQty = ISNULL(SUM(Qty), 0),
                           @Box = SUM(1)
                    FROM dbo.Barcode_AllotDetail
                    WHERE AllotNum = @xxbad_extension2
                          AND PartNum = @xxbad_part;
                    --判断当前备料单 当前零件是否超量备料
                    IF @TotalQty + @Qty1989 > @NeedQty1989
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#当前零件已经超量，请换其他零件!#The current part is overstocked, please use another part!', 11, 1);

                    END;
                    --插入备料明细表
                    INSERT INTO Barcode_AllotDetail
                    SELECT @xxbad_extension2,
                           partnum,
                           usn,
                           qty,
                           currentloc,
                           (
                               SELECT TOP 1
                                      ToLoc
                               FROM dbo.BarocodeFeedLine
                               WHERE AllotNum = @xxbad_extension2
                           ),
                           lot,
                           site,
                           0
                    FROM dbo.barocde_materiallable
                    WHERE USN = @ScanData;

                    --更新标签的状态 表示已经备料 库位在提交的时候发生改变
                    UPDATE dbo.barocde_materiallable
                    SET status = 5
                    WHERE usn = @ScanData;
                END;
                --更新备料主表 备料人 备料开始时间 状态 已备料量
                UPDATE BarocodeFeedLine
                SET AllotUser = @xxbad_user,
                    AllotStartTime = GETDATE(),
                    Status = 1,
                    OkQty = @TotalQty + @Qty1989
                WHERE AllotNum = @xxbad_extension2
                      AND PartNum = @xxbad_part;

                --返回第一个dataset数据给前台
                SELECT SUM(1) xxbad_qty,
                       SUM(Qty) xxbad_extension1,
                       @NeedQty1989 xxbad_rj_qty,
                       MAX(ToLoc) xxbad_toloc,
                       @xxbad_part xxbad_part
                FROM Barcode_AllotDetail
                WHERE AllotNum = @xxbad_extension2;

                --返回第二个dateset 到前台 未备料明细
                SELECT DISTINCT
                       a.PartNum,
                       a.NeedQty,
                       a.OkQty,
                       b.currentloc,
                       b.lot
                FROM dbo.BarocodeFeedLine a
                    LEFT JOIN dbo.barocde_materiallable b
                        ON b.status = 4
                           AND b.partnum = a.PartNum
                WHERE a.AllotNum = @xxbad_extension2
                      AND a.Status < 2
                      AND a.TvNum = 3
                ORDER BY b.lot;
            END;
        END;
        IF @interfaceid IN ( 10012 ) --金属件叫料
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --根据获得的产线 查找回冲库位
                SELECT TOP 1
                       @xxbad_toloc = Loc
                FROM dbo.ProdLine
                WHERE LineCode = @xxbad_proline;
                --判断是否配置拉动参数
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.PartMovingSet
                    WHERE ProdLine = @xxbad_proline
                          AND pt_part = @xxbad_part
                          AND PartType = 1
                )
                BEGIN
                    RAISERROR(N'Info_MESSAGE#当前金属件在当前产线没有配置拉动参数!#The current metal part does not have pull parameters configured on the current production line!', 11, 1);

                END;
                --生成备料单号临时表
                CREATE TABLE #SeqenceNumber
                (
                    ft VARCHAR(20),
                    Line VARCHAR(50)
                );
                --生成一个新的备料单号
                INSERT INTO #SeqenceNumber
                EXEC [MakeSeqenceNum] '00000006', @xxbad_proline;
                --插入一个新的1号看板备料信息
                INSERT INTO [dbo].[BarocodeFeedLine]
                (
                    [AllotNum],
                    Line,
                    [PartNum],
                    PartType,
                    [NeedQty],
                    AllotBox,
                    [ToLoc],
                    [CallTime],
                    [CallPerson],
                    [Site],
                    [Status],
                    [Useble],
                    [UrgencyLevel],
                    TvNum,
                    SouceAllotNum
                )
                SELECT ft,
                       @xxbad_proline,
                       @xxbad_part,
                       1,
                       @xxbad_qty,
                       1,
                       @xxbad_toloc,
                       GETDATE(),
                       @xxbad_user,
                       @xxbad_site,
                       0,
                       1,
                       1,
                       1,
                       @xxbad_extension2
                FROM #SeqenceNumber;
                --更改2号看板的备料信息状态
                UPDATE BarocodeFeedLine
                SET Status = 1,
                    AllotUser = @xxbad_user,
                    AllotStartTime = GETDATE(),
                    AllotEndTime = GETDATE(),
                    OkQty = @xxbad_qty
                WHERE AllotNum = @xxbad_extension2
                      AND PartNum = @xxbad_part;
                RAISERROR(N'Info_MESSAGE#提交成功!#Submission successful!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 1;
                SELECT 1;

            END;
            ELSE IF @ScanData = 'ComboBox'
            BEGIN
                SELECT 1;
                SELECT 1;

            END;
            ELSE --认为处理扫描器具码 数据
            BEGIN
                --取出扫描的器具码信息
                DECLARE @PartNum VARCHAR(50);
                DECLARE @Line VARCHAR(50);
                DECLARE @Qty DECIMAL; --器具容量
                SELECT @PartNum = PartNum,
                       @Qty = NeedQty,
                       @Line = Line
                FROM UtensilCode
                WHERE Code = @ScanData;
                --判断器具码是否合法
                IF ISNULL(@PartNum, '') = ''
                BEGIN
                    RAISERROR(N'Info_MESSAGE#器具码不存在!#The equipment code does not exist!', 11, 1);

                END;
                --返回第一个dataset 到前台
                SELECT @ScanData xxbad_extension3,
                       'xxbad_qty' READONLY,
                       @PartNum xxbad_part,
                       @Qty xxbad_qty,
                       @Line xxbad_proline;
            END;
        END;
        IF @interfaceid IN ( 10011 ) --通用扫描解除
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                DELETE FROM dbo.Barcode_OperateCache
                WHERE LableID = @xxbad_id
                      AND OpUser = @xxbad_user;
                RAISERROR(N'Info_MESSAGE#提交成功!#Submission successful!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;
                SELECT 1;

            END;
            ELSE --认为处理
            BEGIN
                SELECT AppID xxbad_extension2,
                       OpUser xxbad_extension1,
                       LableID xxbad_id,
                       PartNum xxbad_part,
                       ShipID xxbad_ship_id,
                       Qty xxbad_qty,
                       CurrentLoc xxbad_loc,
                       ScanTime xxbad_shiptime
                FROM dbo.Barcode_OperateCache
                WHERE OpUser = @xxbad_user
                      AND LableID = @xxbad_id;

            END;
        END;
        IF @interfaceid IN ( 5222 ) --电子件备料标签收货
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断备料单是否已经结束

                --判断所有标签 是否被扫描 如果全部扫描则关闭备料单
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_AllotDetail
                    WHERE AllotNum = @xxbad_extension2
                          AND Stauts = 1
                )
                BEGIN
                    UPDATE dbo.BarocodeFeedLine
                    SET Status = 4
                    WHERE AllotNum = @xxbad_extension2
                          AND Status = 3;
                END;
                --更新主表信息，状态 收货人，收货时间,数量
                UPDATE dbo.BarocodeFeedLine
                SET ReceiptQty =
                    (
                        SELECT SUM(Qty)
                        FROM dbo.Barcode_AllotDetail
                        WHERE AllotNum = @xxbad_extension2
                              AND Stauts = 2
                    ),
                    ReceiptUser = @xxbad_user,
                    ReceiptEndTime = GETDATE()
                WHERE AllotNum = @xxbad_extension2
                      AND Status = 3;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg]
                )
                SELECT @xxbad_domain,
                       'IC_TR',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       dbo.GetQADloc(Loc),
                       dbo.GetQADloc(MAX(ToLoc)),
                       Lot,
                       Lot,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       SUM(1),
                       SUM(Qty)
                FROM dbo.Barcode_AllotDetail
                WHERE AllotNum = @xxbad_extension2
                      AND Stauts = 2
                GROUP BY AllotNum,
                         PartNum,
                         Lot,
                         Loc;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       USN,
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       Loc,
                       ToLoc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       AllotNum,
                       @xxbad_id,
                       Qty,
                       Lot,
                       Lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM dbo.Barcode_AllotDetail
                WHERE AllotNum = @xxbad_extension2
                      AND Stauts = 2;

                RAISERROR(N'Info_MESSAGE#提交成功!#Submission successful!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                --汇总返回第一个dataset
                SELECT MAX(PartNum) xxbad_part,
                       MAX(Line) xxbad_proline,
                       MAX(ToLoc) xxbad_toloc,
                       SUM(OkQty) xxbad_scrapqty,
                       SUM(NeedQty) xxbad_qty
                FROM dbo.BarocodeFeedLine
                WHERE AllotNum = @xxbad_extension2
                      AND Status IN ( 2, 3 );
                --返回第二个dataset 到前台		
                SELECT PartNum,
                       USN,
                       Qty
                FROM dbo.Barcode_AllotDetail
                WHERE AllotNum = @xxbad_extension2
                      AND Stauts = 1;
            END;
            ELSE IF @ScanData = 'ComboBox'
            BEGIN
                --汇总返回第一个dataset
                SELECT MAX(PartNum) xxbad_part,
                       MAX(Line) xxbad_proline,
                       MAX(ToLoc) xxbad_toloc,
                       SUM(OkQty) xxbad_scrapqty,
                       SUM(NeedQty) xxbad_qty
                FROM dbo.BarocodeFeedLine
                WHERE AllotNum = @xxbad_extension2
                      AND Status = 2;
                --返回第二个dataset 到前台		
                SELECT PartNum,
                       USN,
                       Qty
                FROM dbo.Barcode_AllotDetail
                WHERE AllotNum = @xxbad_extension2
                      AND Stauts = 1;
            END;
            ELSE --认为处理条码 数据
            BEGIN
                SELECT TOP 1
                       @PartNum = PartNum
                FROM dbo.Barcode_AllotDetail
                WHERE AllotNum = @xxbad_extension2
                      AND Stauts = 1
                      AND USN = @ScanData;
                --判断标签是否在备料明细中
                IF ISNULL(@PartNum, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不在当前备料单中!#The label is not in the current material list!', 11, 1);

                END;
                --如果全部被收货 则更新主表信息，状态 收货人，收货时间
                UPDATE dbo.BarocodeFeedLine
                SET Status = 3,
                    ReceiptStartTime = GETDATE()
                WHERE AllotNum = @xxbad_extension2
                      AND PartNum = @PartNum
                      AND Status = 2;
                --如果在备料明细中 更新明细表的状态,标识标签已收货
                UPDATE Barcode_AllotDetail
                SET Stauts = 2
                WHERE AllotNum = @xxbad_extension2
                      AND Stauts = 1
                      AND USN = @ScanData;
                --更改标签的库位，状态
                UPDATE dbo.barocde_materiallable
                SET currentloc = @xxbad_toloc,
                    status = 6
                WHERE usn = @ScanData;
                --返回第一个dataset 到前台 不清空主表
                SELECT @PartNum xxbad_part,
                       @xxbad_proline xxbad_proline,
                       @xxbad_toloc xxbad_toloc,
                       @xxbad_scrapqty xxbad_scrapqty,
                       @xxbad_qty xxbad_qty;

                --返回第二个dataset 到前台 未扫描的标签列表
                SELECT PartNum,
                       USN,
                       Qty
                FROM dbo.Barcode_AllotDetail
                WHERE AllotNum = @xxbad_extension2
                      AND Stauts = 1;
            END;
        END;
        IF @interfaceid IN ( 730 ) --仓库原材料通用移库
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN

                --判断当前库位 是否和到库位相同
                SELECT @xxbad_fromloc = currentloc,
                       @xxbad_lot = lot,
                       @xxbad_part = partnum,
                       @xxbad_qty = qty
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id
                      AND status = 4;
                IF ISNULL(@xxbad_fromloc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                --判断当前 库存 是否足够移库
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.barocde_stock
                    WHERE partnum = @xxbad_part
                          AND loc = @xxbad_fromloc
                          AND lot = @xxbad_lot
                          AND qty >= @xxbad_qty
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#从库位没有足够此批次的零件移库!#There are not enough parts of this batch in the storage location for transfer!', 11, 1);

                END;
                IF (ISNULL(@xxbad_fromloc, '') = ISNULL(@xxbad_toloc, ''))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前标签已经在到库位下面了!#The current label is already under the destination location!', 11, 1);

                END;
                --更新标签的库位
                UPDATE dbo.barocde_materiallable
                SET fromloc = currentloc,
                    currentloc = @xxbad_toloc
                WHERE usn = @xxbad_id;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg]
                )
                SELECT @xxbad_domain,
                       'IC_TR',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       '',
                       partnum,
                       dbo.GetQADloc(@xxbad_fromloc),
                       dbo.GetQADloc(@xxbad_toloc),
                       lot,
                       lot,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       usn,
                       qty
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       usn,
                       @xxbad_user,
                       '',
                       '',
                       partnum,
                       @xxbad_fromloc,
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       @xxbad_id,
                       qty,
                       lot,
                       lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
                RAISERROR(N'Info_MESSAGE#提交成功!#Submission successful!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_toloc' READONLY;
            END;
            ELSE IF @ScanData = 'xxbad_toloc'
            BEGIN
                --判断库位是否合法
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_Location
                    WHERE xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    SELECT @xxbad_toloc xxbad_toloc,
                           'xxbad_id' focus;
                END;
                ELSE
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#库位不存在!#Location does not exist!', 11, 1);

                END;
            END;
            ELSE --认为扫描的是条码数据
            BEGIN
                --如果到库位是空 默认认为扫描的是到库位
                BEGIN --认为扫描的是标签
                    --读取标签中的信息
                    SELECT @xxbad_id = usn,
                           @xxbad_qty = qty,
                           @xxbad_part = partnum,
                           @xxbad_desc = partdescription,
                           @xxbad_fromloc = currentloc
                    FROM dbo.barocde_materiallable
                    WHERE usn = @xxbad_id
                          AND status = 4;
                    --判断标签是否合法
                    IF ISNULL(@xxbad_part, '') = ''
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                    END;
                    --判断零件是否可以移库到到库位
                    SELECT @msg_error = dbo.CheckLocArea(@xxbad_part, @xxbad_toloc, 1);
                    IF ISNULL(@msg_error, '') <> ''
                    BEGIN
                        RAISERROR(@msg_error, 11, 1);

                    END;
                    --判断零件是否可以从从库位移除
                    SELECT @msg_error = dbo.CheckLocArea(@xxbad_part, @xxbad_fromloc, 0);
                    IF ISNULL(@msg_error, '') <> ''
                    BEGIN
                        RAISERROR(@msg_error, 11, 1);

                    END;
                    --返回第一个dataset 到前台
                    SELECT @xxbad_id xxbad_id,
                           @xxbad_qty xxbad_qty,
                           @xxbad_part xxbad_part,
                           @xxbad_desc xxbad_desc,
                           @xxbad_fromloc xxbad_fromloc,
                           @xxbad_toloc xxbad_toloc;
                END;
            END;
        END;
        IF @interfaceid IN ( 10014 ) --金属仓库调拨备料
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断补料单是否可用
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           AllotNum
                    FROM dbo.BarocodeFeedLine
                    WHERE Useble = 1
                          AND Status = 1
                          AND AllotNum = @xxbad_extension2
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#备料单不可用!#Material list unavailable!', 11, 1);

                END;
                IF @xxbad_rj_qty = ''
                   OR @xxbad_extension1 = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#不能提交空数据!#Cannot submit empty data!', 11, 1);

                END;
                --判断备料总量是否大于需求量
                IF CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_rj_qty, 0)) < CONVERT(
                                                                                  DECIMAL(18, 5),
                                                                                  ISNULL(@xxbad_extension1, 0)
                                                                              )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#备料量不能大于需求量!#The preparation quantity cannot exceed the required quantity!', 11, 1);

                END;
                --更新备料单表状态,并且关闭备料单 设置为在途
                UPDATE BarocodeFeedLine
                SET Status = 2,
                    AllotEndTime = GETDATE()
                WHERE AllotNum = @xxbad_extension2
                      AND OkQty IS NOT NULL;
                --更新备料明细表中的状态为备料完成
                UPDATE dbo.Barcode_AllotDetail
                SET Stauts = 1
                WHERE AllotNum = @xxbad_extension2
                      AND Stauts = 0;
                RAISERROR(N'Info_MESSAGE#备料完成!#Material preparation completed!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                --返回第一个dataset数据给前台
                SELECT SUM(1) xxbad_qty,
                       SUM(Qty) xxbad_extension1,
                       MAX(ToLoc) xxbad_toloc,
                       MAX(Site) xxbad_site,
                       (
                           SELECT SUM(NeedQty)
                           FROM dbo.BarocodeFeedLine
                           WHERE AllotNum = @xxbad_extension2
                                 AND TvNum = 1
                       ) xxbad_rj_qty,
                       MAX(ScanTime) ScanTime,
                       MAX(PartNum) xxbad_part
                FROM Barcode_AllotDetail
                WHERE AllotNum = @xxbad_extension2
                ORDER BY ScanTime;
                --返回第二个dataset数据给前台
                SELECT DISTINCT
                       a.PartNum,
                       a.NeedQty,
                       a.OkQty,
                       b.currentloc,
                       b.lot
                FROM dbo.BarocodeFeedLine a
                    LEFT JOIN dbo.barocde_materiallable b
                        ON b.status = 4
                           AND b.partnum = a.PartNum
                WHERE a.AllotNum = @xxbad_extension2
                      AND a.Status < 2
                      AND a.TvNum = 1;
            END;
            ELSE IF @ScanData = 'ComboBox'
            BEGIN
                --返回第一个dataset数据给前台
                SELECT SUM(1) xxbad_qty,
                       SUM(Qty) xxbad_extension1,
                       MAX(ToLoc) xxbad_toloc,
                       MAX(Site) xxbad_site,
                       (
                           SELECT SUM(NeedQty)
                           FROM dbo.BarocodeFeedLine
                           WHERE AllotNum = @xxbad_extension2
                                 AND TvNum = 1
                       ) xxbad_rj_qty,
                       MAX(ScanTime) ScanTime,
                       MAX(PartNum) xxbad_part
                FROM Barcode_AllotDetail
                WHERE AllotNum = @xxbad_extension2
                ORDER BY ScanTime;
                --返回第二个dataset数据给前台
                SELECT PartNum,
                       (
                           SELECT TOP 1
                                  usn + ';' + currentloc
                           FROM barocde_materiallable
                           WHERE partnum = BarocodeFeedLine.PartNum
                                 AND status = 4
                           ORDER BY lot,
                                    usn
                       ) USN
                FROM dbo.BarocodeFeedLine
                WHERE AllotNum = @xxbad_extension2
                      AND TvNum = 1
                ORDER BY USN DESC;
            END;
            ELSE
            BEGIN
                SET @xxbad_part = ''; --标签的零件号
                DECLARE @NeedQty10014 DECIMAL; --总需求量
                DECLARE @Qty10014 DECIMAL; --标签的数量
                DECLARE @TotalQty10014 DECIMAL; --总备料量
                DECLARE @lot10014 VARCHAR(50); --标签的批次
                --判断标签不在电子仓内且不在异常库位
                SELECT TOP 1
                       @xxbad_part = partnum,
                       @Qty10014 = qty,
                       @lot = lot
                FROM dbo.barocde_materiallable
                WHERE usn = @ScanData
                      AND status IN ( 4, 5 )
                      AND LEFT(currentloc, 2) <> 'NG';

                IF ISNULL(@Qty10014, 0) = 0
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不存在!#Tag does not exist!', 11, 1);

                END;

                --判断标签零件是否和备料单匹配 顺便取出需求量
                SELECT TOP 1
                       @NeedQty10014 = NeedQty
                FROM dbo.BarocodeFeedLine
                WHERE AllotNum = @xxbad_extension2
                      AND PartNum = @xxbad_part
                      AND TvNum = 1;
                IF (ISNULL(@NeedQty10014, 0) = 0)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#零件和备料单不匹配!#Parts and material list do not match!', 11, 1);

                END;
                --判断标签批次是否满足先进先出规则 顺便取出零件号和标签数量
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.barocde_materiallable
                    WHERE lot < @lot
                          AND partnum = @xxbad_part
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请扫码更早批次的标签!#Please scan the label from an earlier batch!', 11, 1);

                END;


                --如果备料明细表中已经存在 则解除备料 如果不存在则插入
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_AllotDetail
                    WHERE USN = @ScanData
                          AND AllotNum = @xxbad_extension2
                )
                BEGIN
                    --解除备料明细
                    DELETE FROM Barcode_AllotDetail
                    WHERE USN = @ScanData
                          AND AllotNum = @xxbad_extension2;
                    --还原标签的状态 
                    UPDATE dbo.barocde_materiallable
                    SET status = 4
                    WHERE usn = @ScanData;
                END;
                ELSE
                BEGIN
                    --获取当前零件 已经备料总量
                    SELECT @TotalQty = ISNULL(SUM(Qty), 0),
                           @Box = SUM(1)
                    FROM dbo.Barcode_AllotDetail
                    WHERE AllotNum = @xxbad_extension2
                          AND PartNum = @xxbad_part;
                    --判断当前备料单 当前零件是否超量备料
                    IF @TotalQty + @Qty10014 > @NeedQty10014
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#当前零件已经超量，请换其他零件!#The current part is overstocked, please use another part!', 11, 1);

                    END;
                    --插入备料明细表
                    INSERT INTO Barcode_AllotDetail
                    SELECT @xxbad_extension2,
                           partnum,
                           usn,
                           qty,
                           currentloc,
                           (
                               SELECT TOP 1
                                      ToLoc
                               FROM dbo.BarocodeFeedLine
                               WHERE AllotNum = @xxbad_extension2
                           ),
                           lot,
                           site,
                           0
                    FROM dbo.barocde_materiallable
                    WHERE USN = @ScanData;

                    --更新标签的状态 表示已经备料 库位在提交的时候发生改变
                    UPDATE dbo.barocde_materiallable
                    SET status = 5
                    WHERE usn = @ScanData;
                END;
                --更新备料主表 备料人 备料开始时间 状态 已备料量
                UPDATE BarocodeFeedLine
                SET AllotUser = @xxbad_user,
                    AllotStartTime = GETDATE(),
                    Status = 1,
                    OkQty = @TotalQty + @Qty10014
                WHERE AllotNum = @xxbad_extension2
                      AND PartNum = @xxbad_part;

                --返回第一个dataset数据给前台
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_AllotDetail
                    WHERE AllotNum = @xxbad_extension2
                )
                BEGIN
                    SELECT SUM(1) xxbad_qty,
                           SUM(Qty) xxbad_extension1,
                           MAX(ToLoc) xxbad_toloc,
                           @NeedQty10014 xxbad_rj_qty,
                           MAX(Site) xxbad_site,
                           MAX(ScanTime) ScanTime,
                           @xxbad_part xxbad_part
                    FROM Barcode_AllotDetail
                    WHERE AllotNum = @xxbad_extension2
                    ORDER BY ScanTime;
                END;
                ELSE
                BEGIN
                    SELECT '' xxbad_qty,
                           '' xxbad_extension1;
                END;
                --返回第二个dateset 到前台 未备料明细
                SELECT DISTINCT
                       a.PartNum,
                       a.NeedQty,
                       a.OkQty,
                       b.currentloc,
                       b.lot
                FROM dbo.BarocodeFeedLine a
                    LEFT JOIN dbo.barocde_materiallable b
                        ON b.status = 4
                           AND b.partnum = a.PartNum
                WHERE a.AllotNum = @xxbad_extension2
                      AND a.Status < 2
                      AND a.TvNum = 1;
            END;
        END;
        IF @interfaceid IN ( 10016 ) --金属件备料标签收货
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断备料单是否已经结束

                --判断所有标签 是否被扫描
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_AllotDetail
                    WHERE AllotNum = @xxbad_extension2
                          AND Stauts = 1
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#还有标签未收货，如果需要差异收货，请到PC上面操作!#There are still tags not received. If you need to process discrepancy receipts, please operate on the PC!', 11, 1);

                END;
                --如果全部被收货 则更新主表信息，状态 收货人，收货时间
                UPDATE dbo.BarocodeFeedLine
                SET Status = 4,
                    ReceiptQty = OkQty,
                    ReceiptUser = @xxbad_user,
                    ReceiptEndTime = GETDATE()
                WHERE AllotNum = @xxbad_extension2
                      AND Status = 3;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg]
                )
                SELECT @xxbad_domain,
                       'IC_TR',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       dbo.GetQADloc(Loc),
                       dbo.GetQADloc(MAX(ToLoc)),
                       Lot,
                       Lot,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       SUM(1),
                       SUM(Qty)
                FROM dbo.Barcode_AllotDetail
                WHERE AllotNum = @xxbad_extension2
                      AND Stauts = 2
                GROUP BY AllotNum,
                         PartNum,
                         Lot,
                         Loc;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       USN,
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       Loc,
                       ToLoc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       AllotNum,
                       @xxbad_id,
                       Qty,
                       Lot,
                       Lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM dbo.Barcode_AllotDetail
                WHERE AllotNum = @xxbad_extension2
                      AND Stauts = 2;

                RAISERROR(N'Info_MESSAGE#提交成功!#Submission successful!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                --汇总返回第一个dataset
                SELECT MAX(PartNum) xxbad_part,
                       MAX(Line) xxbad_proline,
                       MAX(ToLoc) xxbad_toloc,
                       SUM(OkQty) xxbad_scrapqty,
                       SUM(NeedQty) xxbad_qty
                FROM dbo.BarocodeFeedLine
                WHERE AllotNum = @xxbad_extension2
                      AND Status IN ( 2, 3 );
                --返回第二个dataset 到前台		
                SELECT PartNum,
                       USN,
                       Qty
                FROM dbo.Barcode_AllotDetail
                WHERE AllotNum = @xxbad_extension2
                      AND Stauts = 1;
            END;
            ELSE IF @ScanData = 'ComboBox'
            BEGIN
                --汇总返回第一个dataset
                SELECT MAX(PartNum) xxbad_part,
                       MAX(Line) xxbad_proline,
                       MAX(ToLoc) xxbad_toloc,
                       SUM(OkQty) xxbad_scrapqty,
                       SUM(NeedQty) xxbad_qty
                FROM dbo.BarocodeFeedLine
                WHERE AllotNum = @xxbad_extension2
                      AND Status = 2;
                --返回第二个dataset 到前台		
                SELECT PartNum,
                       USN,
                       Qty
                FROM dbo.Barcode_AllotDetail
                WHERE AllotNum = @xxbad_extension2
                      AND Stauts = 1;
            END;
            ELSE --认为处理条码 数据
            BEGIN
                SELECT TOP 1
                       @PartNum = PartNum
                FROM dbo.Barcode_AllotDetail
                WHERE AllotNum = @xxbad_extension2
                      AND Stauts = 1
                      AND USN = @ScanData;
                --判断标签是否在备料明细中
                IF ISNULL(@PartNum, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不在当前备料单中!#The label is not in the current material list!', 11, 1);

                END;
                --如果全部被收货 则更新主表信息，状态 收货人，收货时间
                UPDATE dbo.BarocodeFeedLine
                SET Status = 3,
                    ReceiptStartTime = GETDATE()
                WHERE AllotNum = @xxbad_extension2
                      AND PartNum = @PartNum
                      AND Status = 2;
                --如果在备料明细中 更新明细表的状态,标识标签已收货
                UPDATE Barcode_AllotDetail
                SET Stauts = 2
                WHERE AllotNum = @xxbad_extension2
                      AND Stauts = 1
                      AND USN = @ScanData;
                --更改标签的库位，状态
                UPDATE dbo.barocde_materiallable
                SET currentloc = @xxbad_toloc,
                    status = 6
                WHERE usn = @ScanData;
                --返回第一个dataset 到前台 不清空主表
                SELECT @PartNum xxbad_part,
                       @xxbad_proline xxbad_proline,
                       @xxbad_toloc xxbad_toloc,
                       @xxbad_scrapqty xxbad_scrapqty,
                       @xxbad_qty xxbad_qty;

                --返回第二个dataset 到前台 未扫描的标签列表
                SELECT PartNum,
                       USN,
                       Qty
                FROM dbo.Barcode_AllotDetail
                WHERE AllotNum = @xxbad_extension2
                      AND Stauts = 1;
            END;
        END;
        IF @interfaceid IN ( 10018 ) --清洗线器具码移库
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断是否移库量大于备料量
                IF ISNULL(@xxbad_scrapqty, 0) < ISNULL(@xxbad_qty, 0)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#转移量不能大于需求量!#The transfer amount cannot exceed the demand!', 11, 1);

                END;
                --更改2号看板的备料收货信息，收货人，时间，数量，状态 直接关闭对应备料单号和零件号
                UPDATE BarocodeFeedLine
                SET Status = 4,
                    OkQty = @xxbad_qty,
                    ReceiptUser = @xxbad_user,
                    ReceiptStartTime = GETDATE(),
                    ReceiptEndTime = GETDATE(),
                    ReceiptQty = @xxbad_qty
                WHERE AllotNum = @xxbad_extension2
                      AND PartNum = @xxbad_part;
                RAISERROR(N'Info_MESSAGE#提交成功!#Submission successful!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 1;
                SELECT 1;
            END;
            ELSE IF @ScanData = 'ComboBox'
            BEGIN
                SELECT 1;
                SELECT 1;

            END;
            ELSE --认为处理扫描器具码 数据
            BEGIN
                --取出扫描的器具码信息
                SELECT @xxbad_part = PartNum,
                       @xxbad_qty = NeedQty,
                       @xxbad_proline = Line
                FROM UtensilCode
                WHERE Code = @ScanData;
                --判断器具码是否合法
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    RAISERROR(N'Info_MESSAGE#器具码不存在!#The equipment code does not exist!', 11, 1);

                END;
                --从备料表取出需求量
                SELECT TOP 1
                       @xxbad_scrapqty = NeedQty
                FROM dbo.BarocodeFeedLine
                WHERE AllotNum = @xxbad_extension2
                      AND PartNum = @xxbad_part;

                --判断器具码和备料单是否匹配
                IF (ISNULL(@xxbad_scrapqty, 0) = 0)
                BEGIN
                    RAISERROR(N'Info_MESSAGE#器具码和备料单不匹配!#The equipment code does not match the material preparation list!', 11, 1);

                END;
                --返回第一个dataset 到前台
                SELECT @ScanData xxbad_extension3,
                       'xxbad_qty' READONLY,
                       @xxbad_part xxbad_part,
                       @xxbad_scrapqty xxbad_scrapqty,
                       @xxbad_qty xxbad_qty,
                       @xxbad_proline xxbad_proline;
            END;
        END;
        IF @interfaceid IN ( 10022 ) --额外补料
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断是否超量叫料
                IF ISNULL(@xxbad_rj_qty, 0) < ISNULL(@xxbad_qty, 0)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#叫料量不能大于最大存放量!#The requested material quantity cannot exceed the maximum storage capacity!', 11, 1);

                END;
                --根据获得的产线 查找回冲库位
                SELECT TOP 1
                       @xxbad_toloc = Loc
                FROM dbo.ProdLine
                WHERE LineCode = @xxbad_proline;

                --生成备料单号临时表
                CREATE TABLE #SeqenceNumber10022
                (
                    ft VARCHAR(20),
                    Line VARCHAR(50)
                );
                --生成一个新的备料单号
                INSERT INTO #SeqenceNumber10022
                EXEC [MakeSeqenceNum] '00000006', @xxbad_proline;
                --插入一个新的1号看板备料信息
                INSERT INTO [dbo].[BarocodeFeedLine]
                (
                    [AllotNum],
                    Line,
                    [PartNum],
                    PartType,
                    [NeedQty],
                    AllotBox,
                    [ToLoc],
                    [CallTime],
                    [CallPerson],
                    [Site],
                    [Status],
                    [Useble],
                    [UrgencyLevel],
                    TvNum,
                    SouceAllotNum
                )
                SELECT ft,
                       @xxbad_proline,
                       @xxbad_part,
                       1,
                       @xxbad_qty,
                       1, --ROUND(@xxbad_qty / SDPkgQty, 0),
                       @xxbad_toloc,
                       GETDATE(),
                       @xxbad_user,
                       @xxbad_site,
                       0,
                       1,
                       1,
                       CASE @xxbad_type
                           WHEN '1' THEN
                               2
                           WHEN '2' THEN
                               3
                       END,
                       @xxbad_extension2
                FROM #SeqenceNumber10022;

                RAISERROR(N'Info_MESSAGE#提交成功!#Submission successful!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 1;
                SELECT 1;
            END;
            ELSE IF @ScanData = 'ComboBox'
            BEGIN
                SELECT 1;
                SELECT 1;

            END;
            ELSE --认为扫描的是零件号
            BEGIN
                --从零件表取出零件号 零件描述
                SELECT @xxbad_part = pt_part,
                       @xxbad_desc = pt_desc1
                FROM pt_mstr
                WHERE pt_part = @ScanData;
                --判断零件号是否合法
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    RAISERROR(N'Info_MESSAGE#零件号不存在!#Part number does not exist!', 11, 1);

                END;

                --返回第一个dataset 到前台 取出最大零件容量 作为参考
                SELECT TOP 1
                       @xxbad_desc xxbad_desc,
                       'xxbad_qty' READONLY,
                       @xxbad_part xxbad_part,
                       PartType xxbad_type,
                       MaxSaftyQty xxbad_rj_qty
                FROM dbo.PartMovingSet
                WHERE pt_site = @xxbad_site
                      AND ProdLine = @xxbad_proline
                      AND pt_part = @xxbad_part;
            END;
        END;

        IF @interfaceid IN ( 10028 ) --半成品回冲 中用不使用 
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --根据获得的产线 查找回冲库位
                IF ISNULL(@xxbad_loc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#下线库位不能为空!#The offline storage location cannot be empty!', 11, 1);

                END;
                --取出当前零件的BOM到临时表
                SELECT *
                INTO #ps_mstr10028
                FROM dbo.ps_mstr;
                -- WHERE ps_par = @xxbad_part;
                --判断BOM是否存在
                IF NOT EXISTS (SELECT TOP 1 1 FROM #ps_mstr10028)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#总成BOM缺失，无法下线!#Assembly BOM missing, unable to proceed with production!', 11, 1);

                END;
                --判断是否重复下线
                IF EXISTS (SELECT TOP 1 1 FROM Barocde_FGlLable WHERE USN = @xxbad_id)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#成品不能重复下线!#Finished products cannot be taken offline repeatedly!', 11, 1);

                END;
                --将标签信息插入成品标签表
                INSERT Barocde_FGlLable
                (
                    USN,
                    PartNum,
                    PartDescription,
                    Lot,
                    CurrentLoc,
                    Qty,
                    Site,
                    Status,
                    CreateTime,
                    ProLine,
                    FlushStatus,
                    BackwashUser,
                    WorkOp,
                    Type
                )
                SELECT TOP 1
                       @xxbad_id,
                       @xxbad_part,
                       pt_desc1,
                       @xxbad_lot,
                       @xxbad_loc,
                       1,
                       @xxbad_tosite,
                       0,
                       GETDATE(),
                       @xxbad_proline,
                       0,
                       @xxbad_user,
                       @xxbad_routing,
                       0
                FROM dbo.pt_mstr
                WHERE pt_part = @xxbad_part;
                --插入QAD回冲队列
                --逻辑放到BackFlushFGLbale 定时上传回冲
                --BOM回冲
                --逻辑放到BackFlushFGLbale 定时扣减原材料
                --标签插入子队列 用于增加成品库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'PQ_WO_BKFL',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       USN,
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       CurrentLoc,
                       CurrentLoc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       @xxbad_id,
                       Qty,
                       ISNULL(Lot, ''),
                       Lot,
                       @xxbad_ref,
                       ''
                FROM dbo.Barocde_FGlLable
                WHERE USN = @xxbad_id;
                RAISERROR(N'Info_MESSAGE#下线成功!#Logout successful!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 1;
                SELECT 1;
            END;
            ELSE IF @ScanData = 'ComboBox'
            BEGIN
                SELECT 1;
                SELECT 1;
            END;
            ELSE --认为扫描的是成品条码
            BEGIN
                SET @xxbad_id = @ScanData;
                --标签长度是否是 20 并且全是数字
                IF (20 <> LEN(@xxbad_id) OR PATINDEX('%[^0-9]%', @xxbad_id) = 1)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#条码格式错误!#Barcode format error!', 11, 1);

                END;
                --然后拆解成品标签到不同的 变量里面
                SELECT @PartNum = LEFT(@xxbad_id, 8),
                       @xxbad_qty = 1;


                IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.pt_mstr WHERE pt_part = @PartNum)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#条码解析失败，对应的零件号不存在!#Barcode parsing failed, corresponding part number does not exist!', 11, 1);

                END;

                --返回第一个dataset 到前台 95130001 EC28BBE010P1
                SELECT TOP 1
                       @xxbad_id xxbad_id,
                       pt_part_type xxbad_ltype,
                       pt_site xxbad_site,
                       pt_part xxbad_part,
                       (
                           SELECT TOP 1 Loc FROM dbo.ProdLine WHERE LineCode = @xxbad_proline
                       ) xxbad_loc,
                       CONVERT(VARCHAR(50), GETDATE(), 112) xxbad_lot,
                       '100' xxbad_routing
                FROM dbo.pt_mstr
                WHERE pt_part = @PartNum;
            END;
        END;

        IF @interfaceid IN ( 10034 ) --成品单箱上架
        BEGIN

            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --将到库位转化成库区
                DECLARE @locarea10034 VARCHAR(50);
                SELECT TOP 1
                       @locarea10034 = LocArea
                FROM dbo.Barcode_Location
                WHERE xxlocation_loc = @xxbad_toloc;
                IF ISNULL(@locarea10034, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前到库位库区不存在!#The current storage location does not exist!', 11, 1);

                END;
                --将从库位转化成QAD库位
                DECLARE @QADfrom10034 VARCHAR(50);
                SELECT TOP 1
                       @QADfrom10034 = LocArea
                FROM dbo.Barcode_Location
                WHERE xxlocation_loc = @xxbad_fromloc;
                --判断 到库位 是否在零件的配置的库区内
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_Location
                    WHERE LocArea IN
                          (
                              SELECT LocArea
                              FROM Barcode_ItemLocArea
                              WHERE ItemNum = @xxbad_part
                                    AND tenant_id = @xxbad_site
                          )
                          AND xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前零件不能上架到此库区!#The current part cannot be placed in this storage area!', 11, 1);

                END;
                IF (ISNULL(@xxbad_fromloc, '') = ISNULL(@xxbad_toloc, ''))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前成品已经在到库位下面了!#The current finished product is already under the storage location!', 11, 1);

                END;
                --判断从库位的业务限制逻辑
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_LocStatusCode
                    WHERE IsAvailble = 1
                          AND ISS_TR = 1
                          AND StatusCode =
                          (
                              SELECT TOP 1 StatusCode FROM Barcode_LocArea WHERE Name = @QADfrom10034
                          )
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前从库位限制移除!#Current location restriction removed!', 11, 1);

                END;
                --判断到库位的业务限制逻辑
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_LocStatusCode
                    WHERE IsAvailble = 1
                          AND RCT_TR = 1
                          AND StatusCode =
                          (
                              SELECT TOP 1 StatusCode FROM Barcode_LocArea WHERE Name = @locarea10034
                          )
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前到库位限制移入!#Current location limit reached for moving in!', 11, 1);

                END;
                --更新标签表的库位和上架时间批次
                UPDATE Barocde_BoxlLable
                SET FromLoc = CurrentLoc,
                    CurrentLoc = @xxbad_toloc,
                    Status = 3,
                    InboundUser = @xxbad_user,
                    InboundTime = GETDATE()
                WHERE USN = @xxbad_id;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotto
                )
                SELECT @xxbad_domain,
                       'IC_TR',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       PartNum,
                       @QADfrom10034,
                       @locarea10034,
                       Site,
                       Site,
                       '',
                       USN,
                       Qty,
                       Lot
                FROM Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       a.USN,
                       @xxbad_user,
                       '',
                       '',
                       a.PartNum,
                       @xxbad_fromloc,
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       a.Qty,
                       b.Lot,
                       a.Lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM Barocde_BoxlLable a
                    INNER JOIN dbo.Barocde_FGlLable b
                        ON b.InBoundBox = a.USN
                WHERE a.USN = @xxbad_id;
                RAISERROR(N'Info_MESSAGE#上架完成!#Listing completed!', 11, 1);
            END;

            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 1;
            END;
            ELSE
            BEGIN
                --从标签中加载信息  并且判断标签状态
                SELECT @xxbad_ship_id = ShipSN,
                       @xxbad_id = USN,
                       @xxbad_part = PartNum,
                       @xxbad_desc = PartDescription,
                       @xxbad_qty = Qty,
                       @xxbad_status = Status,
                       @xxbad_lot = Lot,
                       @xxbad_woid = WoNum,
                       @InspectUser = InspectUser,
                       @InspectType = InspectType,
                       @InspectResult = InspectResult,
                       @xxbad_fromloc = CurrentLoc
                FROM Barocde_BoxlLable
                WHERE USN = @ScanData;

                IF (ISNULL(@xxbad_id, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不正确!#Invalid tag!', 11, 1);

                END;
                IF (ISNULL(@xxbad_status, '') <> '2')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签没有打包，请先打包!#Labels are not packaged, please package them first!', 11, 1);

                END;
                --返回第一个dataset到前台
                SELECT @xxbad_ship_id xxbad_ship_id,
                       @xxbad_id xxbad_id,
                       @xxbad_part xxbad_part,
                       @xxbad_desc xxbad_desc,
                       @xxbad_woid xxbad_woid,
                       @xxbad_lot xxbad_lot,
                       @xxbad_qty xxbad_qty,
                       pt_loc xxbad_toloc,
                       @xxbad_fromloc xxbad_fromloc,
                       'xxbad_toloc' READONLY
                FROM pt_mstr
                WHERE pt_part = @xxbad_part
                      AND pt_domain = @xxbad_domain
                      AND pt_site = @xxbad_site;
            END;
        END;
        IF @interfaceid IN ( 10064 ) --成品箱标签解绑
        BEGIN

            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN

                ----插入条码主队列
                --INSERT INTO [dbo].[xxinbxml_mstr]
                --(   [xxinbxml_domain],
                --    [xxinbxml_appid],
                --    BarcodeInterFaceID,
                --    [xxinbxml_status],
                --    [xxinbxml_crtdate],
                --    [xxinbxml_cimdate],
                --    [xxinbxml_type],
                --    [xxinbxml_extusr],
                --    [xxinbxml_part],
                --    [xxinbxml_locfrm],
                --    [xxinbxml_locto],
                --    [xxinbxml_sitefrm],
                --    [xxinbxml_siteto],
                --    [xxinbxml_pallet],
                --    [xxinbxml_box],
                --    [xxinbxml_qty_chg],
                --    xxinbxml_lotto
                --)
                --SELECT @xxbad_domain,
                --    'IC_TR',
                --    @interfaceid,
                --    0,
                --    GETDATE(),
                --    GETDATE(),
                --    'CIM',
                --    @xxbad_user,
                --    PartNum,
                --    @QADfrom10034,
                --    @locarea10034,
                --    Site,
                --    Site,
                --    '',
                --    USN,
                --    Qty,
                --    Lot
                --FROM Barocde_BoxlLable
                --WHERE USN = @xxbad_id;
                --标签插入子队列 用于记录日志，但是不参与库存核算
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT 10064,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       USN,
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       @xxbad_fromloc,
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       InBoundBox,
                       @xxbad_id,
                       Qty,
                       @xxbad_lot,
                       Lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM Barocde_FGlLable
                WHERE InBoundBox = @xxbad_id;
                --更新标签表的库位和状态 
                UPDATE Barocde_BoxlLable
                SET Status = 7,
                    DestroyTime = GETDATE(),
                    DestroyUser = @xxbad_user,
                    DestroyMemo = '成品箱标签解绑'
                WHERE USN = @xxbad_id;
                --记录日志 将Barocde_FGlLable  备份

                --更新箱标签中成品小标签的状态和库位突变批次号
                UPDATE dbo.Barocde_FGlLable
                SET CurrentLoc = @xxbad_fromloc,
                    Status = 1,
                    Lot = @xxbad_lot,
                    InBoundBox = NULL,
                    ExtendFiled3 = '成品箱标签解绑' + @xxbad_id
                WHERE InBoundBox = @xxbad_id;
                RAISERROR(N'Info_MESSAGE#解绑完成!#Unbinding completed!', 11, 1);
            END;

            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 1;
            END;
            ELSE
            BEGIN
                --从标签中加载信息  并且判断标签状态
                SELECT @xxbad_ship_id = ShipSN,
                       @xxbad_id = USN,
                       @xxbad_part = PartNum,
                       @xxbad_desc = PartDescription,
                       @xxbad_qty = Qty,
                       @xxbad_status = Status,
                       @xxbad_lot = Lot,
                       @xxbad_supplier = CustomName,
                       @xxbad_woid = WoNum,
                       @InspectUser = InspectUser,
                       @InspectType = InspectType,
                       @InspectResult = InspectResult,
                       @xxbad_fromloc = CurrentLoc
                FROM Barocde_BoxlLable
                WHERE USN = @ScanData;

                IF (ISNULL(@xxbad_id, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不正确!#Invalid tag!', 11, 1);

                END;
                --判断有没有打包
                IF (ISNULL(@xxbad_status, '0') < 2)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签没有打包，请先打包!#Labels are not packaged, please package them first!', 11, 1);

                END;
                --判断是否已经注销
                IF (ISNULL(@xxbad_status, '0') = 7)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签已经解绑注销，不能再次解绑!#The tag has already been unbound and deactivated, it cannot be unbound again!', 11, 1);

                END;

                --判断是否已经销售发运
                IF (ISNULL(@xxbad_status, '0') > 3)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签已经销售发运，不能解绑!#The tag has already been sold and shipped, it cannot be unbound!', 11, 1);

                END;
                --判断有没有上架
                IF (ISNULL(@xxbad_status, '0') = 2)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请先上架，然后在解绑!#Please list it first, then unbind!', 11, 1);

                END;
                --判断当前 标签是否在线边库位@
                IF (ISNULL(@xxbad_fromloc, '') <> 'Line2')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前标签线边库，请先移库到线边库!#The current label is in the line-side warehouse. Please move it to the line-side warehouse first!', 11, 1);

                END;
                --返回第一个dataset到前台
                SELECT @xxbad_ship_id xxbad_ship_id,
                       @xxbad_id xxbad_id,
                       @xxbad_part xxbad_part,
                       @xxbad_desc xxbad_desc,
                       @xxbad_woid xxbad_woid,
                       @xxbad_lot xxbad_lot,
                       @xxbad_qty xxbad_qty,
                       @xxbad_fromloc xxbad_toloc,
                       @xxbad_fromloc xxbad_fromloc
                FROM pt_mstr
                WHERE pt_part = @xxbad_part
                      AND pt_domain = @xxbad_domain
                      AND pt_site = @xxbad_site;
            END;
        END;
        IF @interfaceid IN ( 10036, 10092 ) --成品和半成品批量上架
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断是否是空提交  没有缓存
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#没有缓存扫描任何标签!#No cached scan of any tags!', 11, 1);

                END;
                --到库位是废弃品库  的特殊逻辑FQPK
                IF @xxbad_toloc = 'fqpk'
                BEGIN

                    IF EXISTS
                    (
                        SELECT TOP 1
                               1
                        FROM Barocde_BoxlLable
                        WHERE USN IN
                              (
                                  SELECT LableID
                                  FROM Barcode_OperateCache
                                  WHERE AppID = @interfaceid
                                        AND OpUser = @xxbad_user
                              )
                              AND InspectResult = '1'
                    )
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#合格品不能移动到废弃品库!#Qualified products cannot be moved to the scrap warehouse!', 11, 1);
                    END;

                END;
                --判断线边是否足够的库存上架
                --将线边库存 汇总存入临时表
                SELECT *
                INTO #Barocde_Stock10036
                FROM dbo.barocde_stock
                WHERE loc IN
                      (
                          SELECT LineCode FROM dbo.ProdLine
                      );
                --将缓存中的标签生成库存
                SELECT FromSite,
                       CurrentLoc,
                       PartNum,
                       ToLot,
                       SUM(Qty) Qty
                INTO #Barcode_OperateCache10036
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                GROUP BY FromSite,
                         CurrentLoc,
                         PartNum,
                         ToLot;
                SET @xxbad_extension5 = '';
                SELECT TOP 1
                       @xxbad_extension5 = a.partnum
                FROM #Barocde_Stock10036 a
                    INNER JOIN #Barcode_OperateCache10036 b
                        ON a.site = b.FromSite
                           AND a.loc = b.CurrentLoc
                           AND b.PartNum = a.partnum
                           AND a.lot = b.ToLot
                           AND (b.Qty <= ISNULL(a.qty, 0));

                IF ISNULL(@xxbad_extension5, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#没有足够的线边库存做此业务!#Insufficient line-side inventory to perform this operation!', 11, 1);

                END;
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_Location
                    WHERE xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#到库位不合法!#Invalid destination location!', 11, 1);
                END;
                --更新标签表的库位和上架时间批次
                UPDATE b
                SET b.FromLoc = b.CurrentLoc,
                    b.CurrentLoc = @xxbad_toloc,
                    b.Status = 3,
                    b.Lot = a.ToLot,
                    InboundUser = @xxbad_user,
                    InboundTime = GETDATE()
                FROM Barcode_OperateCache a,
                     Barocde_BoxlLable b
                WHERE a.LableID = b.USN
                      AND a.AppID = @interfaceid
                      AND a.OpUser = @xxbad_user;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    BarcodeInterFaceID,
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @xxbad_domain,
                       @interfaceid,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       dbo.GetQADloc(MAX(CurrentLoc)),
                       dbo.GetQADloc(@xxbad_toloc),
                       @xxbad_fromsite,
                       @xxbad_fromsite,
                       MAX(ExtendedField1),
                       @xxbad_id,
                       SUM(Qty),
                       ToLot,
                       ToLot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                GROUP BY CurrentLoc,
                         PartNum,
                         ToLot;


                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       b.LableID,
                       @xxbad_user,
                       '',
                       '',
                       b.PartNum,
                       b.FromLoc,
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       b.ExtendedField1,
                       b.ExtendedField1,
                       b.Qty,
                       b.ToLot,
                       b.ToLot,
                       @xxbad_fromref,
                       @xxbad_toref
                FROM Barcode_OperateCache b
                WHERE b.AppID = @interfaceid
                      AND b.OpUser = @xxbad_user;

                --清除缓存表
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                RAISERROR(N'Info_MESSAGE#上架完成!#Listing completed!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    SELECT 'xxbad_toloc' focus;
                END;
                SELECT TOP 1
                       ToLoc xxbad_toloc,
                       PartNum xxbad_part,
                       ToLot xxbad_lot,
                       'xxbad_toloc' focus,
                       FromSite xxbad_site,
                       ExtendedField1 xxbad_ship_id,
                       (
                           SELECT SUM(Qty)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_extension1,
                       (
                           SELECT COUNT(1)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_extension2
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                --返回第二个dataset
                SELECT *
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
            END;
            ELSE IF @ScanData = 'xxbad_toloc'
            BEGIN
                --判断库位是否存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_Location
                    WHERE xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#库位不存在!#Location does not exist!', 11, 1);

                END;
                --返回第一个dateset 到前台
                SELECT @xxbad_toloc xxbad_toloc,
                       'xxbad_id' focus;
            END;
            ELSE
            BEGIN
                --处理扫描的条码
                DECLARE @CustomNum NVARCHAR(50);
                --从标签中加载信息  并且判断标签状态
                SELECT @xxbad_ship_id = ShipSN,
                       @xxbad_id = USN,
                       @xxbad_part = PartNum,
                       @xxbad_desc = PartDescription,
                       @xxbad_qty = Qty,
                       @xxbad_lot = Lot,
                       @xxbad_status = Status,
                       @CustomNum = CustomNum,
                       @InspectUser = InspectUser,
                       @InspectResult = InspectResult,
                       @xxbad_fromloc = CurrentLoc
                FROM Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                IF (ISNULL(@xxbad_desc, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签或标签状态不正确!#Incorrect tag or tag status!', 11, 1);
                END;
                IF (ISNULL(@xxbad_status, '') = '0')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签未打印不能上架!#Labels not printed, cannot be shelved!', 11, 1);
                END;
                IF (ISNULL(@xxbad_status, '') = '1')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签未执行完工下线，请先下线!#The tag has not completed the offline process, please go offline first!', 11, 1);
                END;
                IF (ISNULL(@xxbad_status, '') > '2')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签已经上架，不能重复上架!#The tag has already been listed and cannot be listed again!', 11, 1);
                END;
                --判断 到库位 是否在零件的配置的库区内
                --IF NOT EXISTS
                --(
                --    SELECT TOP 1
                --           1
                --    FROM Barcode_Location
                --    WHERE LocArea IN
                --          (
                --              SELECT LocArea FROM Barcode_ItemLocArea WHERE ItemNum = @xxbad_part
                --          --AND xxlocation_site = @xxbad_site
                --          )
                --          AND xxlocation_loc = @xxbad_toloc
                --)
                --BEGIN
                --    RAISERROR(N'ERROR_MESSAGE#当前成品不能上架到此库区!#The current product cannot be placed in this storage area!', 11, 1);
                --    
                --END;
                IF ISNULL(@xxbad_toloc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#到库位不能为空!#The destination location cannot be empty!', 11, 1);

                END;
                IF (ISNULL(@xxbad_fromloc, '') = ISNULL(@xxbad_toloc, ''))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前成品已经在到库位下面了!#The current finished product is already under the storage location!', 11, 1);

                END;
                --判断当前原材料是否被被人缓存了
                SELECT TOP 1
                       @cacheuser = OpUser
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND LableID = @xxbad_id;
                IF (ISNULL(@cacheuser, @xxbad_user) <> @xxbad_user)
                BEGIN
                    SET @ErrorMessage
                        = N'ERROR_MESSAGE#该箱码被用户' + @cacheuser + N'扫描，请提醒其操作!#The box code has been scanned by user ' + @cacheuser + N'. Please remind them to take action!';
                    RAISERROR(@ErrorMessage, 11, 1);

                END;
                --如果在动态高速缓存表不存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                          AND LableID = @xxbad_id
                )
                BEGIN
                    --从标签中获取标签信息 插入动态高速缓存表
                    INSERT INTO [dbo].[Barcode_OperateCache]
                    (
                        id,
                        [AppID],
                        [OpUser],
                        [LableID],
                        [PartNum],
                        [PartDescrition],
                        [Qty],
                        ToLot,
                        [FromLoc],
                        [CurrentLoc],
                        [ToLoc],
                        [FromSite],
                        [ToSite],
                        [ScanTime],
                        ExtendedField1
                    )
                    SELECT TOP 1
                           NEWID(),
                           @interfaceid,
                           @xxbad_user,
                           @xxbad_id,
                           PartNum,
                           PartDescription,
                           Qty,
                           Lot,
                           CurrentLoc,
                           CurrentLoc,
                           @xxbad_toloc,
                           @xxbad_site,
                           @xxbad_site,
                           GETDATE(),
                           WoNum
                    FROM dbo.Barocde_BoxlLable
                    WHERE USN = @xxbad_id;
                END;
                ELSE
                BEGIN
                    --DELETE [Barcode_OperateCache]
                    --WHERE AppID = @interfaceid
                    --      AND OpUser = @xxbad_user
                    --      AND LableID = @xxbad_id;
                    RAISERROR(N'ERROR_MESSAGE#不能重复扫描当前标签!#Cannot scan the current label again!', 11, 1);
                END;
                --到库位是废弃品库  的特殊逻辑FQPK
                IF @xxbad_toloc = 'fqpk'
                BEGIN

                    IF @InspectResult = '1'
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#合格品不能移动到废弃品库!#Qualified products cannot be moved to the scrap warehouse!', 11, 1);
                    END;
                    ELSE
                    BEGIN
                        SET @xxbad_rmks = '此操作不可逆，请确认是否确定要移库到废弃品库';
                    END;
                END;
                --返回第一个dataset到前台
                SELECT TOP 1
                       ToLoc xxbad_toloc,
                       PartNum xxbad_part,
                       FromSite xxbad_site,
                       '' xxbad_id,
                       ToLot xxbad_lot,
                       @xxbad_rmks xxbad_rmks,
                       ExtendedField1 xxbad_ship_id,
                       (
                           SELECT SUM(Qty)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_extension1,
                       (
                           SELECT COUNT(1)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_extension2
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;

                --返回第二个dataset到前台
                SELECT LableID,
                       PartNum,
                       PartDescrition
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
            END;
        END;

        IF @interfaceid IN ( 10112 ) --成品箱码批量移库
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断是否是空提交  没有缓存
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#没有缓存扫描任何标签!#No cached scan of any tags!', 11, 1);

                END;

                IF ISNULL(@xxbad_toloc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#到库位不能为空!#The destination location cannot be empty!', 11, 1);
                END;
                --更新标签表的库位和上架时间批次
                UPDATE b
                SET b.FromLoc = b.CurrentLoc,
                    b.CurrentLoc = a.ToLoc,
                    b.Lot = a.ToLot,
                    InboundUser = @xxbad_user,
                    InboundTime = GETDATE()
                FROM Barcode_OperateCache a,
                     Barocde_BoxlLable b
                WHERE a.LableID = b.USN
                      AND a.AppID = @interfaceid
                      AND a.OpUser = @xxbad_user;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    BarcodeInterFaceID,
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @xxbad_domain,
                       @interfaceid,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       dbo.GetQADloc(CurrentLoc),
                       dbo.GetQADloc(@xxbad_toloc),
                       @xxbad_fromsite,
                       @xxbad_fromsite,
                       MAX(ExtendedField1),
                       @xxbad_id,
                       SUM(Qty),
                       ToLot,
                       ToLot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                GROUP BY CurrentLoc,
                         PartNum,
                         ToLot;


                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       b.LableID,
                       @xxbad_user,
                       '',
                       '',
                       b.PartNum,
                       b.FromLoc,
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       b.ExtendedField1,
                       b.ExtendedField1,
                       b.Qty,
                       b.ToLot,
                       b.ToLot,
                       @xxbad_fromref,
                       @xxbad_toref
                FROM Barcode_OperateCache b
                WHERE b.AppID = @interfaceid
                      AND b.OpUser = @xxbad_user;

                --清除缓存表
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                RAISERROR(N'Info_MESSAGE#移库成功!#Stock transfer successful!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    SELECT 'xxbad_toloc' focus;
                END;
                SELECT TOP 1
                       ToLoc xxbad_toloc,
                       PartNum xxbad_part,
                       ToLot xxbad_lot,
                       FromSite xxbad_site,
                       'xxbad_toloc' focus,
                       ExtendedField1 xxbad_ship_id,
                       (
                           SELECT SUM(Qty)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_extension1,
                       (
                           SELECT COUNT(1)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_extension2
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                --返回第二个dataset
                SELECT *
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
            END;
            ELSE IF @ScanData = 'xxbad_toloc'
            BEGIN
                --判断库位是否存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_Location
                    WHERE xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#库位不存在!#Location does not exist!', 11, 1);

                END;
                --返回第一个dateset 到前台
                SELECT @xxbad_toloc xxbad_toloc,
                       'xxbad_id' focus;
            END;
            ELSE
            BEGIN
                --处理扫描的条码

                --从标签中加载信息  并且判断标签状态
                SELECT @xxbad_ship_id = ShipSN,
                       @xxbad_id = USN,
                       @xxbad_part = PartNum,
                       @xxbad_desc = PartDescription,
                       @xxbad_qty = Qty,
                       @xxbad_lot = Lot,
                       @InspectUser = InspectUser,
                       @InspectResult = InspectResult,
                       @xxbad_fromloc = CurrentLoc
                FROM Barocde_BoxlLable
                WHERE USN = @xxbad_id
                      AND Status = 3;
                IF (ISNULL(@xxbad_desc, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签或标签状态不正确!#Incorrect tag or tag status!', 11, 1);

                END;

                --判断 到库位 是否在零件的配置的库区内
                --IF NOT EXISTS
                --(
                --    SELECT TOP 1
                --           1
                --    FROM Barcode_Location
                --    WHERE LocArea IN
                --          (
                --              SELECT LocArea FROM Barcode_ItemLocArea WHERE ItemNum = @xxbad_part
                --          --AND xxlocation_site = @xxbad_site
                --          )
                --          AND xxlocation_loc = @xxbad_toloc
                --)
                --BEGIN
                --    RAISERROR(N'ERROR_MESSAGE#当前成品不能上架到此库区!#The current product cannot be placed in this storage area!', 11, 1);
                --    
                --END;
                IF (ISNULL(@xxbad_fromloc, '') = ISNULL(@xxbad_toloc, ''))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前成品已经在到库位下面了!#The current finished product is already under the storage location!', 11, 1);
                END;
                --判断箱码 的从库位 不能是线边库位
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.ProdLine
                    WHERE LineCode = @xxbad_fromloc
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#不能从线边使用此功能!#This feature cannot be used from the line side!', 11, 1);
                END;
                IF ISNULL(@xxbad_toloc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请先扫描到库位!#Please scan the storage location first!', 11, 1);
                END;
                --判断当前原材料是否被被人缓存了
                SELECT TOP 1
                       @cacheuser = OpUser
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND LableID = @xxbad_id;
                IF (ISNULL(@cacheuser, @xxbad_user) <> @xxbad_user)
                BEGIN
                    SET @ErrorMessage
                        = N'ERROR_MESSAGE#该箱码被用户' + @cacheuser + N'扫描，请提醒其操作!#The box code has been scanned by user ' + @cacheuser + N'. Please remind them to take action!';
                    RAISERROR(@ErrorMessage, 11, 1);

                END;
                --如果在动态高速缓存表不存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                          AND LableID = @xxbad_id
                )
                BEGIN
                    --从标签中获取标签信息 插入动态高速缓存表
                    INSERT INTO [dbo].[Barcode_OperateCache]
                    (
                        id,
                        [AppID],
                        [OpUser],
                        [LableID],
                        [PartNum],
                        [PartDescrition],
                        [Qty],
                        ToLot,
                        [FromLoc],
                        [CurrentLoc],
                        [ToLoc],
                        [FromSite],
                        [ToSite],
                        [ScanTime],
                        ExtendedField1
                    )
                    SELECT TOP 1
                           NEWID(),
                           @interfaceid,
                           @xxbad_user,
                           @xxbad_id,
                           PartNum,
                           PartDescription,
                           Qty,
                           Lot,
                           CurrentLoc,
                           CurrentLoc,
                           @xxbad_toloc,
                           Site,
                           @xxbad_site,
                           GETDATE(),
                           WoNum
                    FROM dbo.Barocde_BoxlLable
                    WHERE USN = @xxbad_id;
                END;
                ELSE
                BEGIN
                    --DELETE [Barcode_OperateCache]
                    --WHERE AppID = @interfaceid
                    --      AND OpUser = @xxbad_user
                    --      AND LableID = @xxbad_id;
                    RAISERROR(N'ERROR_MESSAGE#不能重复扫描当前标签!#Cannot scan the current label again!', 11, 1);
                END;
                --返回第一个dataset到前台
                SELECT TOP 1
                       ToLoc xxbad_toloc,
                       PartNum xxbad_part,
                       FromSite xxbad_site,
                       '' xxbad_id,
                       ToLot xxbad_lot,
                       ExtendedField1 xxbad_ship_id,
                       (
                           SELECT SUM(Qty)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_extension1,
                       (
                           SELECT COUNT(1)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_extension2
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;

                --返回第二个dataset到前台
                SELECT LableID,
                       PartNum,
                       PartDescrition
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
            END;
        END;
        IF @interfaceid IN ( 10066 ) --仓库单个成品通用移库   --中用不用
        BEGIN
            --先处理命令  然后在处理数据  只有还未打包的 才能移库
            IF @ScanData = 'Submit'
            BEGIN
                --判断当前 库存 是否足够移库
                --以后补上 逻辑
                --判断当前库位 是否和到库位相同
                SELECT @xxbad_fromloc = CurrentLoc
                FROM dbo.Barocde_FGlLable
                WHERE USN = @ScanData
                      AND Status = 4;
                --判断标签是否合法
                IF ISNULL(@xxbad_fromloc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                IF (ISNULL(@xxbad_fromloc, '') = ISNULL(@xxbad_toloc, ''))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前标签已经在到库位下面了!#The current label is already under the destination location!', 11, 1);

                END;
                --更新标签的库位
                UPDATE dbo.Barocde_FGlLable
                SET FromLoc = CurrentLoc,
                    CurrentLoc = @xxbad_toloc
                WHERE USN = @xxbad_id;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg]
                )
                SELECT @xxbad_domain,
                       'IC_TR',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       dbo.GetQADloc(@xxbad_fromloc),
                       dbo.GetQADloc(@xxbad_toloc),
                       Lot,
                       Lot,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       USN,
                       Qty
                FROM dbo.Barocde_FGlLable
                WHERE USN = @xxbad_id;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       USN,
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       @xxbad_fromloc,
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       @xxbad_id,
                       Qty,
                       Lot,
                       Lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM dbo.Barocde_FGlLable
                WHERE USN = @xxbad_id;
                RAISERROR(N'Info_MESSAGE#提交成功!#Submission successful!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_toloc' READONLY;
            END;
            ELSE --认为扫描的是条码数据
            BEGIN
                --如果到库位是空 默认认为扫描的是到库位
                IF ISNULL(@xxbad_toloc, '') = ''
                BEGIN
                    --判断库位是否合法
                    IF EXISTS
                    (
                        SELECT TOP 1
                               1
                        FROM dbo.Barcode_Location
                        WHERE xxlocation_loc = @ScanData
                    )
                    BEGIN
                        SELECT @ScanData xxbad_toloc;
                    END;
                    ELSE
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#库位不存在!#Location does not exist!', 11, 1);

                    END;
                END;
                ELSE
                BEGIN --认为扫描的是标签
                    --读取标签中的信息
                    SELECT @xxbad_id = USN,
                           @xxbad_qty = Qty,
                           @xxbad_part = PartNum,
                           @xxbad_desc = PartDescription,
                           @xxbad_fromloc = CurrentLoc
                    FROM dbo.Barocde_FGlLable
                    WHERE USN = @ScanData
                          AND Status = 0;
                    --判断标签是否合法
                    IF ISNULL(@xxbad_part, '') = ''
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                    END;
                    PRINT @xxbad_part;
                    PRINT @xxbad_fromloc;
                    --判断零件是否可以移库到到库位
                    SELECT @msg_error = dbo.CheckLocArea(@xxbad_part, @xxbad_toloc, 1);
                    IF ISNULL(@msg_error, '') <> ''
                    BEGIN
                        RAISERROR(@msg_error, 11, 1);

                    END;
                    --判断零件是否可以从从库位移除
                    SELECT @msg_error = dbo.CheckLocArea(@xxbad_part, @xxbad_fromloc, 0);
                    IF ISNULL(@msg_error, '') <> ''
                    BEGIN
                        RAISERROR(@msg_error, 11, 1);

                    END;
                    --返回第一个dataset 到前台
                    SELECT @xxbad_id xxbad_id,
                           @xxbad_qty xxbad_qty,
                           @xxbad_part xxbad_part,
                           @xxbad_desc xxbad_desc,
                           @xxbad_fromloc xxbad_fromloc,
                           @xxbad_toloc xxbad_toloc;
                END;
            END;
        END;
        DECLARE @json VARCHAR(MAX);
        IF @interfaceid IN ( 5224 ) --成品销售发运备料
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --从标签中加载信息  并且判断标签状态 只有上架并且零件号匹配的标签 才能发运
                SELECT @xxbad_loc = CurrentLoc
                FROM Barocde_BoxlLable
                WHERE USN = @xxbad_extension1
                      AND (Status = 3);
                IF (ISNULL(@xxbad_loc, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签状态不正确!#Incorrect tag status!', 11, 1);

                END;
                --判断是否提前维护了 寄存库位
                SET @xxbad_toloc = dbo.GetCustloc(@xxbad_order);
                IF (ISNULL(@xxbad_toloc, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前订单对应的客户没有维护寄存库位!#The customer associated with the current order has not maintained a storage location!', 11, 1);

                END;
                IF (ISNULL(@xxbad_extension1, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前没有需要提交的标签，请先扫描标签!#There are currently no tags to submit. Please scan the tags first!', 11, 1);
                END;
                --限请扫描推荐的标签
                --IF NOT EXISTS
                --(
                --    SELECT TOP 1
                --           1
                --    FROM [Barcode_OperateCache]
                --    WHERE AppID = @interfaceid
                --          AND OpUser = @xxbad_user
                --          AND LableID = @xxbad_extension1
                --)
                --BEGIN
                --    RAISERROR(N'ERROR_MESSAGE#请下架推荐的标签!#Please remove the recommended tags!', 11, 1);
                --END;
                --获取标签中数量
                SELECT @xxbad_qty = Qty
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_extension1;
                --AND AppID = @interfaceid;
                --实时校验qad 中是否还有欠交量 不能直接访问qad 会造成死锁
                DECLARE @qadqty DECIMAL(18, 4) = 0,
                        @quneueqty DECIMAL(18, 4) = 0;
                SELECT @qadqty = sod_qty_ord - ISNULL(sod_qty_ship, 0)
                FROM sod_det
                WHERE sod_nbr = @xxbad_order
                      AND sod_line = @xxbad_proline;
                --获取队列中还没有上传的的汇总求和的数据
                SELECT @quneueqty = SUM(xxinbxml_qty_chg)
                FROM dbo.xxinbxml_mstr
                WHERE BarcodeInterFaceID = 5224
                      AND xxinbxml_ord = @xxbad_order
                      AND xxinbxml_line = @xxbad_proline
                      AND xxinbxml_status = 0;
                IF @qadqty - @quneueqty - @xxbad_qty < 0
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前订单行不能超量发运!#The current order line cannot be over-shipped!', 11, 1);
                END;
                --更新销售订单中的发运总数量   中用使用销售计划
                UPDATE sod_det
                SET sod_shipQty = ISNULL(sod_shipQty, 0) + @xxbad_qty
                FROM sod_det
                WHERE sod_nbr = @xxbad_order
                      AND sod_line = @xxbad_proline;

                --更新备料明细表中的累计备料量,累计总箱数
                UPDATE dbo.Barcode_SOShippingDetail
                SET AllotQty = ISNULL(AllotQty, 0) + @xxbad_qty,
                    shipboxcount = ISNULL(shipboxcount, 0) + 1
                WHERE ShipSN = @xxbad_ship_id
                      AND PurchaseOrder = @xxbad_order
                      AND Line = @xxbad_proline;
                --将托表中的标签 库位，状态，发运单 字段更新
                UPDATE dbo.Barocde_BoxlLable
                SET CurrentLoc = @xxbad_toloc,
                    Status = 5,
                    FromLoc = CurrentLoc,
                    ShipSN = @xxbad_ship_id,
                    PurchaseOrder = @xxbad_order,
                    PoLine = @xxbad_proline
                WHERE USN = @xxbad_extension1;

                -- 如果全部备料完成 将发运主表状态更改为已发运
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_SOShippingDetail
                    WHERE ShipSN = @xxbad_ship_id
                          AND CurrentQty > ISNULL(AllotQty, 0)
                )
                BEGIN
                    UPDATE dbo.shipboxplan
                    SET status = 2
                    WHERE sn = @xxbad_ship_id;
                END;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    BarcodeInterFaceID,
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @xxbad_domain,
                       @interfaceid,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       PurchaseOrder,
                       PoLine,
                       PartNum,
                       dbo.GetQADloc(FromLoc),
                       @xxbad_toloc,
                       @xxbad_site,
                       @xxbad_site,
                       @xxbad_ship_id,
                       @xxbad_id,
                       Qty,
                       Lot,
                       Lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM Barocde_BoxlLable
                WHERE USN = @xxbad_extension1;
                --FROM Barcode_OperateCache
                --WHERE AppID = @interfaceid
                --      AND OpUser = @xxbad_user
                --      AND ShipID = @xxbad_ship_id
                --      AND LableID = @xxbad_extension1;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       USN,
                       @xxbad_user,
                       PurchaseOrder,
                       PoLine,
                       PartNum,
                       FromLoc,
                       @xxbad_toloc,
                       'VIAM',
                       'VIAM',
                       @xxbad_ship_id,
                       @xxbad_id,
                       Qty,
                       Lot,
                       Lot,
                       @xxbad_fromref,
                       @xxbad_toref
                FROM Barocde_BoxlLable
                WHERE USN = @xxbad_extension1;
                --FROM Barcode_OperateCache
                --WHERE AppID = @interfaceid
                --      AND OpUser = @xxbad_user
                --      AND ShipID = @xxbad_ship_id
                --      AND LableID = @xxbad_extension1;
                --清理缓存
                DELETE [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                      AND LableID = @xxbad_extension1;
                --返回第一个dateset 到前台 将明细表备料第一行带出
                SELECT @xxbad_ship_id xxbad_ship_id,
                       @xxbad_order xxbad_order,
                       @xxbad_proline xxbad_proline,
                       @xxbad_part xxbad_part,
                       @xxbad_id xxbad_extension1,
                       shipboxcount xxbad_extension2,
                       'xxbad_id' focus,
                       @xxbad_scrapqty xxbad_scrapqty,
                       AllotQty xxbad_rj_qty
                FROM dbo.Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                      AND PurchaseOrder = @xxbad_order
                      AND Line = @xxbad_proline;
                --返回第二个dataset到前台 按照批次检索
                SELECT LableID USN,
                       CurrentLoc,
                       Qty,
                       ToLot Lot
                FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                RAISERROR(N'Info_MESSAGE#下架完成!#Unlisted successfully!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                --获取缓存中发运单号
                SELECT 'xxbad_ship_id' focus;
            END;
            ELSE IF @ScanData = 'xxbad_saleship_id'
            BEGIN
                --翻滚发运明细行
                SELECT @xxbad_order = PurchaseOrder,
                       @xxbad_proline = Line,
                       @xxbad_part = Item,
                       @xxbad_scrapqty = CurrentQty,
                       @xxbad_rj_qty = ISNULL(AllotQty, 0),
                       @xxbad_extension3 = shipboxcount,
                       @xxbad_extension4 = boxnum
                FROM dbo.Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                      AND '[' + PurchaseOrder + '_' + Line + ']' = @xxbad_saleship_id;
                --判断是否提前维护了 寄存库位
                SET @xxbad_toloc = dbo.GetCustloc(@xxbad_order);
                IF (ISNULL(@xxbad_toloc, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前订单对应的客户没有维护寄存库位!#The customer associated with the current order has not maintained a storage location!', 11, 1);

                END;
                CREATE TABLE #tempLable5224
                (
                    [ID] [INT] IDENTITY(1, 1) NOT NULL,
                    USN NVARCHAR(50) NULL,
                    Qty DECIMAL(18, 5) NULL,
                    CurrentLoc NVARCHAR(50) NULL,
                    lot NVARCHAR(50) NULL
                );

                --从成品表 按照标签号排序
                INSERT INTO #tempLable5224
                SELECT USN,
                       Qty,
                       CurrentLoc,
                       Lot
                FROM dbo.Barocde_BoxlLable
                WHERE PartNum = @xxbad_part
                      AND Status = 3
                      AND Qty > 0
                      AND dbo.GetlocAreaId(CurrentLoc) = 1
                ORDER BY Lot,
                         USN ASC;

                --按照汇总数量排序临时表
                SELECT ID,
                       USN,
                       Qty,
                       CurrentLoc,
                       (
                           SELECT SUM(Qty) FROM #tempLable5224 b WHERE a.ID >= b.ID
                       ) fQty,
                       a.lot
                INTO #t_lable5224
                FROM #tempLable5224 a
                ORDER BY ID;
                --先删除然后 插入动态高速缓存表 (删除别人的)
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND ShipID = @xxbad_ship_id
                      AND PartNum = @xxbad_part;
                --删除自己的
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;

                --INSERT INTO [dbo].[Barcode_OperateCache]
                --(
                --    id,
                --    [AppID],
                --    [OpUser],
                --    LableID,
                --    [Qty],
                --    CurrentLoc,
                --    ExtendedField1,
                --    ExtendedField2,
                --    ShipID,
                --    PartNum,
                --    ToLoc
                --)
                --SELECT NEWID(),
                --       @interfaceid,
                --       @xxbad_user,
                --       a.USN,
                --       a.Qty,
                --       CurrentLoc,
                --       a.fQty,
                --       a.Qty,
                --       @xxbad_ship_id,
                --       @xxbad_part,
                --       @xxbad_toloc   
                --FROM #t_lable5224 a 
                --WHERE ID <= ISNULL(
                --            (
                --                SELECT TOP 1
                --                       ID
                --                FROM #t_lable5224
                --                WHERE fQty > CONVERT(
                --                                        DECIMAL(18, 5),
                --                                        ISNULL(
                --                                                  (CONVERT(DECIMAL(18, 5), @xxbad_scrapqty)
                --                                                   - CONVERT(DECIMAL(18, 5), @xxbad_rj_qty)
                --                                                  ),
                --                                                  0
                --                                              )
                --                                    )
                --                ORDER BY ID
                --            ),
                --            ID
                --                  )
                --      AND CONVERT(DECIMAL(18, 5), @xxbad_scrapqty) > CONVERT(DECIMAL(18, 5), @xxbad_rj_qty);

                SELECT a.lot
                INTO #selectusnlot
                FROM #t_lable5224 a
                WHERE ID <= ISNULL(
                            (
                                SELECT TOP 1
                                       ID
                                FROM #t_lable5224
                                WHERE fQty > CONVERT(
                                                        DECIMAL(18, 5),
                                                        ISNULL(
                                                                  (CONVERT(DECIMAL(18, 5), @xxbad_scrapqty)
                                                                   - CONVERT(DECIMAL(18, 5), @xxbad_rj_qty)
                                                                  ),
                                                                  0
                                                              )
                                                    )
                                ORDER BY ID
                            ),
                            ID
                                  )
                      AND CONVERT(DECIMAL(18, 5), @xxbad_scrapqty) > CONVERT(DECIMAL(18, 5), @xxbad_rj_qty);


                INSERT INTO [dbo].[Barcode_OperateCache]
                (
                    id,
                    [AppID],
                    [OpUser],
                    LableID,
                    [Qty],
                    CurrentLoc,
                    ExtendedField1,
                    ExtendedField2,
                    ShipID,
                    PartNum,
                    ToLoc,
                    PoNum,
                    PoLine
                )
                SELECT NEWID(),
                       @interfaceid,
                       @xxbad_user,
                       a.USN,
                       a.Qty,
                       CurrentLoc,
                       a.Lot,
                       a.Qty,
                       @xxbad_ship_id,
                       @xxbad_part,
                       @xxbad_toloc,
                       @xxbad_order,
                       @xxbad_proline
                FROM dbo.Barocde_BoxlLable a
                WHERE a.PartNum = @xxbad_part
                      AND a.Status = 3
                      AND a.Qty > 0
                      AND dbo.GetlocAreaId(a.CurrentLoc) = 1
                      AND a.Lot IN
                          (
                              SELECT lot FROM #selectusnlot
                          );


                --返回第一个dataset
                SELECT @xxbad_ship_id xxbad_ship_id,
                       @xxbad_order xxbad_order,
                       @xxbad_proline xxbad_proline,
                       @xxbad_saleship_id xxbad_saleship_id,
                       @xxbad_part xxbad_part,
                       @xxbad_extension4 xxbad_extension4,
                       @xxbad_extension3 xxbad_extension3,
                       'xxbad_id' focus,
                       (
                           SELECT SUM(boxnum)
                           FROM dbo.Barcode_SOShippingDetail
                           WHERE ShipSN = @xxbad_ship_id
                       ) xxbad_extension5,
                       @xxbad_rj_qty xxbad_rj_qty;
                --返回第二个dataset到前台 按照先进先出的规则 将成品标签排序
                SELECT LableID USN,
                       CurrentLoc,
                       Qty,
                       ToLot Lot
                FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
            END;
            ELSE IF @ScanData = 'xxbad_ship_id'
            BEGIN
                --判断发运单是否合法
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.shipboxplan
                    WHERE sn = @xxbad_ship_id
                --AND status = 1
                )
                BEGIN
                    SET @ErrorMessage = @xxbad_ship_id + N'ERROR_MESSAGE#销售单号不合法 !#Invalid sales order number!';
                    RAISERROR(@ErrorMessage, 11, 1);

                END;
                --返回第一个dateset 到前台 将明细表备料第一行带出
                SELECT @xxbad_ship_id xxbad_ship_id,
                       'xxbad_saleship_id' focus,
                       SUM(boxnum) xxbad_extension5
                FROM dbo.Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id;
                --返回第二个dataset到前台 
                SELECT LableID USN,
                       CurrentLoc,
                       Qty,
                       ToLot Lot
                FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
            END;
            ELSE IF @ScanData = 'xxbad_id'
            BEGIN

                --从标签中加载信息  并且判断标签状态 只有上架并且零件号匹配的标签 才能发运
                SELECT @xxbad_id = USN,
                       @xxbad_lot = Lot,
                       @xxbad_qty = Qty,
                       @xxbad_extension3 = PartNum,
                       @xxbad_status = Status,
                       @xxbad_loc = CurrentLoc
                FROM Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                --AND PartNum = @xxbad_part
                --AND (Status = 3);
                IF (ISNULL(@xxbad_loc, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不存在!#Tag does not exist!', 11, 1);
                END;
                IF (ISNULL(@xxbad_extension3, '') <> ISNULL(@xxbad_part, ''))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签零件和订单行不匹配!#Label parts and order lines do not match!', 11, 1);
                END;
                IF ISNULL(@xxbad_status, '0') IN ( 4, 5 )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签重复备料扫描!#Duplicate label material scanning!', 11, 1);
                END;
                IF ISNULL(@xxbad_status, '0') IN ( 1, 2 )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签还没有上架!#The label has not been listed yet!', 11, 1);
                END;
                --暂时不判断
                IF @xxbad_rj_qty = ''
                    SET @xxbad_rj_qty = 0;
                IF @xxbad_qty = ''
                    SET @xxbad_qty = 0;
                IF @xxbad_scrapqty = ''
                    SET @xxbad_scrapqty = 0;
                --判断当前原材料是否被被人缓存了
                SELECT TOP 1
                       @cacheuser = OpUser
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND LableID = @xxbad_id;
                IF (ISNULL(@cacheuser, @xxbad_user) <> @xxbad_user)
                BEGIN
                    SET @ErrorMessage
                        = N'ERROR_MESSAGE#该箱码被用户' + @cacheuser + N'扫描，请提醒其操作!#The box code has been scanned by user ' + @cacheuser + N'. Please remind them to take action!';
                    RAISERROR(@ErrorMessage, 11, 1);
                END;
                --限请扫描推荐的标签
                --IF NOT EXISTS
                --(
                --    SELECT TOP 1
                --           1
                --    FROM [Barcode_OperateCache]
                --    WHERE AppID = @interfaceid
                --          AND OpUser = @xxbad_user
                --          AND LableID = @xxbad_id
                --)
                --BEGIN
                --    RAISERROR(N'ERROR_MESSAGE#请扫描推荐的标签!#Please scan the recommended tags!', 11, 1);
                --END;
                --判断上一箱有没有点击提交按钮
                --IF EXISTS
                --(
                --    SELECT TOP 1
                --           1
                --    FROM [Barcode_OperateCache]
                --    WHERE AppID = @interfaceid
                --          AND OpUser = @xxbad_user
                --          AND ScanTime IS NOT NULL
                --          AND LableID <> @xxbad_id
                --)
                --BEGIN
                --    RAISERROR(N'ERROR_MESSAGE#上一张箱码没有点击领料按钮!#The previous box code did not click the material picking button!', 11, 1);

                --END;

                --UPDATE [Barcode_OperateCache]
                --SET ScanTime = GETDATE()
                --WHERE LableID = @xxbad_id; 

                SELECT @xxbad_extension2 = shipboxcount
                FROM Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                      AND PurchaseOrder = @xxbad_order
                      AND Line = @xxbad_proline;

                SELECT @xxbad_extension3 = shipboxcount
                FROM Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id;

                --判断单箱数量是否已经超量
                IF CONVERT(DECIMAL(18, 5), @xxbad_qty) > CONVERT(DECIMAL(18, 5), @xxbad_scrapqty)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#单箱数量已经超出本次发运量!#The quantity per box has exceeded the shipment quantity!', 11, 1);

                END;
                --判断是否超量备料
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_SOShippingDetail
                    WHERE ShipSN = @xxbad_ship_id
                          AND PurchaseOrder = @xxbad_order
                          AND Line = @xxbad_proline
                          AND ISNULL(AllotQty, 0) >= ISNULL(CurrentQty, 0)
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#不能超量备料!#Do not exceed the material limit!', 11, 1);

                END;

                --返回第一个dateset 到前台 将明细表备料第一行带出
                SELECT @xxbad_ship_id xxbad_ship_id,
                       @xxbad_order xxbad_order,
                       @xxbad_proline xxbad_proline,
                       @xxbad_part xxbad_part,
                       @xxbad_id xxbad_extension1,
                       @xxbad_extension2 xxbad_extension2,
                       @xxbad_extension3 xxbad_extension3,
                       'xxbad_id' focus,
                       @xxbad_scrapqty xxbad_scrapqty,
                       @xxbad_rj_qty xxbad_rj_qty;
                --返回第二个dataset到前台 按照批次检索
                SELECT LableID USN,
                       CurrentLoc,
                       Qty,
                       ToLot Lot
                FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
            END;
            ELSE
            BEGIN
                RAISERROR(N'ERROR_MESSAGE#无效的的扫描指令 !#Invalid scan command!', 11, 1);
            END;
        END;
        IF @interfaceid IN ( 5225 ) --原材料销售发运备料
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --从标签中加载信息  并且判断标签状态 只有上架并且零件号匹配的标签 才能发运
                SELECT @xxbad_loc = currentloc
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_extension1
                      AND (status = 4);
                IF (ISNULL(@xxbad_loc, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签状态不正确!#Incorrect tag status!', 11, 1);

                END;
                --判断是否提前维护了 寄存库位
                SET @xxbad_toloc = dbo.GetCustloc(@xxbad_order);
                IF (ISNULL(@xxbad_toloc, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前订单对应的客户没有维护寄存库位!#The customer associated with the current order has not maintained a storage location!', 11, 1);

                END;
                IF (ISNULL(@xxbad_extension1, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前没有需要提交的标签，请先扫描标签!#There are currently no tags to submit. Please scan the tags first!', 11, 1);
                END;
                --获取标签中数量
                SELECT @xxbad_qty = qty
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_extension1;
                --AND AppID = @interfaceid;
                --实时校验qad 中是否还有欠交量 不能直接访问qad 会造成死锁
                DECLARE @qadqty5225 DECIMAL(18, 4) = 0,
                        @quneueqty5225 DECIMAL(18, 4) = 0;
                SELECT @qadqty5225 = sod_qty_ord - ISNULL(sod_qty_ship, 0)
                FROM sod_det
                WHERE sod_nbr = @xxbad_order
                      AND sod_line = @xxbad_proline;
                --获取队列中还没有上传的的汇总求和的数据
                SELECT @quneueqty5225 = SUM(xxinbxml_qty_chg)
                FROM dbo.xxinbxml_mstr
                WHERE BarcodeInterFaceID = 5225
                      AND xxinbxml_ord = @xxbad_order
                      AND xxinbxml_line = @xxbad_proline
                      AND xxinbxml_status = 0;
                IF @qadqty5225 - @quneueqty5225 - @xxbad_qty < 0
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前订单行不能超量发运!#The current order line cannot be over-shipped!', 11, 1);
                END;
                --更新销售订单中的发运总数量   中用使用销售计划
                UPDATE sod_det
                SET sod_shipQty = ISNULL(sod_shipQty, 0) + @xxbad_qty
                FROM sod_det
                WHERE sod_nbr = @xxbad_order
                      AND sod_line = @xxbad_proline;

                --更新备料明细表中的累计备料量
                UPDATE dbo.Barcode_SOShippingDetail
                SET AllotQty = ISNULL(AllotQty, 0) + @xxbad_qty
                WHERE ShipSN = @xxbad_ship_id
                      AND PurchaseOrder = @xxbad_order
                      AND Line = @xxbad_proline;
                --将托表中的标签 库位，状态，发运单 字段更新  9是转售
                UPDATE dbo.barocde_materiallable
                SET currentloc = @xxbad_toloc,
                    status = 9,
                    fromloc = currentloc,
                    soshipnum = @xxbad_ship_id,
                    sonum = @xxbad_order,
                    soline = @xxbad_proline
                WHERE usn = @xxbad_extension1;

                -- 如果全部备料完成 将发运主表状态更改为已发运
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_SOShippingDetail
                    WHERE ShipSN = @xxbad_ship_id
                          AND CurrentQty > ISNULL(AllotQty, 0)
                )
                BEGIN
                    UPDATE dbo.shipboxplan
                    SET status = 2
                    WHERE sn = @xxbad_ship_id;
                END;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    BarcodeInterFaceID,
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @xxbad_domain,
                       @interfaceid,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       sonum,
                       soline,
                       partnum,
                       dbo.GetQADloc(fromloc),
                       @xxbad_toloc,
                       @xxbad_site,
                       @xxbad_site,
                       @xxbad_ship_id,
                       @xxbad_id,
                       qty,
                       lot,
                       lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM barocde_materiallable
                WHERE usn = @xxbad_extension1;

                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       usn,
                       @xxbad_user,
                       sonum,
                       soline,
                       partnum,
                       fromloc,
                       @xxbad_toloc,
                       'VIAM',
                       'VIAM',
                       @xxbad_ship_id,
                       @xxbad_id,
                       qty,
                       lot,
                       lot,
                       @xxbad_fromref,
                       @xxbad_toref
                FROM barocde_materiallable
                WHERE usn = @xxbad_extension1;

                --清理缓存
                DELETE [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                      AND LableID = @xxbad_extension1;
                --返回第一个dateset 到前台 将明细表备料第一行带出
                SELECT @xxbad_ship_id xxbad_ship_id,
                       @xxbad_order xxbad_order,
                       @xxbad_proline xxbad_proline,
                       @xxbad_part xxbad_part,
                       @xxbad_id xxbad_extension1,
                       'xxbad_id' focus,
                       @xxbad_scrapqty xxbad_scrapqty,
                       AllotQty xxbad_rj_qty
                FROM dbo.Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                      AND PurchaseOrder = @xxbad_order
                      AND Line = @xxbad_proline;
                --返回第二个dataset到前台 按照批次检索
                SELECT LableID USN,
                       CurrentLoc,
                       Qty,
                       ToLot Lot
                FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                RAISERROR(N'Info_MESSAGE#下架完成!#Unlisted successfully!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                --获取缓存中发运单号
                SELECT 'xxbad_ship_id' focus;
            END;
            ELSE IF @ScanData = 'xxbad_saleship_id'
            BEGIN
                --翻滚发运明细行
                SELECT @xxbad_order = PurchaseOrder,
                       @xxbad_proline = Line,
                       @xxbad_part = Item,
                       @xxbad_scrapqty = CurrentQty,
                       @xxbad_rj_qty = ISNULL(AllotQty, 0)
                FROM dbo.Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                      AND '[' + PurchaseOrder + '_' + Line + ']' = @xxbad_saleship_id;
                --判断是否提前维护了 寄存库位
                SET @xxbad_toloc = dbo.GetCustloc(@xxbad_order);
                IF (ISNULL(@xxbad_toloc, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前订单对应的客户没有维护寄存库位!#The customer associated with the current order has not maintained a storage location!', 11, 1);

                END;
                CREATE TABLE #tempLable5225
                (
                    [ID] [INT] IDENTITY(1, 1) NOT NULL,
                    USN NVARCHAR(50) NULL,
                    Qty DECIMAL(18, 5) NULL,
                    CurrentLoc NVARCHAR(50) NULL,
                    lot NVARCHAR(50) NULL
                );

                --从成品表 按照标签号排序
                INSERT INTO #tempLable5225
                SELECT usn,
                       qty,
                       currentloc,
                       lot
                FROM dbo.barocde_materiallable
                WHERE partnum = @xxbad_part
                      AND status = 4
                      AND Qty > 0
                      AND dbo.GetlocAreaId(CurrentLoc) = 2
                ORDER BY lot,
                         usn ASC;

                --按照汇总数量排序临时表
                SELECT ID,
                       USN,
                       Qty,
                       CurrentLoc,
                       (
                           SELECT SUM(Qty) FROM #tempLable5225 b WHERE a.ID >= b.ID
                       ) fQty,
                       a.lot
                INTO #t_lable5225
                FROM #tempLable5225 a
                ORDER BY ID;
                --先删除然后 插入动态高速缓存表 (删除别人的)
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND ShipID = @xxbad_ship_id
                      AND PartNum = @xxbad_part;
                --删除自己的
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;


                SELECT a.lot
                INTO #selectusnlot5225
                FROM #t_lable5225 a
                WHERE ID <= ISNULL(
                            (
                                SELECT TOP 1
                                       ID
                                FROM #t_lable5225
                                WHERE fQty > CONVERT(
                                                        DECIMAL(18, 5),
                                                        ISNULL(
                                                                  (CONVERT(DECIMAL(18, 5), @xxbad_scrapqty)
                                                                   - CONVERT(DECIMAL(18, 5), @xxbad_rj_qty)
                                                                  ),
                                                                  0
                                                              )
                                                    )
                                ORDER BY ID
                            ),
                            ID
                                  )
                      AND CONVERT(DECIMAL(18, 5), @xxbad_scrapqty) > CONVERT(DECIMAL(18, 5), @xxbad_rj_qty);


                INSERT INTO [dbo].[Barcode_OperateCache]
                (
                    id,
                    [AppID],
                    [OpUser],
                    LableID,
                    [Qty],
                    CurrentLoc,
                    ExtendedField1,
                    ExtendedField2,
                    ShipID,
                    PartNum,
                    ToLoc,
                    PoNum,
                    PoLine
                )
                SELECT NEWID(),
                       @interfaceid,
                       @xxbad_user,
                       a.usn,
                       a.qty,
                       currentloc,
                       a.lot,
                       a.qty,
                       @xxbad_ship_id,
                       @xxbad_part,
                       @xxbad_toloc,
                       @xxbad_order,
                       @xxbad_proline
                FROM dbo.barocde_materiallable a
                WHERE a.partnum = @xxbad_part
                      AND a.status = 4
                      AND a.qty > 0
                      AND dbo.GetlocAreaId(a.currentloc) = 2
                      AND a.lot IN
                          (
                              SELECT lot FROM #selectusnlot5225
                          );


                --返回第一个dataset
                SELECT @xxbad_ship_id xxbad_ship_id,
                       @xxbad_order xxbad_order,
                       @xxbad_proline xxbad_proline,
                       @xxbad_saleship_id xxbad_saleship_id,
                       @xxbad_part xxbad_part,
                       'xxbad_id' focus,
                       @xxbad_scrapqty xxbad_scrapqty,
                       @xxbad_rj_qty xxbad_rj_qty;
                --返回第二个dataset到前台 按照先进先出的规则 将成品标签排序
                SELECT LableID USN,
                       CurrentLoc,
                       Qty,
                       ToLot Lot
                FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
            END;
            ELSE IF @ScanData = 'xxbad_ship_id'
            BEGIN
                --判断发运单是否合法
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.shipboxplan
                    WHERE sn = @xxbad_ship_id
                --AND status = 1
                )
                BEGIN
                    SET @ErrorMessage = @xxbad_ship_id + N'ERROR_MESSAGE#销售单号不合法 !#Invalid sales order number!';
                    RAISERROR(@ErrorMessage, 11, 1);

                END;
                --返回第一个dateset 到前台 将明细表备料第一行带出
                SELECT @xxbad_ship_id xxbad_ship_id,
                       'xxbad_saleship_id' focus;
                --返回第二个dataset到前台 
                SELECT LableID USN,
                       CurrentLoc,
                       Qty,
                       ToLot Lot
                FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
            END;
            ELSE IF @ScanData = 'xxbad_id'
            BEGIN

                --从标签中加载信息  并且判断标签状态 只有上架并且零件号匹配的标签 才能发运
                SELECT @xxbad_id = usn,
                       @xxbad_lot = lot,
                       @xxbad_qty = qty,
                       @xxbad_part = partnum,
                       @xxbad_loc = currentloc
                FROM barocde_materiallable
                WHERE usn = @xxbad_id
                      AND partnum = @xxbad_part
                      AND (status = 4);
                IF (ISNULL(@xxbad_loc, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不正确!#Invalid tag!', 11, 1);

                END;

                --暂时不判断
                IF @xxbad_rj_qty = ''
                    SET @xxbad_rj_qty = 0;
                IF @xxbad_qty = ''
                    SET @xxbad_qty = 0;
                IF @xxbad_scrapqty = ''
                    SET @xxbad_scrapqty = 0;
                --判断当前原材料是否被被人缓存了
                SELECT TOP 1
                       @cacheuser = OpUser
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND LableID = @xxbad_id;
                IF (ISNULL(@cacheuser, @xxbad_user) <> @xxbad_user)
                BEGIN
                    SET @ErrorMessage
                        = N'ERROR_MESSAGE#该箱码被用户' + @cacheuser + N'扫描，请提醒其操作!#The box code has been scanned by user ' + @cacheuser + N'. Please remind them to take action!';
                    RAISERROR(@ErrorMessage, 11, 1);

                END;

                --判断单箱数量是否已经超量
                IF CONVERT(DECIMAL(18, 5), @xxbad_qty) > CONVERT(DECIMAL(18, 5), @xxbad_scrapqty)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#单箱数量已经超出本次发运量!#The quantity per box has exceeded the shipment quantity!', 11, 1);

                END;
                --判断是否超量备料
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_SOShippingDetail
                    WHERE ShipSN = @xxbad_ship_id
                          AND PurchaseOrder = @xxbad_order
                          AND Line = @xxbad_proline
                          AND ISNULL(AllotQty, 0) >= ISNULL(CurrentQty, 0)
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#不能超量备料!#Do not exceed the material limit!', 11, 1);

                END;

                --返回第一个dateset 到前台 将明细表备料第一行带出
                SELECT @xxbad_ship_id xxbad_ship_id,
                       @xxbad_order xxbad_order,
                       @xxbad_proline xxbad_proline,
                       @xxbad_part xxbad_part,
                       @xxbad_id xxbad_extension1,
                       'xxbad_id' focus,
                       @xxbad_scrapqty xxbad_scrapqty,
                       @xxbad_rj_qty xxbad_rj_qty;
                --返回第二个dataset到前台 按照批次检索
                SELECT LableID USN,
                       CurrentLoc,
                       Qty,
                       ToLot Lot
                FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
            END;
            ELSE
            BEGIN
                RAISERROR(N'ERROR_MESSAGE#无效的的扫描指令 !#Invalid scan command!', 11, 1);
            END;
        END;
        IF @interfaceid IN ( 10082 ) --国外销售发运备料
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断托表中 是否有备料信息
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                          AND ExtendedField1 = @xxbad_ship_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前单据没有缓存的备料信息 !#No cached material information for the current document!', 11, 1);

                END;
                --判断所有的行 是否全部备料完成
                DECLARE @Unfinish10082 VARCHAR(2000);
                SELECT @Unfinish10082 = COALESCE(Item + '|' + Line, '')
                FROM dbo.Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                      AND ISNULL(AllotQty, 0) < CurrentQty;
                SET @ErrorMessage = N'ERROR_MESSAGE#' + @Unfinish10082 + N'未完成备料!#' + @Unfinish10082 + N'Unfinished material preparation!';
                IF ISNULL(@Unfinish10082, '') <> ''
                BEGIN
                    RAISERROR(@ErrorMessage, 11, 1);

                END;
                --获取发运模式
                SELECT @xxbad_toloc = SrmNum
                FROM Barcode_SOShippingMain
                WHERE SN = @xxbad_ship_id;
                --汇总计算每个
                SELECT SUM(CurrentQty) Qty,
                       PurchaseOrder,
                       Line
                INTO #temp110082
                FROM Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                GROUP BY PurchaseOrder,
                         Line;

                --更新销售订单中的发运总数量 中用使用销售计划
                --UPDATE a
                --SET a.sod_shipQty = ISNULL(a.sod_shipQty, 0)
                --                    + ISNULL(b.Qty, 0)
                --FROM sod_det a,
                --    #temp110082 b
                --WHERE a.sod_nbr = b.PurchaseOrder
                --      AND a.sod_line = b.Line;
                UPDATE a
                SET a.ShipQty = ISNULL(a.ShipQty, 0) + ISNULL(b.Qty, 0)
                FROM dbo.Barcode_ShipPlan a,
                     #temp110082 b
                WHERE a.ID = b.PurchaseOrder
                      AND a.Line = b.Line;
                --如果发运量大于计划量 则关闭发运计划
                UPDATE Barcode_ShipPlan
                SET Stauts = 0
                WHERE Stauts = 1
                      AND ShipQty >= PlanQty
                      AND ShipQty IS NOT NULL;
                --将托表中的标签 库位，状态，发运单 字段更新
                UPDATE dbo.Barcode_PalletLable
                SET CurrentLoc = @xxbad_toloc,
                    Status = 5,
                    FromLoc = CurrentLoc,
                    ShipSN = @xxbad_ship_id
                WHERE USN IN
                      (
                          SELECT LableID
                          FROM dbo.Barcode_OperateCache
                          WHERE AppID = @interfaceid
                                AND OpUser = @xxbad_user
                                AND ExtendedField1 = @xxbad_ship_id
                      );

                --将发运主表状态更改为已发运
                UPDATE dbo.Barcode_SOShippingMain
                SET Status = 2
                WHERE SN = @xxbad_ship_id;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    BarcodeInterFaceID,
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @xxbad_domain,
                       @interfaceid,
                       'PQ_SO_SHIPMNT',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       '',
                       b.PartNum,
                       dbo.GetQADloc(MAX(b.CurrentLoc)),
                       @xxbad_toloc,
                       MAX(b.Site),
                       MAX(b.Site),
                       @xxbad_ship_id,
                       @xxbad_id,
                       SUM(b.Qty),
                       b.Lot,
                       b.Lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM Barcode_OperateCache a,
                     dbo.Barocde_BoxlLable b
                WHERE a.LableID = b.PalletLable
                      AND AppID = @interfaceid
                      AND a.OpUser = @xxbad_user
                      AND a.ExtendedField1 = @xxbad_ship_id
                GROUP BY b.PartNum,
                         b.Lot;

                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'PQ_SO_SHIPMNT',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       b.USN,
                       @xxbad_user,
                       '',
                       '',
                       b.PartNum,
                       b.CurrentLoc,
                       @xxbad_toloc,
                       @xxbad_tosite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       b.Qty,
                       b.Lot,
                       b.Lot,
                       @xxbad_fromref,
                       @xxbad_toref
                FROM Barcode_OperateCache a,
                     dbo.Barocde_BoxlLable b
                WHERE a.LableID = b.PalletLable
                      AND a.AppID = @interfaceid
                      AND a.OpUser = @xxbad_user
                      AND a.ExtendedField1 = @xxbad_ship_id;
                --将每个FG小标签的状态 全部标记为已发运 放到后面 是因为到库位队列用到了
                UPDATE dbo.Barocde_BoxlLable
                SET Status = 5,
                    CurrentLoc = @xxbad_toloc
                WHERE PalletLable IN
                      (
                          SELECT LableID
                          FROM dbo.Barcode_OperateCache
                          WHERE AppID = @interfaceid
                                AND OpUser = @xxbad_user
                                AND ExtendedField1 = @xxbad_ship_id
                      );
                --清理缓存
                DELETE [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                RAISERROR(N'Info_MESSAGE#发运完成!#Shipment completed!', 11, 1);
            END;

            ELSE IF @ScanData = 'Cache'
            BEGIN
                --获取缓存中发运单号
                SELECT TOP 1
                       @xxbad_ship_id = ExtendedField1
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                GROUP BY ExtendedField1,
                         PoNum,
                         PoLine,
                         PartNum;
                --  根据发运单号获取  还没备料完成的第一行的记录  返回第一个dateset 到前台 
                SELECT TOP 1
                       ShipSN xxbad_ship_id,
                       PurchaseOrder xxbad_order,
                       Line xxbad_proline,
                       Item xxbad_part,
                       AllotQty xxbad_rj_qty,
                       CurrentQty xxbad_scrapqty
                FROM dbo.Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                      AND ISNULL(AllotQty, 0) <= CurrentQty
                ORDER BY AllotQty ASC;
                --返回第二个dataset到前台 按照批次检索 前10行的箱标签
                SELECT LableID USN,
                       CurrentLoc,
                       Qty,
                       ToLot Lot
                FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;

            END;
            ELSE
            BEGIN
                --处理数据扫描模块 如果到销售单号为空，认为当前扫描的是销售单号
                IF ISNULL(@xxbad_ship_id, '') = ''
                BEGIN
                    --判断发运单是否合法
                    IF NOT EXISTS
                    (
                        SELECT TOP 1
                               1
                        FROM dbo.Barcode_SOShippingMain
                        WHERE SN = @ScanData
                              AND SupplierType = 0
                              AND Status = 1
                    )
                    BEGIN
                        SET @ErrorMessage = @xxbad_ship_id + N'ERROR_MESSAGE#销售单号不合法 !#Invalid sales order number!';
                        RAISERROR(@ErrorMessage, 11, 1);

                    END;
                    SET @xxbad_ship_id = @ScanData;

                    SELECT TOP 1
                           @xxbad_order = PurchaseOrder,
                           @xxbad_proline = Line,
                           @xxbad_fromsite = sod_site,
                           @xxbad_tosite = sod_site,
                           @xxbad_part = Item,
                           @xxbad_scrapqty = CurrentQty,
                           @xxbad_rj_qty = ISNULL(AllotQty, 0)
                    FROM dbo.Barcode_SOShippingDetail
                    WHERE ShipSN = @xxbad_ship_id
                          AND ISNULL(AllotQty, 0) < CurrentQty
                    ORDER BY Item,
                             Line;

                    --返回第一个dateset 到前台 将明细表备料第一行带出
                    SELECT @xxbad_ship_id xxbad_ship_id,
                           @xxbad_order xxbad_order,
                           @xxbad_proline xxbad_proline,
                           @xxbad_fromsite xxbad_fromsite,
                           @xxbad_part xxbad_part,
                           @xxbad_scrapqty xxbad_scrapqty,
                           @xxbad_rj_qty xxbad_rj_qty;
                    --返回第二个dataset到前台 
                    SELECT LableID USN,
                           CurrentLoc,
                           Qty,
                           ToLot Lot
                    FROM dbo.Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user;
                END;
                ELSE
                BEGIN --处理扫描的条码
                    --从标签中加载信息  并且判断标签状态 只有上架并且零件号匹配的标签 才能发运
                    SELECT @xxbad_id = USN,
                           @xxbad_lot = Lot,
                           @xxbad_qty = Qty,
                           @xxbad_part = PartNum,
                           @xxbad_loc = CurrentLoc
                    FROM Barcode_PalletLable
                    WHERE USN = @ScanData
                          AND PartNum = @xxbad_part
                          AND
                          (
                              Status = 3
                              OR Status = 4
                          );
                    IF (ISNULL(@xxbad_id, '') = '')
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#标签不正确!#Invalid tag!', 11, 1);

                    END;
                    --判断零件是否可以从从库位移除
                    SELECT @msg_error = dbo.CheckLocArea(@xxbad_part, @xxbad_loc, @interfaceid);
                    IF ISNULL(@msg_error, '') <> ''
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#当前箱码不在成品货架，不能出库!#The current box code is not on the finished goods shelf and cannot be shipped out!', 11, 1);

                    END;

                    --判断当前客户的当前零件没有维护扩展信息
                    IF NOT EXISTS
                    (
                        SELECT TOP 1
                               1
                        FROM dbo.barcode_custompartset
                        WHERE partnum = @xxbad_part
                              AND customid =
                              (
                                  SELECT TOP 1
                                         SupplierCode
                                  FROM dbo.Barcode_SOShippingMain
                                  WHERE SN = @xxbad_ship_id
                              )
                    )
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#当前客户的当前零件没有维护扩展信息!#No extended information is maintained for the current part of the current customer!', 11, 1);

                    END;
                    --暂时不判断
                    IF @xxbad_rj_qty = ''
                        SET @xxbad_rj_qty = 0;
                    IF @xxbad_qty = ''
                        SET @xxbad_qty = 0;
                    IF @xxbad_scrapqty = ''
                        SET @xxbad_scrapqty = 0;
                    --判断当前原材料是否被被人缓存了
                    SELECT TOP 1
                           @cacheuser = OpUser
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND LableID = @ScanData;
                    IF (ISNULL(@cacheuser, @xxbad_user) <> @xxbad_user)
                    BEGIN
                        SET @ErrorMessage
                            = N'ERROR_MESSAGE#该箱码被用户' + @cacheuser + N'扫描，请提醒其操作!#The box code has been scanned by user ' + @cacheuser + N'. Please remind them to take action!';
                        RAISERROR(@ErrorMessage, 11, 1);

                    END;
                    --判断是不是推荐的箱码
                    CREATE TABLE #ResultLable5224
                    (
                        USN NVARCHAR(50) NULL,
                        PartNum NVARCHAR(200) NULL,
                        Qty DECIMAL(18, 5) NULL,
                        CurrentLoc NVARCHAR(50) NULL
                    );
                    INSERT INTO #ResultLable5224
                    EXEC dbo.GetSoFGlable @xxbad_ship_id;
                    IF NOT EXISTS (SELECT TOP 1 1 FROM #ResultLable5224 WHERE USN = @ScanData)
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#当前箱码不在推荐的列表中，不能出库!#The current box code is not on the recommended list and cannot be shipped out!', 11, 1);

                    END;
                    --如果在动态高速缓存表不存在
                    IF NOT EXISTS
                    (
                        SELECT TOP 1
                               1
                        FROM [Barcode_OperateCache]
                        WHERE AppID = @interfaceid
                              AND OpUser = @xxbad_user
                              AND ExtendedField1 = @xxbad_ship_id
                              AND LableID = @ScanData
                    )
                    BEGIN

                        --判断单箱数量是否已经超量
                        IF CONVERT(DECIMAL(18, 5), @xxbad_qty) > CONVERT(DECIMAL(18, 5), @xxbad_scrapqty)
                        BEGIN
                            RAISERROR(N'ERROR_MESSAGE#单箱数量已经超出本次发运量!#The quantity per box has exceeded the shipment quantity!', 11, 1);

                        END;
                        --判断是否超量备料
                        IF EXISTS
                        (
                            SELECT TOP 1
                                   1
                            FROM Barcode_SOShippingDetail
                            WHERE ShipSN = @xxbad_ship_id
                                  AND PurchaseOrder = @xxbad_order
                                  AND Line = @xxbad_proline
                                  AND ISNULL(AllotQty, 0) >= ISNULL(CurrentQty, 0)
                        )
                        BEGIN
                            RAISERROR(N'ERROR_MESSAGE#不能超量备料!#Do not exceed the material limit!', 11, 1);

                        END;
                        --从标签中获取标签信息 插入动态高速缓存表
                        INSERT INTO [dbo].[Barcode_OperateCache]
                        (
                            [AppID],
                            [OpUser],
                            [LableID],
                            [PartNum],
                            [PartDescrition],
                            [Qty],
                            ToLot,
                            PoNum,
                            PoLine,
                            [FromLoc],
                            [CurrentLoc],
                            [ToLoc],
                            [FromSite],
                            [ToSite],
                            [ScanTime],
                            ExtendedField1
                        )
                        SELECT TOP 1
                               @interfaceid,
                               @xxbad_user,
                               @ScanData,
                               PartNum,
                               PartDescription,
                               Qty,
                               Lot,
                               @xxbad_order,
                               @xxbad_proline,
                               CurrentLoc,
                               CurrentLoc,
                               @xxbad_toloc,
                               @xxbad_fromsite,
                               @xxbad_fromsite,
                               GETDATE(),
                               @xxbad_ship_id
                        FROM dbo.Barcode_PalletLable
                        WHERE USN = @ScanData;

                        --更新标签表 标记标签已经备料
                        UPDATE Barcode_PalletLable
                        SET Status = 4
                        WHERE USN = @ScanData;
                        --更新备料明细表中的累计备料量
                        UPDATE dbo.Barcode_SOShippingDetail
                        SET AllotQty = ISNULL(AllotQty, 0) + @xxbad_qty
                        WHERE ShipSN = @xxbad_ship_id
                              AND PurchaseOrder = @xxbad_order
                              AND Line = @xxbad_proline;
                    END;
                    ELSE
                    BEGIN
                        --重新获取 被解除的采购单和行号
                        SELECT @xxbad_purchacorder = PoNum,
                               @xxbad_line = PoLine
                        FROM [Barcode_OperateCache]
                        WHERE AppID = @interfaceid
                              AND ExtendedField1 = @xxbad_ship_id
                              AND OpUser = @xxbad_user
                              AND LableID = @ScanData;
                        --从托表中删除
                        DELETE [Barcode_OperateCache]
                        WHERE AppID = @interfaceid
                              AND ExtendedField1 = @xxbad_ship_id
                              AND OpUser = @xxbad_user
                              AND LableID = @ScanData;
                        --更新标签表 回滚标记
                        UPDATE Barcode_PalletLable
                        SET Status = 3
                        WHERE USN = @ScanData
                              AND Status = 4;

                        --减去备料明细表中的累计备料量
                        UPDATE dbo.Barcode_SOShippingDetail
                        SET AllotQty = ISNULL(AllotQty, 0) - @xxbad_qty
                        WHERE ShipSN = @xxbad_ship_id
                              AND PurchaseOrder = @xxbad_purchacorder
                              AND Line = @xxbad_line;
                        --清空部分界面
                        SET @xxbad_part = '';
                        SET @xxbad_scrapqty = '';
                        SET @xxbad_rj_qty = '';
                    END;
                    --重新获取刷新下备料量
                    SELECT TOP 1
                           @xxbad_rj_qty = AllotQty
                    FROM dbo.Barcode_SOShippingDetail
                    WHERE ShipSN = @xxbad_ship_id
                          AND PurchaseOrder = @xxbad_order
                          AND Line = @xxbad_proline;
                    --获取需要备料的下一行数据
                    SELECT TOP 1
                           @xxbad_order = PurchaseOrder,
                           @xxbad_proline = Line,
                           @xxbad_part = Item,
                           @xxbad_scrapqty = CurrentQty,
                           @xxbad_rj_qty = AllotQty
                    FROM dbo.Barcode_SOShippingDetail
                    WHERE ShipSN = @xxbad_ship_id
                          AND ISNULL(AllotQty, 0) < CurrentQty
                    ORDER BY PurchaseOrder,
                             Line;
                    --返回第一个dateset 到前台 将明细表备料第一行带出
                    SELECT @xxbad_ship_id xxbad_ship_id,
                           @xxbad_order xxbad_order,
                           @xxbad_proline xxbad_proline,
                           @xxbad_part xxbad_part,
                           @xxbad_scrapqty xxbad_scrapqty,
                           @xxbad_rj_qty xxbad_rj_qty;

                    --返回第二个dataset到前台 按照批次检索 前10行的箱标签
                    SELECT LableID USN,
                           CurrentLoc,
                           Qty,
                           ToLot Lot
                    FROM dbo.Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user;
                END;
            END;
        END;

        IF @interfaceid IN ( 10116 ) --新国外销售发运备料
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断托表中 是否有备料信息
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                          AND ExtendedField1 = @xxbad_ship_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前单据没有缓存的备料信息 !#No cached material information for the current document!', 11, 1);

                END;
                --判断所有的行 是否全部备料完成
                DECLARE @Unfinish10116 VARCHAR(2000);
                SELECT @Unfinish10116 = COALESCE(Item + '|' + Line, '')
                FROM dbo.Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                      AND ISNULL(AllotQty, 0) < CurrentQty;
                SET @ErrorMessage = N'ERROR_MESSAGE#' + @Unfinish10116 + N'未完成备料!#' + @Unfinish10116 + N'Unfinished material preparation!';
                IF ISNULL(@Unfinish10116, '') <> ''
                BEGIN
                    RAISERROR(@ErrorMessage, 11, 1);

                END;
                --获取发运模式
                SELECT @xxbad_toloc = SrmNum
                FROM Barcode_SOShippingMain
                WHERE SN = @xxbad_ship_id;
                --汇总计算每个
                SELECT SUM(CurrentQty) Qty,
                       PurchaseOrder,
                       Line
                INTO #temp110116
                FROM Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                GROUP BY PurchaseOrder,
                         Line;

                --更新销售订单中的发运总数量 中用使用销售计划
                --UPDATE a
                --SET a.sod_shipQty = ISNULL(a.sod_shipQty, 0)
                --                    + ISNULL(b.Qty, 0)
                --FROM sod_det a,
                --    #temp110082 b
                --WHERE a.sod_nbr = b.PurchaseOrder
                --      AND a.sod_line = b.Line;
                UPDATE a
                SET a.ShipQty = ISNULL(a.ShipQty, 0) + ISNULL(b.Qty, 0)
                FROM dbo.Barcode_ShipPlan a,
                     #temp110116 b
                WHERE a.ID = b.PurchaseOrder
                      AND a.Line = b.Line;
                --如果发运量大于计划量 则关闭发运计划
                UPDATE Barcode_ShipPlan
                SET Stauts = 0
                WHERE Stauts = 1
                      AND ShipQty >= PlanQty
                      AND ShipQty IS NOT NULL;
                --将托表中的标签 库位，状态，发运单 字段更新
                UPDATE dbo.Barcode_PalletLable
                SET CurrentLoc = @xxbad_toloc,
                    Status = 5,
                    FromLoc = CurrentLoc,
                    ShipSN = @xxbad_ship_id
                WHERE USN IN
                      (
                          SELECT LableID
                          FROM dbo.Barcode_OperateCache
                          WHERE AppID = @interfaceid
                                AND OpUser = @xxbad_user
                                AND ExtendedField1 = @xxbad_ship_id
                      );

                --将发运主表状态更改为已发运
                UPDATE dbo.Barcode_SOShippingMain
                SET Status = 2
                WHERE SN = @xxbad_ship_id;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    BarcodeInterFaceID,
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @xxbad_domain,
                       @interfaceid,
                       'PQ_SO_SHIPMNT',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       '',
                       b.PartNum,
                       dbo.GetQADloc(MAX(b.CurrentLoc)),
                       @xxbad_toloc,
                       MAX(b.Site),
                       MAX(b.Site),
                       @xxbad_ship_id,
                       @xxbad_id,
                       SUM(b.Qty),
                       b.Lot,
                       b.Lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM Barcode_OperateCache a,
                     dbo.Barocde_BoxlLable b
                WHERE a.LableID = b.PalletLable
                      AND AppID = @interfaceid
                      AND a.OpUser = @xxbad_user
                      AND a.ExtendedField1 = @xxbad_ship_id
                GROUP BY b.PartNum,
                         b.Lot;

                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'PQ_SO_SHIPMNT',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       b.USN,
                       @xxbad_user,
                       '',
                       '',
                       b.PartNum,
                       b.CurrentLoc,
                       @xxbad_toloc,
                       @xxbad_tosite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       b.Qty,
                       b.Lot,
                       b.Lot,
                       @xxbad_fromref,
                       @xxbad_toref
                FROM Barcode_OperateCache a,
                     dbo.Barocde_BoxlLable b
                WHERE a.LableID = b.PalletLable
                      AND a.AppID = @interfaceid
                      AND a.OpUser = @xxbad_user
                      AND a.ExtendedField1 = @xxbad_ship_id;
                --将每个FG小标签的状态 全部标记为已发运 放到后面 是因为到库位队列用到了
                UPDATE dbo.Barocde_BoxlLable
                SET Status = 5,
                    CurrentLoc = @xxbad_toloc
                WHERE PalletLable IN
                      (
                          SELECT LableID
                          FROM dbo.Barcode_OperateCache
                          WHERE AppID = @interfaceid
                                AND OpUser = @xxbad_user
                                AND ExtendedField1 = @xxbad_ship_id
                      );
                --清理缓存
                DELETE [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                RAISERROR(N'Info_MESSAGE#发运完成!#Shipment completed!', 11, 1);
            END;

            ELSE IF @ScanData = 'xxbad_ship_id'
            BEGIN
                --判断发运单是否合法
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_SOShippingMain
                    WHERE SN = @xxbad_ship_id
                          AND SupplierType = 0
                          AND Status = 1
                )
                BEGIN
                    SET @ErrorMessage = @xxbad_ship_id + N'ERROR_MESSAGE#销售单号不合法 !#Invalid sales order number!';
                    RAISERROR(@ErrorMessage, 11, 1);

                END;


                SELECT TOP 1
                       @xxbad_fromsite = sod_site,
                       @xxbad_tosite = sod_site,
                       @xxbad_part = Item,
                       @xxbad_scrapqty = CurrentQty,
                       @xxbad_rj_qty = ISNULL(AllotQty, 0)
                FROM dbo.Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                      AND ISNULL(AllotQty, 0) < CurrentQty
                ORDER BY Item,
                         Line;

                --返回第一个dateset 到前台 将明细表备料第一行带出
                SELECT @xxbad_ship_id xxbad_ship_id,
                       'xxbad_rj_qty' READONLY,
                       @xxbad_fromsite xxbad_fromsite,
                       @xxbad_part xxbad_part,
                       @xxbad_scrapqty xxbad_scrapqty,
                       @xxbad_rj_qty xxbad_rj_qty;
                --返回第二个dataset到前台 
                SELECT LableID USN,
                       CurrentLoc,
                       Qty,
                       ToLot Lot
                FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                ORDER BY ScanTime DESC;
            END;
            ELSE IF @ScanData = 'Next'
            BEGIN
                --获取需要备料的下一行数据
                SELECT @xxbad_part = Item,
                       @xxbad_scrapqty = CurrentQty,
                       @xxbad_rj_qty = AllotQty
                FROM dbo.Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                      AND ISNULL(AllotQty, 0) < CurrentQty
                ORDER BY NEWID() DESC;
                --返回第一个dateset 到前台 将明细表备料第一行带出
                SELECT @xxbad_ship_id xxbad_ship_id,
                       @xxbad_part xxbad_part,
                       @xxbad_scrapqty xxbad_scrapqty,
                       @xxbad_rj_qty xxbad_rj_qty;

                --返回第二个dataset到前台 按照批次检索 前10行的箱标签
                SELECT LableID USN,
                       CurrentLoc,
                       Qty,
                       ToLot Lot
                FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND PartNum = @xxbad_part
                      AND OpUser = @xxbad_user
                ORDER BY ScanTime DESC;
            END;
            ELSE IF @ScanData = 'UP'
            BEGIN
                --获取需要备料的下一行数据
                SELECT @xxbad_part = Item,
                       @xxbad_scrapqty = CurrentQty,
                       @xxbad_rj_qty = AllotQty
                FROM dbo.Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                      AND ISNULL(AllotQty, 0) < CurrentQty
                ORDER BY NEWID() ASC;
                --返回第一个dateset 到前台 将明细表备料第一行带出
                SELECT @xxbad_ship_id xxbad_ship_id,
                       @xxbad_part xxbad_part,
                       @xxbad_scrapqty xxbad_scrapqty,
                       @xxbad_rj_qty xxbad_rj_qty;

                --返回第二个dataset到前台 按照批次检索 前10行的箱标签
                SELECT LableID USN,
                       CurrentLoc,
                       Qty,
                       ToLot Lot
                FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND PartNum = @xxbad_part
                      AND OpUser = @xxbad_user
                ORDER BY ScanTime DESC;
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                --获取缓存中发运单号
                SELECT TOP 1
                       @xxbad_ship_id = ExtendedField1
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                GROUP BY ExtendedField1,
                         PoNum,
                         PoLine,
                         PartNum;
                --  根据发运单号获取  还没备料完成的第一行的记录  返回第一个dateset 到前台 
                SELECT TOP 1
                       ShipSN xxbad_ship_id,
                       Item xxbad_part,
                       AllotQty xxbad_rj_qty,
                       CurrentQty xxbad_scrapqty
                FROM dbo.Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                      AND ISNULL(AllotQty, 0) <= CurrentQty
                ORDER BY AllotQty ASC;
                --返回第二个dataset到前台 按照批次检索 前10行的箱标签
                SELECT LableID USN,
                       CurrentLoc,
                       Qty,
                       ToLot Lot
                FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;

            END;
            ELSE
            BEGIN
                --认为当前扫描的是销售单号
                SELECT @xxbad_id = USN,
                       @xxbad_lot = Lot,
                       @xxbad_qty = Qty,
                       @xxbad_desc = PartDescription,
                       @xxbad_part = PartNum,
                       @xxbad_loc = CurrentLoc
                FROM Barcode_PalletLable
                WHERE USN = @xxbad_id
                      AND
                      (
                          Status = 3
                          OR Status = 4
                      );
                IF (ISNULL(@xxbad_desc, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不正确!#Invalid tag!', 11, 1);

                END;
                --标签数量不能为空
                IF (ISNULL(@xxbad_qty, '0') = '0')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签数量不能为空!#The number of tags cannot be empty!', 11, 1);

                END;
                --判断零件是否可以从从库位移除
                SELECT @msg_error = dbo.CheckLocArea(@xxbad_part, @xxbad_loc, @interfaceid);
                IF ISNULL(@msg_error, '') <> ''
                BEGIN
                    RAISERROR(@msg_error, 11, 1);

                END;

                --判断当前客户的当前零件没有维护扩展信息
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.barcode_custompartset
                    WHERE partnum = @xxbad_part
                          AND customid =
                          (
                              SELECT TOP 1
                                     SupplierCode
                              FROM dbo.Barcode_SOShippingMain
                              WHERE SN = @xxbad_ship_id
                          )
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前客户的当前零件没有维护扩展信息!#No extended information is maintained for the current part of the current customer!', 11, 1);

                END;
                SELECT TOP 1
                       @xxbad_rj_qty = AllotQty,
                       @xxbad_scrapqty = CurrentQty
                FROM dbo.Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                      AND Item = @xxbad_part;
                --暂时不判断
                IF @xxbad_rj_qty = ''
                    SET @xxbad_rj_qty = 0;
                IF @xxbad_qty = ''
                    SET @xxbad_qty = 0;
                IF @xxbad_scrapqty = ''
                    SET @xxbad_scrapqty = 0;
                --判断当前原材料是否被被人缓存了
                SELECT TOP 1
                       @cacheuser = OpUser
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND LableID = @xxbad_id;
                IF (ISNULL(@cacheuser, @xxbad_user) <> @xxbad_user)
                BEGIN
                    SET @ErrorMessage
                        = N'ERROR_MESSAGE#该箱码被用户' + @cacheuser + N'扫描，请提醒其操作!#The box code has been scanned by user ' + @cacheuser + N'. Please remind them to take action!';
                    RAISERROR(@ErrorMessage, 11, 1);

                END;
                --判断是不是推荐的箱码
                CREATE TABLE #ResultLable10116
                (
                    USN NVARCHAR(50) NULL,
                    PartNum NVARCHAR(200) NULL,
                    Qty DECIMAL(18, 5) NULL,
                    CurrentLoc NVARCHAR(50) NULL
                );
                INSERT INTO #ResultLable10116
                EXEC dbo.GetSoFGlable @xxbad_ship_id;

                --如果在动态高速缓存表不存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                          AND ExtendedField1 = @xxbad_ship_id
                          AND LableID = @xxbad_id
                )
                BEGIN
                    IF NOT EXISTS (SELECT TOP 1 1 FROM #ResultLable10116 WHERE USN = @xxbad_id)
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#当前箱码不在推荐的列表中，不能出库!#The current box code is not on the recommended list and cannot be shipped out!', 11, 1);

                    END;
                    --判断单箱数量是否已经超量
                    IF CONVERT(DECIMAL(18, 5), @xxbad_qty) > CONVERT(DECIMAL(18, 5), @xxbad_scrapqty)
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#单箱数量已经超出本次发运量!#The quantity per box has exceeded the shipment quantity!', 11, 1);

                    END;
                    --判断是否超量备料
                    IF EXISTS
                    (
                        SELECT TOP 1
                               1
                        FROM Barcode_SOShippingDetail
                        WHERE ShipSN = @xxbad_ship_id
                              AND Item = @xxbad_part
                              AND ISNULL(AllotQty, 0) >= ISNULL(CurrentQty, 0)
                    )
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#不能超量备料!#Do not exceed the material limit!', 11, 1);

                    END;
                    --从标签中获取标签信息 插入动态高速缓存表
                    INSERT INTO [dbo].[Barcode_OperateCache]
                    (
                        [AppID],
                        [OpUser],
                        [LableID],
                        [PartNum],
                        [PartDescrition],
                        [Qty],
                        ToLot,
                        PoNum,
                        PoLine,
                        [FromLoc],
                        [CurrentLoc],
                        [ToLoc],
                        [FromSite],
                        [ToSite],
                        [ScanTime],
                        ExtendedField1
                    )
                    SELECT TOP 1
                           @interfaceid,
                           @xxbad_user,
                           @xxbad_id,
                           PartNum,
                           PartDescription,
                           Qty,
                           Lot,
                           @xxbad_order,
                           @xxbad_proline,
                           CurrentLoc,
                           CurrentLoc,
                           @xxbad_toloc,
                           @xxbad_fromsite,
                           @xxbad_fromsite,
                           GETDATE(),
                           @xxbad_ship_id
                    FROM dbo.Barcode_PalletLable
                    WHERE USN = @xxbad_id;

                    --更新标签表 标记标签已经备料
                    UPDATE Barcode_PalletLable
                    SET Status = 4
                    WHERE USN = @xxbad_id;
                    --更新备料明细表中的累计备料量
                    UPDATE dbo.Barcode_SOShippingDetail
                    SET AllotQty = ISNULL(AllotQty, 0) + @xxbad_qty
                    WHERE ShipSN = @xxbad_ship_id
                          AND Item = @xxbad_part;
                END;
                ELSE
                BEGIN
                    --重新获取 被解除的采购单和行号
                    SELECT @xxbad_purchacorder = PoNum,
                           @xxbad_line = PoLine
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND ExtendedField1 = @xxbad_ship_id
                          AND OpUser = @xxbad_user
                          AND LableID = @xxbad_id;
                    --从托表中删除
                    DELETE [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND ExtendedField1 = @xxbad_ship_id
                          AND OpUser = @xxbad_user
                          AND LableID = @xxbad_id;
                    --更新标签表 回滚标记
                    UPDATE Barcode_PalletLable
                    SET Status = 3
                    WHERE USN = @xxbad_id
                          AND Status = 4;

                    --减去备料明细表中的累计备料量
                    UPDATE dbo.Barcode_SOShippingDetail
                    SET AllotQty = ISNULL(AllotQty, 0) - @xxbad_qty
                    WHERE ShipSN = @xxbad_ship_id
                          AND Item = @xxbad_part;
                    --清空部分界面
                    SET @xxbad_part = '';
                    SET @xxbad_scrapqty = '';
                    SET @xxbad_rj_qty = '';
                END;
                --重新获取刷新下备料量
                SELECT TOP 1
                       @xxbad_rj_qty = AllotQty
                FROM dbo.Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                      AND Item = @xxbad_part;

                --获取需要备料的下一行数据
                SELECT TOP 1
                       @xxbad_part = Item,
                       @xxbad_scrapqty = CurrentQty,
                       @xxbad_rj_qty = AllotQty
                FROM dbo.Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                      AND ISNULL(AllotQty, 0) < CurrentQty
                ORDER BY PurchaseOrder,
                         Line;
                --返回第一个dateset 到前台 将明细表备料第一行带出
                SELECT @xxbad_ship_id xxbad_ship_id,
                       @xxbad_part xxbad_part,
                       @xxbad_scrapqty xxbad_scrapqty,
                       @xxbad_rj_qty xxbad_rj_qty;

                --返回第二个dataset到前台 按照批次检索 前10行的箱标签
                SELECT LableID USN,
                       CurrentLoc,
                       Qty,
                       ToLot Lot
                FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                ORDER BY ScanTime DESC;
            END;
        END;
        IF @interfaceid IN ( 10038 ) --FG盘点采集条码
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                SELECT 1;
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_toloc' focus;
            END;
            ELSE IF @ScanData = 'xxbad_toloc'
            BEGIN
                --判断库位是否存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_Location
                    WHERE xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#库位不存在!#Location does not exist!', 11, 1);

                END;
                --返回第一个dateset 到前台
                SELECT @xxbad_toloc xxbad_toloc;
            END;
            ELSE
            BEGIN
                --从标签中加载信息  并且判断标签状态
                SELECT @xxbad_id = USN,
                       @xxbad_part = PartNum,
                       @xxbad_qty = Qty,
                       @xxbad_lot = Lot,
                       @xxbad_loc = CurrentLoc
                FROM Barocde_BoxlLable
                WHERE USN = @xxbad_id
                      AND Status = 3;
                IF (ISNULL(@xxbad_id, '') = '')
                BEGIN
                    --插入盘盈标签
                    INSERT INTO [dbo].[Barcode_CheckStock]
                    (
                        [Site],
                        [Loc],
                        FromLoc,
                        [USN],
                        [LableType],
                        [PartNum],
                        [lot],
                        [Ref],
                        [Qty],
                        [ModifyUser],
                        [ModifyTime],
                        CheckStatus,
                        PartDescription,
                        pt_um,
                        pt_desc2
                    )
                    SELECT @xxbad_site,
                           @xxbad_loc,
                           '',
                           @xxbad_id,
                           0,
                           @xxbad_part,
                           @xxbad_lot,
                           '',
                           0,
                           @xxbad_user,
                           GETDATE(),
                           1,
                           @xxbad_desc,
                           pt_um,
                           pt_desc2
                    FROM dbo.pt_mstr
                    WHERE pt_part = @xxbad_part;
                    RAISERROR(N'ERROR_MESSAGE#盘盈标签，请单独摆放!#Surplus label, please place separately!', 11, 1);
                END;
                --判断标签库位和盘点库位是否一致   ,不一致提醒前台用户
                IF (ISNULL(@xxbad_loc, '') <> @xxbad_toloc)
                BEGIN
                    SET @ErrorMessage = N'ERROR_MESSAGE#源库位是' + @xxbad_loc + N',与盘点库位不一致!#The source location is ' + @xxbad_loc + N', which is inconsistent with the inventory location!';
                    RAISERROR(@ErrorMessage, 11, 1);
                END;
                --判断标签是否 已经被盘点 并且提醒被盘点人
                DECLARE @checkuser VARCHAR(50);
                SELECT @checkuser = ModifyUser
                FROM Barcode_CheckStock
                WHERE USN = @xxbad_id
                      AND LableType = 0
                      AND DATEDIFF(WEEK, ModifyTime, GETDATE()) = 0;
                IF (ISNULL(@checkuser, '') <> '')
                BEGIN
                    SET @ErrorMessage = N'ERROR_MESSAGE#标签已经被' + @checkuser + N'盘点!#The tag has already been inventoried by ' + @checkuser + N'!';
                    RAISERROR(@ErrorMessage, 11, 1);

                END;

                --从标签中获取标签信息 插入表
                INSERT INTO [dbo].[Barcode_CheckStock]
                (
                    [Site],
                    [Loc],
                    FromLoc,
                    [USN],
                    [LableType],
                    [PartNum],
                    [lot],
                    [Ref],
                    [Qty],
                    [ModifyUser],
                    [ModifyTime],
                    PartDescription,
                    pt_um,
                    pt_desc2
                )
                SELECT TOP 1
                       @xxbad_site,
                       @xxbad_toloc,
                       CurrentLoc,
                       USN,
                       0,
                       PartNum,
                       Lot,
                       '',
                       Qty,
                       @xxbad_user,
                       GETDATE(),
                       PartDescription,
                       (
                           SELECT TOP 1
                                  pt_um
                           FROM dbo.pt_mstr
                           WHERE pt_part = Barocde_BoxlLable.PartNum
                       ),
                       ExtendFiled2
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;

                --返回第一个dataset到前台
                SELECT TOP 1
                       PartNum xxbad_part,
                       '' xxbad_id,
                       Qty xxbad_qty,
                       @xxbad_toloc xxbad_toloc,
                       lot xxbad_lot,
                       Loc xxbad_loc
                FROM Barcode_CheckStock
                WHERE USN = @xxbad_id;

                --返回当前库位下面的标签 第二个dataset
                SELECT USN,
                       PartNum
                FROM Barcode_CheckStock
                WHERE Loc = @xxbad_toloc
                      AND DATEDIFF(MONTH, ModifyTime, GETDATE()) = 0;
            END;
        END;

        IF @interfaceid IN ( 10094 ) --托标签盘点
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                SELECT 1;
            END;

            ELSE IF @ScanData = 'xxbad_toloc'
            BEGIN
                --判断库位是否存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_Location
                    WHERE xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#库位不存在!#Location does not exist!', 11, 1);

                END;
                --返回第一个dateset 到前台
                SELECT @xxbad_toloc xxbad_toloc,
                       'xxbad_id' focus;
            END;
            ELSE
            BEGIN

                --从标签中加载信息  并且判断标签状态
                SELECT @xxbad_id = USN,
                       @xxbad_part = PartNum,
                       @xxbad_qty = Qty,
                       @xxbad_lot = Lot,
                       @xxbad_loc = CurrentLoc
                FROM dbo.Barcode_PalletLable
                WHERE USN = @xxbad_id
                      AND Status = 3;
                IF (ISNULL(@xxbad_id, '') = '')
                BEGIN
                    --插入盘盈标签
                    INSERT INTO [dbo].[Barcode_CheckStock]
                    (
                        [Site],
                        [Loc],
                        FromLoc,
                        [USN],
                        [LableType],
                        [PartNum],
                        [lot],
                        [Ref],
                        [Qty],
                        [ModifyUser],
                        [ModifyTime],
                        CheckStatus,
                        PartDescription,
                        pt_um
                    )
                    SELECT @xxbad_site,
                           @xxbad_loc,
                           '',
                           @xxbad_id,
                           2,
                           @xxbad_part,
                           0,
                           '',
                           0,
                           @xxbad_user,
                           GETDATE(),
                           1,
                           @xxbad_desc,
                           pt_um
                    FROM dbo.pt_mstr
                    WHERE pt_part = @xxbad_part;
                    RAISERROR(N'ERROR_MESSAGE#盘盈标签，请单独摆放!#Surplus label, please place separately!', 11, 1);
                END;
                --判断标签库位和盘点库位是否一致   ,不一致提醒前台用户
                IF (ISNULL(@xxbad_loc, '') <> @xxbad_toloc)
                BEGIN
                    SET @ErrorMessage = N'ERROR_MESSAGE#源库位是' + @xxbad_loc + N',与盘点库位不一致!#The source location is ' + @xxbad_loc + N', which is inconsistent with the inventory location!';
                    RAISERROR(@ErrorMessage, 11, 1);
                END;
                --判断标签是否 已经被盘点 并且提醒被盘点人
                DECLARE @checkuser10094 VARCHAR(50);
                SELECT @checkuser10094 = ModifyUser
                FROM Barcode_CheckStock
                WHERE USN = @xxbad_id
                      AND LableType = 0
                      AND DATEDIFF(MONTH, ModifyTime, GETDATE()) = 0;
                IF (ISNULL(@checkuser10094, '') <> '')
                BEGIN
                    SET @ErrorMessage = N'ERROR_MESSAGE#标签已经被' + @checkuser10094 + N'盘点!#The tag has already been inventoried by ' + @checkuser10094 + N'!';
                    RAISERROR(@ErrorMessage, 11, 1);

                END;

                --从标签中获取标签信息 插入表
                INSERT INTO [dbo].[Barcode_CheckStock]
                (
                    [Site],
                    [Loc],
                    FromLoc,
                    [USN],
                    [LableType],
                    [PartNum],
                    [lot],
                    [Ref],
                    [Qty],
                    [ModifyUser],
                    [ModifyTime],
                    PartDescription,
                    pt_um
                )
                SELECT TOP 1
                       Site,
                       @xxbad_toloc,
                       CurrentLoc,
                       USN,
                       0,
                       PartNum,
                       0,
                       '',
                       Qty,
                       @xxbad_user,
                       GETDATE(),
                       PartDescription,
                       (
                           SELECT TOP 1
                                  pt_um
                           FROM dbo.pt_mstr
                           WHERE pt_part = Barcode_PalletLable.PartNum
                       )
                FROM dbo.Barcode_PalletLable
                WHERE USN = @xxbad_id;

                --返回第一个dataset到前台
                SELECT TOP 1
                       PartNum xxbad_part,
                       USN xxbad_id,
                       Qty xxbad_qty,
                       @xxbad_toloc xxbad_toloc,
                       lot xxbad_lot,
                       Loc xxbad_loc
                FROM Barcode_CheckStock
                WHERE USN = @xxbad_id;

                --返回当前库位下面的标签 第二个dataset
                SELECT USN,
                       PartNum
                FROM Barcode_CheckStock
                WHERE Loc = @xxbad_toloc
                      AND DATEDIFF(MONTH, ModifyTime, GETDATE()) = 0;
            END;
        END;

        IF @interfaceid IN ( 10040 ) --RM盘点采集条码
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit' --功能功已经废弃
            BEGIN
                --将本次盘点的标签数量更改为最新的  标记为盘盈
                UPDATE [Barcode_CheckStock]
                SET CheckQty = CONVERT(DECIMAL(18, 5), @xxbad_rj_qty),
                    CheckStatus = 1
                WHERE USN = @xxbad_id
                      AND DATEDIFF(MONTH, ModifyTime, GETDATE()) = 0
                      AND ISNULL(@xxbad_rj_qty, 0) > Qty;
                --标记为盘亏
                UPDATE [Barcode_CheckStock]
                SET CheckQty = CONVERT(DECIMAL(18, 5), @xxbad_rj_qty),
                    CheckStatus = 2
                WHERE USN = @xxbad_id
                      AND DATEDIFF(MONTH, ModifyTime, GETDATE()) = 0
                      AND ISNULL(@xxbad_rj_qty, 0) < Qty;
                RAISERROR(N'ERROR_MESSAGE#标签数量修改成功!#Tag quantity successfully modified!', 11, 1);
            END;

            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_toloc' focus;
            END;
            ELSE IF @ScanData = 'xxbad_toloc'
            BEGIN
                --判断库位是否存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_Location
                    WHERE xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#库位不存在!#Location does not exist!', 11, 1);

                END;
                --限制盘点库位  必须是 盘点单中的库位

                --返回第一个dateset 到前台
                SELECT @xxbad_toloc xxbad_toloc,
                       'xxbad_id' focus;
            END;
            ELSE
            BEGIN
                --从标签中加载信息  并且判断标签状态
                SELECT @xxbad_id = usn,
                       @xxbad_part = partnum,
                       @xxbad_qty = qty,
                       @xxbad_lot = lot,
                       @xxbad_status = status,
                       @xxbad_desc = partdescription,
                       @xxbad_loc = currentloc
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
                PRINT @xxbad_id;
                --AND Status = 4;
                IF (ISNULL(@xxbad_id, '') = '')
                BEGIN
                    --插入盘盈标签
                    INSERT INTO [dbo].[Barcode_CheckStock]
                    (
                        [Site],
                        [Loc],
                        FromLoc,
                        [USN],
                        [LableType],
                        [PartNum],
                        [lot],
                        [Ref],
                        [Qty],
                        [ModifyUser],
                        [ModifyTime],
                        CheckStatus,
                        PartDescription,
                        pt_um,
                        pt_desc2
                    )
                    SELECT @xxbad_site,
                           @xxbad_loc,
                           '',
                           @xxbad_id,
                           1,
                           @xxbad_part,
                           @xxbad_lot,
                           '',
                           0,
                           @xxbad_user,
                           GETDATE(),
                           1,
                           @xxbad_desc,
                           pt_um,
                           pt_desc2
                    FROM dbo.pt_mstr
                    WHERE pt_part = @xxbad_part;
                    RAISERROR(N'ERROR_MESSAGE#盘盈标签，请单独摆放!#Surplus label, please place separately!', 11, 1);
                END;
                --判断标签在不在货架上
                IF (ISNULL(@xxbad_status, '') <> '4')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不在货架上!#The label is not on the shelf!', 11, 1);

                END;
                --判断标签库位和盘点库位是否一致   ,不一致提醒前台用户
                IF (ISNULL(@xxbad_loc, '') <> @xxbad_toloc)
                BEGIN
                    SET @ErrorMessage = N'ERROR_MESSAGE#源库位是' + @xxbad_loc + N',与盘点库位不一致!#The source location is ' + @xxbad_loc + N', which is inconsistent with the inventory location!';
                    RAISERROR(@ErrorMessage, 11, 1);
                END;

                --判断标签是否 已经被盘点 并且提醒被盘点人
                DECLARE @checkuser10040 VARCHAR(50);
                SELECT @checkuser10040 = ModifyUser
                FROM Barcode_CheckStock
                WHERE USN = @xxbad_id
                      AND DATEDIFF(MONTH, ModifyTime, GETDATE()) = 0;
                IF (ISNULL(@checkuser10040, '') <> '')
                BEGIN
                    SET @ErrorMessage = N'ERROR_MESSAGE#标签已经被' + @checkuser10040 + N'盘点!#The tag has already been inventoried by ' + @checkuser10040 + N'!';
                    RAISERROR(@ErrorMessage, 11, 1);

                END;

                --从标签中获取标签信息 插入表
                INSERT INTO [dbo].[Barcode_CheckStock]
                (
                    [Site],
                    [Loc],
                    FromLoc,
                    [USN],
                    [LableType],
                    [PartNum],
                    [lot],
                    [Ref],
                    [Qty],
                    [ModifyUser],
                    [ModifyTime],
                    CheckStatus,
                    PartDescription,
                    pt_um,
                    pt_desc2
                )
                SELECT TOP 1
                       @xxbad_site,
                       @xxbad_toloc,
                       currentloc,
                       usn,
                       1,
                       partnum,
                       lot,
                       '',
                       qty,
                       @xxbad_user,
                       GETDATE(),
                       0,
                       partdescription,
                       (
                           SELECT TOP 1
                                  pt_um
                           FROM dbo.pt_mstr
                           WHERE pt_part = barocde_materiallable.partnum
                       ),
                       pt_desc2
                FROM dbo.barocde_materiallable
                WHERE USN = @xxbad_id;

                --返回第一个dataset到前台
                SELECT TOP 1
                       PartNum xxbad_part,
                       '' xxbad_id,
                       Qty xxbad_qty,
                       Qty xxbad_rj_qty,
                       @xxbad_toloc xxbad_toloc,
                       lot xxbad_lot,
                       Loc xxbad_loc,
                       'xxbad_rj_qty' READONLY,
                       PartDescription xxbad_desc
                FROM Barcode_CheckStock
                WHERE USN = @xxbad_id;

                --返回当前库位下面的标签 第二个dataset
                SELECT USN,
                       PartNum
                FROM Barcode_CheckStock
                WHERE Loc = @xxbad_toloc
                      AND DATEDIFF(MONTH, ModifyTime, GETDATE()) = 0;
            END;
        END;

        IF @interfaceid IN ( 10041 ) --通用盘点采集条码
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit' --功能功已经废弃
            BEGIN
                --将本次盘点的标签数量更改为最新的  标记为盘盈
                UPDATE [Barcode_CheckStock]
                SET CheckQty = CONVERT(DECIMAL(18, 5), @xxbad_rj_qty),
                    CheckStatus = 1
                WHERE USN = @xxbad_id
                      AND DATEDIFF(MONTH, ModifyTime, GETDATE()) = 0
                      AND ISNULL(@xxbad_rj_qty, 0) > Qty;
                --标记为盘亏
                UPDATE [Barcode_CheckStock]
                SET CheckQty = CONVERT(DECIMAL(18, 5), @xxbad_rj_qty),
                    CheckStatus = 2
                WHERE USN = @xxbad_id
                      AND DATEDIFF(MONTH, ModifyTime, GETDATE()) = 0
                      AND ISNULL(@xxbad_rj_qty, 0) < Qty;
                RAISERROR(N'ERROR_MESSAGE#标签数量修改成功!#Tag quantity successfully modified!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_toloc' focus;
            END;
            ELSE IF @ScanData = 'xxbad_ship_id'
            BEGIN
                --判断库位是否存在

                --返回第一个dateset 到前台
                SELECT @xxbad_ship_id xxbad_ship_id,
                       'xxbad_toloc' focus;
            END;
            ELSE IF @ScanData = 'xxbad_toloc'
            BEGIN
                --判断库位是否存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM checkloc
                    WHERE loc = @xxbad_toloc
                          AND plannum = @xxbad_ship_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#库位不在本次盘点单中!#The storage location is not included in this inventory list!', 11, 1);

                END;
                --返回第一个dateset 到前台
                SELECT @xxbad_toloc xxbad_toloc,
                       @xxbad_ship_id xxbad_ship_id,
                       'xxbad_id' focus;
                SELECT 1;
            END;
            ELSE
            BEGIN
                --  盘点当前盘点单 是否是关闭状态
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM checkpaper
                    WHERE sn = @xxbad_ship_id
                          AND status = 0
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#本盘点单已经关闭，不能继续盘点了!#This inventory list has been closed and cannot be continued!', 11, 1);
                END;
                SET @xxbad_loc = '';
                --从标签中加载信息  并且判断标签状态
                SELECT @xxbad_id = usn,
                       @xxbad_part = partnum,
                       @xxbad_qty = qty,
                       @xxbad_lot = lot,
                       @xxbad_type = '1', --代表原材料
                       @xxbad_status = status,
                       @xxbad_desc = partdescription,
                       @xxbad_loc = currentloc
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
                PRINT @xxbad_id;
                --如果没有从原材料表中获取 则尝试从成品表获取
                IF (ISNULL(@xxbad_loc, '') = '')
                BEGIN
                    SELECT @xxbad_id = USN,
                           @xxbad_part = PartNum,
                           @xxbad_qty = Qty,
                           @xxbad_lot = Lot,
                           @xxbad_type = '0', --代表产成品
                           @xxbad_status = Status,
                           @xxbad_desc = PartDescription,
                           @xxbad_loc = CurrentLoc
                    FROM dbo.Barocde_BoxlLable
                    WHERE USN = @xxbad_id;
                END;
                --如果没有获取到标签库位  则认为是盘盈标签
                IF (ISNULL(@xxbad_loc, '') = '')
                BEGIN
                    --插入盘盈标签
                    INSERT INTO [dbo].[Barcode_CheckStock]
                    (
                        [Site],
                        [Loc],
                        FromLoc,
                        [USN],
                        [LableType],
                        [PartNum],
                        [lot],
                        [Ref],
                        [Qty],
                        [ModifyUser],
                        [ModifyTime],
                        CheckStatus,
                        PartDescription,
                        pt_um,
                        pt_desc2,
                        plannum
                    )
                    SELECT @xxbad_site,
                           @xxbad_loc,
                           '',
                           @xxbad_id,
                           1,
                           @xxbad_part,
                           @xxbad_lot,
                           '',
                           0,
                           @xxbad_user,
                           GETDATE(),
                           1,
                           @xxbad_desc,
                           pt_um,
                           pt_desc2,
                           @xxbad_ship_id
                    FROM dbo.pt_mstr
                    WHERE pt_part = @xxbad_part;
                    RAISERROR(N'ERROR_MESSAGE#盘盈标签，请单独摆放!#Surplus label, please place separately!', 11, 1);
                END;
                --判断标签在不在货架上
                --IF (ISNULL(@xxbad_status, '') <> '4')
                --BEGIN
                --    RAISERROR(N'ERROR_MESSAGE#标签不在货架上!#The label is not on the shelf!', 11, 1);

                --END;
                --判断标签库位和盘点库位是否一致   ,不一致提醒前台用户
                IF (ISNULL(@xxbad_loc, '') <> @xxbad_toloc)
                BEGIN
                    SET @ErrorMessage = N'ERROR_MESSAGE#源库位是' + @xxbad_loc + N',与盘点库位不一致!#The source location is ' + @xxbad_loc + N', which is inconsistent with the inventory location!';
                    RAISERROR(@ErrorMessage, 11, 1);
                END;

                --判断标签是否 已经被盘点 并且提醒被盘点人
                DECLARE @checkuser10041 VARCHAR(50);
                SELECT @checkuser10041 = ModifyUser
                FROM Barcode_CheckStock
                WHERE USN = @xxbad_id
                      AND plannum = @xxbad_ship_id;
                IF (ISNULL(@checkuser10041, '') <> '')
                BEGIN
                    SET @ErrorMessage = N'ERROR_MESSAGE#标签已经被' + @checkuser10041 + N'盘点!#The tag has already been inventoried by ' + @checkuser10041 + N'!';
                    RAISERROR(@ErrorMessage, 11, 1);

                END;

                --从标签中获取标签信息 插入表
                IF (@xxbad_type = '1')
                BEGIN
                    INSERT INTO [dbo].[Barcode_CheckStock]
                    (
                        [Site],
                        [Loc],
                        FromLoc,
                        [USN],
                        [LableType],
                        [PartNum],
                        [lot],
                        [Ref],
                        [Qty],
                        [ModifyUser],
                        [ModifyTime],
                        CheckStatus,
                        PartDescription,
                        pt_um,
                        plannum,
                        pt_desc2
                    )
                    SELECT TOP 1
                           @xxbad_site,
                           @xxbad_toloc,
                           currentloc,
                           usn,
                           1,
                           partnum,
                           lot,
                           '',
                           qty,
                           @xxbad_user,
                           GETDATE(),
                           CASE
                               WHEN @xxbad_toloc = currentloc THEN
                                   0
                               ELSE
                                   3
                           END,
                           partdescription,
                           (
                               SELECT TOP 1
                                      pt_um
                               FROM dbo.pt_mstr
                               WHERE pt_part = barocde_materiallable.partnum
                           ),
                           @xxbad_ship_id,
                           pt_desc2
                    FROM dbo.barocde_materiallable
                    WHERE USN = @xxbad_id;
                END;
                ELSE
                BEGIN
                    INSERT INTO [dbo].[Barcode_CheckStock]
                    (
                        [Site],
                        [Loc],
                        FromLoc,
                        [USN],
                        [LableType],
                        [PartNum],
                        [lot],
                        [Ref],
                        [Qty],
                        [ModifyUser],
                        [ModifyTime],
                        CheckStatus,
                        PartDescription,
                        pt_um,
                        plannum,
                        pt_desc2
                    )
                    SELECT TOP 1
                           @xxbad_site,
                           @xxbad_toloc,
                           CurrentLoc,
                           USN,
                           0,
                           PartNum,
                           Lot,
                           '',
                           Qty,
                           @xxbad_user,
                           GETDATE(),
                           CASE
                               WHEN @xxbad_toloc = CurrentLoc THEN
                                   0
                               ELSE
                                   3
                           END,
                           PartDescription,
                           (
                               SELECT TOP 1
                                      pt_um
                               FROM dbo.pt_mstr
                               WHERE pt_part = Barocde_BoxlLable.PartNum
                           ),
                           @xxbad_ship_id,
                           ExtendFiled2
                    FROM dbo.Barocde_BoxlLable
                    WHERE USN = @xxbad_id;
                END;
                --返回第一个dataset到前台
                SELECT TOP 1
                       PartNum xxbad_part,
                       '' xxbad_id,
                       Qty xxbad_qty,
                       Qty xxbad_rj_qty,
                       @xxbad_toloc xxbad_toloc,
                       lot xxbad_lot,
                       Loc xxbad_loc,
                       @xxbad_ship_id xxbad_ship_id,
                       (
                           SELECT COUNT(1)
                           FROM Barcode_CheckStock
                           WHERE plannum = @xxbad_ship_id
                                 AND Loc = @xxbad_toloc
                       ) total,
                       @xxbad_ship_id xxbad_ship_id,
                       'xxbad_rj_qty' READONLY,
                       PartDescription xxbad_desc
                FROM Barcode_CheckStock
                WHERE USN = @xxbad_id;

                --返回当前库位下面的标签 第二个dataset
                SELECT USN,
                       PartNum
                FROM Barcode_CheckStock
                WHERE Loc = @xxbad_toloc
                      AND plannum = @xxbad_ship_id;
            END;
        END;


        IF @interfaceid IN ( 10058 ) --RM复盘采集条码
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                SELECT 1;
            END;

            ELSE
            BEGIN
                --处理数据扫描模块 如果盘点库位为空，认为当前扫描的是盘点库位
                IF ISNULL(@xxbad_toloc, '') = ''
                BEGIN
                    --判断库位是否存在
                    IF NOT EXISTS
                    (
                        SELECT TOP 1
                               1
                        FROM Barcode_Location
                        WHERE xxlocation_loc = @ScanData
                    )
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#库位不存在!#Location does not exist!', 11, 1);

                    END;
                    SET @xxbad_toloc = @ScanData;
                    --返回第一个dateset 到前台
                    SELECT @xxbad_toloc xxbad_toloc;
                END;
                ELSE
                BEGIN --处理扫描的盘点条码

                    --从历史盘点记录中 加载信息
                    SELECT @xxbad_id = USN,
                           @xxbad_part = PartNum,
                           @xxbad_qty = Qty,
                           @xxbad_lot = lot,
                           @xxbad_loc = Loc
                    FROM dbo.Barcode_CheckStock
                    WHERE USN = @ScanData;
                    --判断有无盘点记录
                    IF ISNULL(@xxbad_id, '') = ''
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#标签无盘点记录!#No inventory records for the tag!', 11, 1);

                    END;
                    --更新复盘人，库位，等信息
                    UPDATE Barcode_CheckStock
                    SET Loc = @xxbad_toloc,
                        CheckUser = @xxbad_user,
                        CheckTime = GETDATE(),
                        CheckMemo = '库位调整从' + @xxbad_loc + '到' + @xxbad_toloc
                    WHERE USN = @ScanData;

                    --返回第一个dataset到前台
                    SELECT TOP 1
                           PartNum xxbad_part,
                           USN xxbad_id,
                           Qty xxbad_qty,
                           lot xxbad_lot,
                           @xxbad_loc xxbad_loc
                    FROM Barcode_CheckStock
                    WHERE USN = @ScanData;

                    --返回当前库位下面的标签 第二个dataset
                    SELECT USN,
                           PartNum
                    FROM Barcode_CheckStock
                    WHERE Loc = @xxbad_toloc;
                END;
            END;
        END;

        IF @interfaceid IN ( 10042 ) --原材料标签数量调整
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --插入库存日志表 记录是谁调整的
                INSERT INTO [dbo].[barcode_stocklog]
                (
                    [site],
                    [loc],
                    [partnum],
                    [lot],
                    [ref],
                    [changeqty],
                    [changeuser],
                    [changetime],
                    [lastqty],
                    [currentqty],
                    queueid
                )
                SELECT site,
                       currentloc,
                       partnum,
                       lot,
                       '',
                       @xxbad_qty,
                       @xxbad_user,
                       GETDATE(),
                       qty,
                       @xxbad_qty,
                       10042
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id
                      AND status = 4;
                --更改标签表中的数量
                UPDATE barocde_materiallable
                SET qty = @xxbad_qty
                WHERE usn = @xxbad_id
                      AND status = 4;

                RAISERROR(N'Info_MESSAGE#提交成功!#Submission successful!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 1;
                SELECT 1;
            END;
            ELSE IF @ScanData = 'ComboBox'
            BEGIN
                SELECT 1;
                SELECT 1;

            END;
            ELSE --认为处理扫描标签数据
            BEGIN
                --取出扫描的标签信息
                SELECT @xxbad_part = partnum,
                       @xxbad_qty = qty,
                       @xxbad_id = usn,
                       @xxbad_desc = partdescription,
                       @xxbad_loc = currentloc
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id
                      AND status = 4;
                --判断标签是否合法
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    RAISERROR(N'Info_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                --返回第一个dataset 到前台
                SELECT @xxbad_part xxbad_part,
                       @xxbad_qty xxbad_qty,
                       'xxbad_qty' READONLY,
                       @xxbad_id xxbad_id,
                       @xxbad_desc xxbad_desc,
                       @xxbad_loc xxbad_loc;
            END;
        END;
        IF @interfaceid IN ( 10070 ) --成品标签数量调整
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --插入库存日志表 记录是谁调整的
                INSERT INTO [dbo].[barcode_stocklog]
                (
                    [site],
                    [loc],
                    [partnum],
                    [lot],
                    [ref],
                    [changeqty],
                    [changeuser],
                    [changetime],
                    [lastqty],
                    [currentqty],
                    queueid
                )
                SELECT Site,
                       CurrentLoc,
                       PartNum,
                       Lot,
                       '',
                       @xxbad_qty,
                       @xxbad_user,
                       GETDATE(),
                       Qty,
                       @xxbad_qty,
                       10042
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id
                      AND Status = 3;
                --更改标签表中的数量
                UPDATE Barocde_BoxlLable
                SET Qty = @xxbad_qty
                WHERE USN = @xxbad_id
                      AND Status = 3;

                RAISERROR(N'Info_MESSAGE#提交成功!#Submission successful!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 1;
                SELECT 1;
            END;
            ELSE IF @ScanData = 'ComboBox'
            BEGIN
                SELECT 1;
                SELECT 1;
            END;
            ELSE --认为处理扫描标签数据
            BEGIN
                --取出扫描的标签信息
                SELECT @xxbad_part = PartNum,
                       @xxbad_qty = Qty,
                       @xxbad_id = USN,
                       @xxbad_desc = PartDescription,
                       @xxbad_loc = CurrentLoc
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id
                      AND Status = 3;
                --判断标签是否合法
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    RAISERROR(N'Info_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                --返回第一个dataset 到前台
                SELECT @xxbad_part xxbad_part,
                       @xxbad_qty xxbad_qty,
                       'xxbad_qty' READONLY,
                       @xxbad_id xxbad_id,
                       @xxbad_desc xxbad_desc,
                       @xxbad_loc xxbad_loc;
            END;
        END;
        IF @interfaceid IN ( 10046 ) --原材料计划外出库 
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断计划外出库号是不是为空
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.barocde_materiallable
                    WHERE usn = @xxbad_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#没有扫描箱标签，请先扫描箱标签!#No box label scanned. Please scan the box label first!', 11, 1);

                END;
                --判断原因代码是否为空
                IF ISNULL(@xxbad_emp, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#原因代码不能为空!#The reason code cannot be empty!', 11, 1);
                END;
                --判断有没有输入本次领用量
                IF ISNULL(@xxbad_extension2, '0') = '0'
                   OR @xxbad_extension2 = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请扫描标签，然后输入本次领用量!#Please scan the label and then enter the quantity for this usage!', 11, 1);

                END;
                --判断本次领用量是不是大于标签数量
                IF CONVERT(DECIMAL(18, 5), @xxbad_extension2) > CONVERT(DECIMAL(18, 5), @xxbad_qty)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#不能大于本箱的总数量!#Cannot exceed the total quantity of this box!', 11, 1);

                END;

                --判断本次领用量 有没有超出计划量
                IF CONVERT(DECIMAL(18, 5), @xxbad_extension2) > CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_rj_qty, 0))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#本次领用量不能超出计划量!#The amount for this requisition cannot exceed the planned quantity!', 11, 1);

                END;
                IF ISNULL(@xxbad_ship_id, '') = ''
                   AND ISNULL(@xxbad_purchacorder, '') <> ''
                BEGIN
                    SELECT @xxbad_ship_id = SN
                    FROM dbo.Barcode_UsingRequest
                    WHERE ID = @xxbad_purchacorder;
                END;

                --判断计划外出库号是不是为空
                IF ISNULL(@xxbad_ship_id, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#计划外出库号不能为空，请重新选择!#The unplanned outbound number cannot be empty. Please select again!', 11, 1);

                END;
                --获取部门
                SELECT TOP 1
                       @xxbad_rmks = sys_depart.org_code
                FROM dbo.Barcode_UsingRequest
                    LEFT JOIN dbo.sys_depart
                        ON sys_depart.id = Barcode_UsingRequest.Depart
                WHERE SN = @xxbad_ship_id;

                IF ISNULL(@xxbad_emp, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#原因代码不能为空，请检查!#The reason code cannot be empty, please check!', 11, 1);

                END;
                --判断是否超出需求量
                IF CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_rj_qty, '0')) < (CONVERT(
                                                                                     DECIMAL(18, 5),
                                                                                     ISNULL(@xxbad_extension2, '0')
                                                                                 )
                                                                          + CONVERT(
                                                                                       DECIMAL(18, 5),
                                                                                       ISNULL(@xxbad_extension3, '0')
                                                                                   )
                                                                         )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前零件超出需求量!#The current part exceeds the required quantity!', 11, 1);

                END;
                --判断零件号 是否和当前标签号的零件号匹配
                SELECT @xxbad_extension5 = partnum,
                       @xxbad_lot = lot,
                       @xxbad_fromloc = currentloc
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id
                      AND status = 4;
                IF ISNULL(@xxbad_extension5, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不存在!#Tag does not exist!', 11, 1);

                END;
                IF ISNULL(@xxbad_extension5, '') <> @xxbad_part
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#零件号不匹配!#Part number mismatch!', 11, 1);

                END;

                --判断累计领用量 有没有超出计划量
                DECLARE @SumAllot DECIMAL(18, 5);
                SELECT @SumAllot = ISNULL(AllotQty, 0) + CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0'))
                FROM Barcode_Using_Detail
                WHERE SN = @xxbad_ship_id
                      AND PartNum = @xxbad_part;
                IF @SumAllot > CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_rj_qty, 0))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#累计领用量不能超出计划量!#The cumulative usage cannot exceed the planned amount!', 11, 1);

                END;
                --消耗类型 需要判断库存是否足够
                SELECT @ErrorMessage
                    = dbo.fn_checkStock(
                                           @xxbad_part,
                                           @xxbad_fromloc,
                                           @xxbad_lot,
                                           CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0'))
                                       );
                --判断到库位 是否存在
                IF ISNULL(@ErrorMessage, '') <> ''
                BEGIN
                    RAISERROR(@ErrorMessage, 11, 1);

                END;
                --更新备料主表的状态 标记已经备料
                UPDATE Barcode_UsingRequest
                SET Status = 2
                WHERE SN = @xxbad_ship_id;


                --更新备料明细中数量
                UPDATE dbo.Barcode_Using_Detail
                SET AllotQty = ISNULL(AllotQty, 0) + CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0'))
                WHERE SN = @xxbad_ship_id
                      AND PartNum = @xxbad_part;
                --如果出库单 明细全部备料完成  自动关闭出库单
                --UPDATE Barcode_UsingRequest
                --           SET Status = 3
                --           WHERE SN = @xxbad_ship_id;

                --插入备料明细表
                INSERT INTO [dbo].[Using_DetailAllot]
                (
                    ID,
                    [SN],
                    [USN],
                    [LableQty],
                    [AllotQty],
                    [AllotUser],
                    [AllotTime]
                )
                SELECT NEWID(),
                       @xxbad_ship_id,
                       usn,
                       qty,
                       CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0')),
                       @xxbad_user,
                       GETDATE()
                FROM barocde_materiallable
                WHERE USN = @xxbad_id;
                --更新标签表的数量
                UPDATE dbo.barocde_materiallable
                SET qty = qty - CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0'))
                WHERE usn = @xxbad_id;


                --插入计划外主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    BarcodeInterFaceID,
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto,
                    xxinbxml_reason
                )
                SELECT @xxbad_domain,
                       @interfaceid,
                       'IC_SHP',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       poline,
                       partnum,
                       dbo.GetQADloc(currentloc),
                       '',
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0')),
                       lot,
                       '',
                       @xxbad_rmks,
                       @xxbad_ref,
                       @xxbad_emp
                FROM barocde_materiallable
                WHERE usn = @xxbad_id;

                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_SHP',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       usn,
                       @xxbad_user,
                       '',
                       '',
                       partnum,
                       currentloc,
                       '',
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0')),
                       lot,
                       '',
                       @xxbad_fromref,
                       @xxbad_toref
                FROM barocde_materiallable
                WHERE usn = @xxbad_id;
                --获取出库库位，累计数量，计划量
                SELECT @xxbad_rj_qty = Qty,
                       @xxbad_loc = Loc,
                       @xxbad_extension3 = ISNULL(AllotQty, 0)
                FROM dbo.Barcode_Using_Detail
                WHERE SN = @xxbad_ship_id
                      AND PartNum = @xxbad_part;
                --返回第一个dataset 到前台
                SELECT @xxbad_rj_qty xxbad_rj_qty,
                       @xxbad_loc xxbad_loc,
                       @xxbad_part xxbad_part,
                       @xxbad_purchacorder xxbad_purchacorder,
                       @xxbad_extension3 xxbad_extension3,
                       CONVERT(VARCHAR(100), Date, 112) xxbad_date,
                       Depart xxbad_extension1,
                       usinguser xxbad_user,
                       @xxbad_ship_id xxbad_ship_id,
                       '领料成功' xxbad_rmks,
                       '' xxbad_id,
                       'xxbad_id' focus,
                       '' xxbad_qty,
                       '' xxbad_rj_qty,
                       ISNULL(ResonCode, '') xxbad_emp,
                       ISNULL(Memo, '') xxbad_extension4
                FROM dbo.Barcode_UsingRequest
                WHERE SN = @xxbad_ship_id;
            --RAISERROR(N'ERROR_MESSAGE#领料成功!#Material requisition successful!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                --获取备料单中第一行 等待备料的零件号
                SELECT TOP 1
                       @xxbad_part = PartNum,
                       @xxbad_rj_qty = Qty,
                       @xxbad_extension3 = ISNULL(AllotQty, 0)
                FROM dbo.Barcode_Using_Detail
                WHERE SN =
                (
                    SELECT TOP 1
                           SN
                    FROM dbo.Barcode_UsingRequest
                    WHERE ID = @xxbad_purchacorder
                );
                --根据零件号获取库存分布
                SELECT TOP 1
                       @xxbad_loc = loc
                FROM dbo.barocde_stock
                WHERE partnum = @xxbad_part
                ORDER BY lot ASC;
                --返回第一个data到前台
                SELECT 'xxbad_ship_id' focus;
            END;
            ELSE IF @ScanData = 'xxbad_ship_id'
            BEGIN
                PRINT @xxbad_ship_id;
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_UsingRequest
                    WHERE SN = @xxbad_ship_id
                          AND ApproveStatus = 1
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#出库单状态不正确!#The status of the delivery order is incorrect!', 11, 1);

                END;
                SELECT '' xxbad_part,
                       'xxbad_part' focus,
                       @xxbad_purchacorder xxbad_purchacorder,
                       CONVERT(VARCHAR(100), Date, 112) xxbad_date,
                       Depart xxbad_extension1,
                       usinguser xxbad_user,
                       @xxbad_ship_id xxbad_ship_id,
                       '' xxbad_id,
                       '' xxbad_qty,
                       '' xxbad_rj_qty,
                       ISNULL(ResonCode, '') xxbad_emp,
                       ISNULL(Memo, '') xxbad_extension4
                FROM dbo.Barcode_UsingRequest
                WHERE SN = @xxbad_ship_id;
            END;
            ELSE IF @ScanData = 'xxbad_part'
            BEGIN
                --IF CHARINDEX('{', @xxbad_part) > 0
                --BEGIN

                --    
                --END;
                --获取出库库位，累计数量，计划量
                SELECT @xxbad_rj_qty = Qty,
                       @xxbad_loc = Loc,
                       @xxbad_extension3 = ISNULL(AllotQty, 0)
                FROM dbo.Barcode_Using_Detail
                WHERE SN = @xxbad_ship_id
                      AND PartNum = @xxbad_part;
                --返回第一个dataset 到前台
                SELECT @xxbad_rj_qty xxbad_rj_qty,
                       @xxbad_loc xxbad_loc,
                       @xxbad_part xxbad_part,
                       @xxbad_purchacorder xxbad_purchacorder,
                       @xxbad_extension3 xxbad_extension3,
                       CONVERT(VARCHAR(100), Date, 112) xxbad_date,
                       Depart xxbad_extension1,
                       usinguser xxbad_user,
                       @xxbad_ship_id xxbad_ship_id,
                       '' xxbad_id,
                       'xxbad_id' focus,
                       '' xxbad_qty,
                       '' xxbad_rj_qty,
                       ISNULL(ResonCode, '') xxbad_emp,
                       ISNULL(Memo, '') xxbad_extension4
                FROM dbo.Barcode_UsingRequest
                WHERE SN = @xxbad_ship_id;
            END;
            ELSE --认为扫描的是原材料条码
            BEGIN

                --读取标签中的信息
                SELECT @xxbad_id = usn,
                       @xxbad_qty = qty,
                       @xxbad_part = partnum,
                       @xxbad_fromloc = currentloc
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id
                      AND status = 4
                      AND qty > 0;
                --判断标签是否合法
                IF ISNULL(@xxbad_fromloc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                SET @xxbad_rj_qty = '';
                --获取当前标签的零件的需求量和累计备料量
                SELECT @xxbad_rj_qty = Qty,
                       @xxbad_loc = Loc,
                       @xxbad_extension3 = ISNULL(AllotQty, 0)
                FROM dbo.Barcode_Using_Detail
                WHERE SN = @xxbad_ship_id
                      AND PartNum = @xxbad_part;

                --判断当前标签是否在计划外内
                IF ISNULL(@xxbad_rj_qty, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前标签不在计划外内!#The current label is not within the planned scope!', 11, 1);
                END;

                --定义欠交量
                DECLARE @lessqty DECIMAL(18, 5)
                    = CONVERT(DECIMAL(18, 5), @xxbad_rj_qty) - CONVERT(DECIMAL(18, 5), @xxbad_extension3);
                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       @xxbad_qty xxbad_qty,
                       @xxbad_rj_qty xxbad_rj_qty,
                       @xxbad_extension3 xxbad_extension3,
                       CASE
                           WHEN @lessqty > @xxbad_qty THEN
                               @xxbad_qty
                           ELSE
                               @lessqty
                       END xxbad_extension2,
                       @xxbad_emp xxbad_emp,
                       @xxbad_ship_id xxbad_ship_id,
                       @xxbad_part xxbad_part,
                       @xxbad_extension4 xxbad_extension4,
                       CONVERT(VARCHAR(50), @xxbad_date, 112) xxbad_date,
                       @xxbad_extension1 xxbad_extension1;
            END;
        END;
        IF @interfaceid IN ( 10100 ) --新成品计划外出库  天津佰安
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断计划外号是不是为空
                IF ISNULL(@xxbad_id, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#没有扫描箱标签，请先扫描箱标签!#No box label scanned. Please scan the box label first!', 11, 1);

                END;
                --判断有没有输入本次领用量
                IF ISNULL(@xxbad_extension2, '0') = '0'
                   OR @xxbad_extension2 = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请扫描标签，然后输入本次领用量!#Please scan the label and then enter the quantity for this usage!', 11, 1);

                END;
                --判断本次领用量是不是大于标签数量
                IF CONVERT(DECIMAL(18, 5), @xxbad_extension2) > CONVERT(DECIMAL(18, 5), @xxbad_qty)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#不能大于本箱的总数量!#Cannot exceed the total quantity of this box!', 11, 1);

                END;
                --判断原因代码是否为空
                IF ISNULL(@xxbad_emp, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#原因代码不能为空!#The reason code cannot be empty!', 11, 1);
                END;
                --判断本次领用量 有没有超出计划量
                IF CONVERT(DECIMAL(18, 5), @xxbad_extension2) > CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_rj_qty, 0))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#本次领用量不能超出计划量!#The amount for this requisition cannot exceed the planned quantity!', 11, 1);

                END;
                IF ISNULL(@xxbad_ship_id, '') = ''
                   AND ISNULL(@xxbad_purchacorder, '') <> ''
                BEGIN
                    SELECT @xxbad_ship_id = SN
                    FROM dbo.Barcode_UsingRequest
                    WHERE ID = @xxbad_purchacorder;
                END;

                --判断计划外号是不是为空
                IF ISNULL(@xxbad_ship_id, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#计划外号不能为空，请重新选择!#The unplanned number cannot be empty, please select again!', 11, 1);

                END;
                --获取部门
                SELECT TOP 1
                       @xxbad_rmks = sys_depart.org_code
                FROM dbo.Barcode_UsingRequest
                    LEFT JOIN dbo.sys_depart
                        ON sys_depart.id = Barcode_UsingRequest.Depart
                WHERE SN = @xxbad_ship_id;
                --判断是否超出需求量
                IF CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_rj_qty, '0')) < (CONVERT(
                                                                                     DECIMAL(18, 5),
                                                                                     ISNULL(@xxbad_extension2, '0')
                                                                                 )
                                                                          + CONVERT(
                                                                                       DECIMAL(18, 5),
                                                                                       ISNULL(@xxbad_extension3, '0')
                                                                                   )
                                                                         )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前零件超出需求量!#The current part exceeds the required quantity!', 11, 1);

                END;
                --判断零件号 是否和当前标签号的零件号匹配
                SELECT @xxbad_extension5 = PartNum,
                       @xxbad_lot = Lot,
                       @xxbad_fromloc = CurrentLoc
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id
                      AND Status = 3;
                IF ISNULL(@xxbad_extension5, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不存在!#Tag does not exist!', 11, 1);

                END;
                IF ISNULL(@xxbad_extension5, '') <> @xxbad_part
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#零件号不匹配!#Part number mismatch!', 11, 1);

                END;
                --判断累计领用量 有没有超出计划量
                DECLARE @SumAllot10100 DECIMAL(18, 5);
                SELECT @SumAllot10100 = ISNULL(AllotQty, 0) + CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0'))
                FROM Barcode_Using_Detail
                WHERE SN = @xxbad_ship_id
                      AND PartNum = @xxbad_part;
                IF @SumAllot10100 > CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_rj_qty, 0))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#累计领用量不能超出计划量!#The cumulative usage cannot exceed the planned amount!', 11, 1);

                END;
                --消耗类型 需要判断库存是否足够
                SELECT @ErrorMessage
                    = dbo.fn_checkStock(
                                           @xxbad_part,
                                           @xxbad_fromloc,
                                           @xxbad_lot,
                                           CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0'))
                                       );
                --判断到库位 是否存在
                IF ISNULL(@ErrorMessage, '') <> ''
                BEGIN
                    RAISERROR(@ErrorMessage, 11, 1);

                END;
                --更新备料主表的状态 标记已经备料
                UPDATE Barcode_UsingRequest
                SET Status = 2
                WHERE SN = @xxbad_ship_id;
                --更新备料明细中数量
                UPDATE dbo.Barcode_Using_Detail
                SET AllotQty = ISNULL(AllotQty, 0) + CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0'))
                WHERE SN = @xxbad_ship_id
                      AND PartNum = @xxbad_part;
                --插入备料明细表
                INSERT INTO [dbo].[Using_DetailAllot]
                (
                    ID,
                    [SN],
                    [USN],
                    [LableQty],
                    [AllotQty],
                    [AllotUser],
                    [AllotTime]
                )
                SELECT NEWID(),
                       @xxbad_ship_id,
                       USN,
                       Qty,
                       CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0')),
                       @xxbad_user,
                       GETDATE()
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                --更新标签表的数量
                UPDATE dbo.Barocde_BoxlLable
                SET Qty = Qty - CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0'))
                WHERE USN = @xxbad_id;

                --插入计划外主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    BarcodeInterFaceID,
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_refto,
                    xxinbxml_reason,
                    xxinbxml_reffrm
                )
                SELECT @xxbad_domain,
                       @interfaceid,
                       'IC_SHP',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       dbo.GetQADloc(CurrentLoc),
                       '',
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0')),
                       Lot,
                       '',
                       @xxbad_ref,
                       LEFT(@xxbad_emp, 30),
                       @xxbad_rmks
                FROM Barocde_BoxlLable
                WHERE USN = @xxbad_id;

                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_SHP',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       USN,
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       CurrentLoc,
                       '',
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0')),
                       Lot,
                       '',
                       @xxbad_fromref,
                       @xxbad_toref
                FROM Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                --返回第一个dataset 到前台
                SELECT @xxbad_rj_qty xxbad_rj_qty,
                       @xxbad_loc xxbad_loc,
                       @xxbad_part xxbad_part,
                       @xxbad_purchacorder xxbad_purchacorder,
                       @xxbad_extension3 xxbad_extension3,
                       CONVERT(VARCHAR(100), Date, 112) xxbad_date,
                       Depart xxbad_extension1,
                       usinguser xxbad_user,
                       @xxbad_ship_id xxbad_ship_id,
                       '领料成功' xxbad_rmks,
                       '' xxbad_id,
                       'xxbad_id' focus,
                       '' xxbad_qty,
                       '' xxbad_rj_qty,
                       ISNULL(ResonCode, '') xxbad_emp,
                       ISNULL(Memo, '') xxbad_extension4
                FROM dbo.Barcode_UsingRequest
                WHERE SN = @xxbad_ship_id;
            --RAISERROR(N'ERROR_MESSAGE#领料成功!#Material requisition successful!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                ----获取备料单中第一行 等待备料的零件号
                --SELECT TOP 1
                --       @xxbad_part = PartNum,
                --       @xxbad_rj_qty = Qty,
                --       @xxbad_extension3 = ISNULL(AllotQty, 0)
                --FROM dbo.Barcode_Using_Detail
                --WHERE SN =
                --(
                --    SELECT TOP 1
                --           SN
                --    FROM dbo.Barcode_UsingRequest
                --    WHERE ID = @xxbad_purchacorder
                --);
                ----根据零件号获取库存分布
                --SELECT TOP 1
                --       @xxbad_loc = loc
                --FROM dbo.barocde_stock
                --WHERE partnum = @xxbad_part
                --ORDER BY lot ASC;
                ----返回第一个data到前台
                --SELECT @xxbad_extension7 xxbad_extension7,
                --       Depart xxbad_extension1,
                --       SN xxbad_extension5,
                --       usinguser xxbad_user,
                --       @xxbad_part xxbad_part,
                --       'xxbad_ship_id' focus,
                --       @xxbad_rj_qty xxbad_rj_qty,
                --       @xxbad_extension3 xxbad_extension3,
                --       @xxbad_loc xxbad_loc,
                --       ISNULL(ResonCode, '') xxbad_emp,
                --       ISNULL(Memo, '') xxbad_extension4,
                --       0 xxbad_extension3
                --FROM dbo.Barcode_UsingRequest
                --WHERE ID = @xxbad_purchacorder;
                SELECT 'xxbad_ship_id' focus;
            END;
            ELSE IF @ScanData = 'xxbad_ship_id'
            BEGIN

                SELECT '' xxbad_part,
                       @xxbad_purchacorder xxbad_purchacorder,
                       CONVERT(CHAR(12), Date) xxbad_extension7,
                       Depart xxbad_extension1,
                       usinguser xxbad_user,
                       'xxbad_part' focus,
                       '' xxbad_id,
                       @xxbad_ship_id xxbad_ship_id,
                       '' xxbad_qty,
                       '' xxbad_rj_qty,
                       ISNULL(ResonCode, '') xxbad_emp,
                       ISNULL(Memo, '') xxbad_extension4
                FROM dbo.Barcode_UsingRequest
                WHERE SN = @xxbad_ship_id;

            END;
            ELSE IF @ScanData = 'xxbad_part'
            BEGIN

                --获取出库库位，累计数量，计划量
                SELECT @xxbad_rj_qty = Qty,
                       @xxbad_loc = Loc,
                       @xxbad_extension3 = ISNULL(AllotQty, 0)
                FROM dbo.Barcode_Using_Detail
                WHERE SN = @xxbad_ship_id
                      AND PartNum = @xxbad_part;
                --返回第一个dataset 到前台
                SELECT @xxbad_rj_qty xxbad_rj_qty,
                       @xxbad_loc xxbad_loc,
                       @xxbad_purchacorder xxbad_purchacorder,
                       @xxbad_extension3 xxbad_extension3,
                       @xxbad_ship_id xxbad_ship_id,
                       @xxbad_extension7 xxbad_extension7,
                       Depart xxbad_extension1,
                       usinguser xxbad_user,
                       'xxbad_id' focus,
                       @xxbad_part xxbad_part,
                       '' xxbad_id,
                       '' xxbad_qty,
                       '' xxbad_rj_qty,
                       ISNULL(ResonCode, '') xxbad_emp,
                       ISNULL(Memo, '') xxbad_extension4
                FROM dbo.Barcode_UsingRequest
                WHERE SN = @xxbad_ship_id;
            END;
            ELSE --认为扫描的是成品条码
            BEGIN

                --读取标签中的信息
                SELECT @xxbad_id = USN,
                       @xxbad_qty = Qty,
                       @xxbad_part = PartNum,
                       @xxbad_fromloc = CurrentLoc
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id
                      AND Status = 3
                      AND Qty > 0;
                --判断标签是否合法
                IF ISNULL(@xxbad_fromloc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                SET @xxbad_rj_qty = '';
                --获取当前标签的零件的需求量和累计备料量
                SELECT @xxbad_rj_qty = Qty,
                       @xxbad_loc = Loc,
                       @xxbad_extension3 = ISNULL(AllotQty, 0)
                FROM dbo.Barcode_Using_Detail
                WHERE SN = @xxbad_ship_id
                      AND PartNum = @xxbad_part;

                --判断当前标签是否在计划外内
                IF ISNULL(@xxbad_rj_qty, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前标签不在计划外内!#The current label is not within the planned scope!', 11, 1);

                END;
                --判断当前标签是否从指定的库位出库
                IF ISNULL(@xxbad_loc, '') <> @xxbad_fromloc
                BEGIN
                    SET @xxbad_fromloc = @xxbad_loc;
                END;
                DECLARE @lessqty2 DECIMAL(18, 5)
                    = CONVERT(DECIMAL(18, 5), @xxbad_rj_qty) - CONVERT(DECIMAL(18, 5), @xxbad_extension3);
                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       @xxbad_qty xxbad_qty,
                       @xxbad_rj_qty xxbad_rj_qty,
                       @xxbad_extension3 xxbad_extension3,
                       CASE
                           WHEN @lessqty2 > @xxbad_qty THEN
                               @xxbad_qty
                           ELSE
                               @lessqty2
                       END xxbad_extension2,
                       @xxbad_part xxbad_part,
                       @xxbad_ship_id xxbad_ship_id,
                       @xxbad_emp xxbad_emp,
                       @xxbad_extension4 xxbad_extension4,
                       @xxbad_extension7 xxbad_extension7,
                       @xxbad_extension1 xxbad_extension1;
            END;
        END;
        IF @interfaceid IN ( 10048 ) --原材料计划外入库
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --将到库位转化成库区
                DECLARE @locarea10048 VARCHAR(50);
                SELECT TOP 1
                       @locarea10048 = LocArea
                FROM dbo.Barcode_Location
                WHERE xxlocation_loc = @xxbad_toloc;
                IF ISNULL(@locarea10048, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前到库位库区不存在!#The current storage location does not exist!', 11, 1);
                END;

                --判断标签有没有重复扫描
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.barocde_materiallable
                    WHERE usn = @xxbad_id
                          AND ISNULL(status, 0) < 4
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签已经入库!#The label has already been stored!', 11, 1);
                END;
                --判断标签关联的入库单的状态
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_UsingRequest
                    WHERE SN = @xxbad_ship_id
                          AND Status IN ( 2, 3 )
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签关联的入库单的状态不正确!#The status of the associated receipt for the tag is incorrect!', 11, 1);
                END;
                --更新标签表的库位和入库时间批次
                UPDATE barocde_materiallable
                SET fromloc = currentloc,
                    currentloc = @xxbad_toloc,
                    status = 4,
                    lot = CONVERT(CHAR(8), GETDATE(), 112), --目前在生成标签时候 生成批次
                    inbounduser = @xxbad_user,
                    inboundtime = GETDATE()
                WHERE usn = @xxbad_id;
                --更新入库明细的入库数量
                UPDATE dbo.Barcode_Using_Detail
                SET AllotQty = ISNULL(AllotQty, 0) + CONVERT(DECIMAL(18, 4), @xxbad_qty)
                WHERE SN = @xxbad_ship_id
                      AND PartNum = @xxbad_part;
                --获取原因代码
                SELECT TOP 1
                       @xxbad_emp = ResonCode,
                       @xxbad_rmks = sys_depart.org_code
                FROM dbo.Barcode_UsingRequest
                    LEFT JOIN dbo.sys_depart
                        ON sys_depart.id = Barcode_UsingRequest.Depart
                WHERE SN = @xxbad_ship_id
                      AND Type = 1;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotto,
                    xxinbxml_lotfrm,
                    xxinbxml_reason,
                    xxinbxml_reffrm
                )
                SELECT @xxbad_domain,
                       'IC_SHP',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       poline,
                       partnum,
                       dbo.GetQADloc(@xxbad_toloc),
                       '',
                       site,
                       site,
                       @xxbad_ship_id,
                       usn,
                       -qty,
                       lot,
                       lot,
                       @xxbad_emp,
                       @xxbad_rmks
                FROM barocde_materiallable
                WHERE usn = @xxbad_id;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'PQ_IC_ICUNRC',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       usn,
                       @xxbad_user,
                       '',
                       '',
                       partnum,
                       '',
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       qty,
                       lot,
                       lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM barocde_materiallable
                WHERE usn = @xxbad_id;
                --关闭已经全部收货完成的入库单
                --汇总此入库单 标签中的数量
                DECLARE @SUMQTY DECIMAL = 0;
                SELECT @SUMQTY = SUM(qty)
                FROM dbo.barocde_materiallable
                WHERE ponum = @xxbad_ship_id
                      AND ISNULL(status, 0) > 3;
                --汇总此入库单计划数量
                DECLARE @SUMQTY2 DECIMAL = 1;
                SELECT @SUMQTY2 = SUM(Qty)
                FROM dbo.Barcode_Using_Detail
                WHERE SN = @xxbad_ship_id;
                --修改入库单的状态为已入库
                UPDATE dbo.Barcode_UsingRequest
                SET Status = 2
                WHERE SN = @xxbad_ship_id;
                --如果入库量等于计划量 则关闭单据
                IF @SUMQTY = @SUMQTY2
                BEGIN
                    UPDATE dbo.Barcode_UsingRequest
                    SET Status = 5,
                        FinishTime = GETDATE(),
                        FinshUser =
                        (
                            SELECT TOP 1
                                   Name
                            FROM dbo.System_Administrator
                            WHERE LoginCode = @xxbad_user
                        )
                    WHERE SN = @xxbad_ship_id;
                END;
                RAISERROR(N'Info_MESSAGE#入库完成!#Storage completed!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;
            END;
            ELSE IF @ScanData = 'xxbad_toloc'
            BEGIN
                SELECT @xxbad_ship_id xxbad_ship_id,
                       @xxbad_id xxbad_id,
                       @xxbad_part xxbad_part,
                       @xxbad_desc xxbad_desc,
                       @xxbad_supplier xxbad_supplier,
                       @xxbad_qty xxbad_qty,
                       @xxbad_toloc xxbad_toloc,
                       @xxbad_fromloc xxbad_fromloc;
            END;
            ELSE
            BEGIN

                --从标签中加载信息  并且判断标签状态
                SELECT @xxbad_ship_id = ponum,
                       @xxbad_id = usn,
                       @xxbad_part = partnum,
                       @xxbad_desc = partdescription,
                       @xxbad_supplier = supplynum,
                       @xxbad_qty = qty,
                       @xxbad_site = site,
                       @InspectUser = inspectuser,
                       @InspectType = inspecttype,
                       @InspectResult = inspectresult,
                       @xxbad_fromloc = currentloc
                FROM barocde_materiallable
                WHERE usn = @xxbad_id
                      AND ISNULL(status, 0) < 4;

                --判断标签状态
                IF (ISNULL(@xxbad_id, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不正确!#Invalid tag!', 11, 1);

                END;
                --判断标签关联的入库单的状态
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_UsingRequest
                    WHERE SN = @xxbad_ship_id
                          AND Status IN ( 2, 3 )
                          AND ISNULL(FGorRM, 0) = 0
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签关联的入库单的未打印!#The associated receipt of the label has not been printed!', 11, 1);

                END;
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_UsingRequest
                    WHERE SN = @xxbad_ship_id
                          AND ApproveStatus = 1
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签关联的入库单的未审批通过!#The associated warehouse receipt for the tag has not been approved!', 11, 1);

                END;
                --返回第一个dataset到前台
                SELECT @xxbad_ship_id xxbad_ship_id,
                       @xxbad_id xxbad_id,
                       @xxbad_part xxbad_part,
                       @xxbad_desc xxbad_desc,
                       @xxbad_supplier xxbad_supplier,
                       @xxbad_qty xxbad_qty,
                       @xxbad_toloc xxbad_toloc,
                       @xxbad_fromloc xxbad_fromloc
                FROM pt_mstr
                WHERE pt_part = @xxbad_part
                      AND pt_domain = @xxbad_domain
                      AND pt_site = @xxbad_site;
            END;

        END;
        IF @interfaceid IN ( 10050 ) --日程发运备料
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断托表中 是否有备料信息
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                          AND ExtendedField1 = @xxbad_ship_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前单据没有缓存的备料信息 !#No cached material information for the current document!', 11, 1);

                END;

                --判断 发货到库位 的QAD库位是否 配置
                IF ISNULL(dbo.GetQADloc(@xxbad_toloc), '') = ''
                BEGIN
                    SET @ErrorMessage = N'ERROR_MESSAGE#' + @xxbad_toloc + N' 发货到库位不存在!#' + @xxbad_toloc + N' The shipping location does not exist!';
                    RAISERROR(@ErrorMessage, 11, 1);

                END;
                --判断所有的行 是否全部备料完成
                DECLARE @Unfinish10050 VARCHAR(2000);
                SELECT @Unfinish10050 = COALESCE(Item + '|' + Line, '')
                FROM dbo.Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                      AND ISNULL(AllotQty, 0) < CurrentQty;
                SET @ErrorMessage = N'ERROR_MESSAGE#' + @Unfinish10050 + N'未完成备料!#' + @Unfinish10050 + N'Unfinished material preparation!';
                IF ISNULL(@Unfinish10050, '') <> ''
                BEGIN
                    RAISERROR(@ErrorMessage, 11, 1);

                END;

                --汇总计算每个
                SELECT SUM(Qty) Qty,
                       PurchaseOrder,
                       PoLine
                INTO #temp10050
                FROM Barocde_BoxlLable
                WHERE PurchaseOrder IN
                      (
                          SELECT PurchaseOrder
                          FROM Barcode_SOShippingDetail
                          WHERE ShipSN = @xxbad_ship_id
                      )
                GROUP BY PurchaseOrder,
                         PoLine;
                --更新销售订单中的发运总数量
                UPDATE a
                SET a.sod_shipQty = b.Qty
                FROM sod_det a,
                     #temp10050 b
                WHERE a.sod_nbr IN
                      (
                          SELECT PurchaseOrder
                          FROM Barcode_SOShippingDetail
                          WHERE ShipSN = @xxbad_ship_id
                      )
                      AND a.sod_nbr = b.PurchaseOrder
                      AND a.sod_line = b.PoLine;


                --将托表中的标签 库位，状态，发运单 字段更新
                UPDATE dbo.Barocde_BoxlLable
                SET CurrentLoc = @xxbad_toloc,
                    Status = 5,
                    ShipSN = @xxbad_ship_id
                WHERE USN IN
                      (
                          SELECT LableID
                          FROM dbo.Barcode_OperateCache
                          WHERE AppID = @interfaceid
                                AND OpUser = @xxbad_user
                                AND ExtendedField1 = @xxbad_ship_id
                      );
                --将发运主表状态更改为已发运
                UPDATE dbo.Barcode_SOShippingMain
                SET Status = 2
                WHERE SN = @xxbad_ship_id;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    BarcodeInterFaceID,
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @xxbad_domain,
                       @interfaceid,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       PoNum,
                       PoLine,
                       PartNum,
                       dbo.GetQADloc(MAX(CurrentLoc)),
                       dbo.GetQADloc(@xxbad_toloc),
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       SUM(Qty),
                       ToLot,
                       ToLot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                      AND ExtendedField1 = @xxbad_ship_id
                GROUP BY PoNum,
                         PoLine,
                         PartNum,
                         ToLot;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       LableID,
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       CurrentLoc,
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       Qty,
                       ToLot,
                       ToLot,
                       @xxbad_fromref,
                       @xxbad_toref
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                      AND ExtendedField1 = @xxbad_ship_id;
                --清理缓存
                DELETE [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                RAISERROR(N'Info_MESSAGE#发运完成!#Shipment completed!', 11, 1);

            END;

            ELSE IF @ScanData = 'Cache'
            BEGIN
                --获取缓存中发运单号
                SELECT TOP 1
                       @xxbad_ship_id = ExtendedField1
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                GROUP BY ExtendedField1,
                         PoNum,
                         PoLine,
                         PartNum;
                --  根据发运单号获取  还没备料完成的第一行的记录  返回第一个dateset 到前台 
                SELECT TOP 1
                       ShipSN xxbad_ship_id,
                       PurchaseOrder xxbad_order,
                       Line xxbad_proline,
                       ShipTo xxbad_toloc,
                       Item xxbad_part,
                       AllotQty xxbad_rj_qty,
                       CurrentQty xxbad_scrapqty
                FROM dbo.Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_ship_id
                      AND ISNULL(AllotQty, 0) <= CurrentQty
                ORDER BY AllotQty ASC;

                --返回第二个dataset到前台 按照批次检索 前10行的箱标签
                SELECT LableID USN,
                       CurrentLoc,
                       Qty,
                       ToLot Lot
                FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
            END;
            ELSE
            BEGIN
                --处理数据扫描模块 如果到销售单号为空，认为当前扫描的是销售单号
                IF ISNULL(@xxbad_ship_id, '') = ''
                BEGIN
                    --判断发运单是否合法
                    IF NOT EXISTS
                    (
                        SELECT TOP 1
                               1
                        FROM dbo.Barcode_SOShippingMain
                        WHERE SN = @ScanData
                              AND Type = 1
                    )
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#销售单号不合法 !#Invalid sales order number!', 11, 1);

                    END;
                    SET @xxbad_ship_id = @ScanData;

                    SELECT TOP 1
                           @xxbad_order = PurchaseOrder,
                           @xxbad_proline = Line,
                           @xxbad_part = Item,
                           @xxbad_toloc = ShipTo,
                           @xxbad_scrapqty = CurrentQty,
                           @xxbad_rj_qty = ISNULL(AllotQty, 0)
                    FROM dbo.Barcode_SOShippingDetail
                    WHERE ShipSN = @xxbad_ship_id
                          AND ISNULL(AllotQty, 0) < CurrentQty
                    ORDER BY Item,
                             Line;

                    --返回第一个dateset 到前台 将明细表备料第一行带出
                    SELECT @xxbad_ship_id xxbad_ship_id,
                           @xxbad_order xxbad_order,
                           @xxbad_proline xxbad_proline,
                           @xxbad_part xxbad_part,
                           @xxbad_toloc xxbad_toloc,
                           @xxbad_scrapqty xxbad_scrapqty,
                           @xxbad_rj_qty xxbad_rj_qty;
                    --返回第二个dataset到前台 按照批次检索 前10行的箱标签
                    SELECT LableID USN,
                           CurrentLoc,
                           Qty,
                           ToLot Lot
                    FROM dbo.Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user;
                END;
                ELSE
                BEGIN --处理扫描的条码
                    --从标签中加载信息  并且判断标签状态 只有上架的后的标签 才能发运
                    SELECT @xxbad_id = USN,
                           @xxbad_lot = Lot,
                           @xxbad_qty = Qty,
                           @xxbad_part = PartNum,
                           @xxbad_loc = CurrentLoc
                    FROM Barocde_BoxlLable
                    WHERE USN = @ScanData
                          AND
                          (
                              Status = 3
                              OR Status = 4
                          );
                    IF (ISNULL(@xxbad_id, '') = '')
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#标签不正确!#Invalid tag!', 11, 1);

                    END;
                    --判断零件是否可以从从库位移除
                    SELECT @msg_error = dbo.CheckLocArea(@xxbad_part, @xxbad_loc, @interfaceid);
                    IF ISNULL(@msg_error, '') <> ''
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#当前箱码不在成品货架，不能出库!#The current box code is not on the finished goods shelf and cannot be shipped out!', 11, 1);

                    END;
                    --判断QAD中 从库位和到库位是否相同
                    IF (dbo.GetQADloc(@xxbad_loc) = dbo.GetQADloc(@xxbad_toloc))
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#从库位和到库位的库区相同，不能出库!#The source and destination storage areas are the same, cannot proceed with the outbound process!', 11, 1);

                    END;
                    --判断当前客户的当前零件没有维护扩展信息
                    IF NOT EXISTS
                    (
                        SELECT TOP 1
                               1
                        FROM dbo.barcode_custompartset
                        WHERE partnum = @xxbad_part
                              AND customid =
                              (
                                  SELECT TOP 1
                                         SupplierCode
                                  FROM dbo.Barcode_SOShippingMain
                                  WHERE SN = @xxbad_ship_id
                              )
                    )
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#当前客户的当前零件没有维护扩展信息!#No extended information is maintained for the current part of the current customer!', 11, 1);

                    END;
                    --暂时不判断
                    IF @xxbad_rj_qty = ''
                        SET @xxbad_rj_qty = 0;
                    IF @xxbad_qty = ''
                        SET @xxbad_qty = 0;
                    IF @xxbad_scrapqty = ''
                        SET @xxbad_scrapqty = 0;
                    --判断当前原材料是否被被人缓存了
                    SELECT TOP 1
                           @cacheuser = OpUser
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND LableID = @ScanData;
                    IF (ISNULL(@cacheuser, @xxbad_user) <> @xxbad_user)
                    BEGIN
                        SET @ErrorMessage
                            = N'ERROR_MESSAGE#该箱码被用户' + @cacheuser + N'扫描，请提醒其操作!#The box code has been scanned by user ' + @cacheuser + N'. Please remind them to take action!';
                        RAISERROR(@ErrorMessage, 11, 1);

                    END;
                    --如果在动态高速缓存表不存在
                    IF NOT EXISTS
                    (
                        SELECT TOP 1
                               1
                        FROM [Barcode_OperateCache]
                        WHERE AppID = @interfaceid
                              AND OpUser = @xxbad_user
                              AND ExtendedField1 = @xxbad_ship_id
                              AND LableID = @ScanData
                    )
                    BEGIN
                        --判断是否超量备料
                        IF CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_rj_qty, 0), 0)
                           + CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_qty, 0), 0) > CONVERT(
                                                                                            DECIMAL(18, 5),
                                                                                            ISNULL(@xxbad_scrapqty, 0),
                                                                                            0
                                                                                        )
                        BEGIN
                            RAISERROR(N'ERROR_MESSAGE#不能超量备料!#Do not exceed the material limit!', 11, 1);

                        END;
                        --从标签中获取标签信息 插入动态高速缓存表
                        INSERT INTO [dbo].[Barcode_OperateCache]
                        (
                            [AppID],
                            [OpUser],
                            [LableID],
                            [PartNum],
                            [PartDescrition],
                            [Qty],
                            ToLot,
                            [FromLoc],
                            [CurrentLoc],
                            [ToLoc],
                            [FromSite],
                            [ToSite],
                            [ScanTime],
                            ExtendedField1
                        )
                        SELECT TOP 1
                               @interfaceid,
                               @xxbad_user,
                               @ScanData,
                               PartNum,
                               PartDescription,
                               Qty,
                               Lot,
                               CurrentLoc,
                               CurrentLoc,
                               @xxbad_toloc,
                               Site,
                               @xxbad_site,
                               GETDATE(),
                               @xxbad_ship_id
                        FROM dbo.Barocde_BoxlLable
                        WHERE USN = @ScanData;

                        --更新标签表 标记标签已经备料
                        UPDATE Barocde_BoxlLable
                        SET Status = 4
                        WHERE USN = @ScanData;
                        --更新备料明细表中的累计备料量
                        UPDATE dbo.Barcode_SOShippingDetail
                        SET AllotQty = ISNULL(AllotQty, 0) + @xxbad_qty
                        WHERE ShipSN = @xxbad_ship_id
                              AND PurchaseOrder = @xxbad_order
                              AND Line = @xxbad_proline;
                    END;
                    ELSE
                    BEGIN
                        --从托表中删除
                        DELETE [Barcode_OperateCache]
                        WHERE AppID = @interfaceid
                              AND ExtendedField1 = @xxbad_ship_id
                              AND OpUser = @xxbad_user
                              AND LableID = @ScanData;
                        --更新标签表 回滚标记
                        UPDATE Barocde_BoxlLable
                        SET Status = 3
                        WHERE USN = @ScanData;
                        --更新备料明细表中的累计备料量
                        UPDATE dbo.Barcode_SOShippingDetail
                        SET AllotQty = ISNULL(AllotQty, 0) - ISNULL(@xxbad_qty, 0)
                        WHERE ShipSN = @xxbad_ship_id
                              AND PurchaseOrder = @xxbad_order
                              AND Line = @xxbad_proline;
                        --清空部分界面
                        SET @xxbad_part = '';
                        SET @xxbad_scrapqty = '';
                        SET @xxbad_rj_qty = '';
                    END;
                    --重新获取刷新下备料量
                    SELECT TOP 1
                           @xxbad_rj_qty = AllotQty
                    FROM dbo.Barcode_SOShippingDetail
                    WHERE ShipSN = @xxbad_ship_id
                          AND PurchaseOrder = @xxbad_order
                          AND Line = @xxbad_proline;
                    --获取需要备料的下一行数据
                    SELECT TOP 1
                           @xxbad_order = PurchaseOrder,
                           @xxbad_proline = Line,
                           @xxbad_part = Item,
                           @xxbad_toloc = ShipTo,
                           @xxbad_scrapqty = CurrentQty,
                           @xxbad_rj_qty = AllotQty
                    FROM dbo.Barcode_SOShippingDetail
                    WHERE ShipSN = @xxbad_ship_id
                          AND ISNULL(AllotQty, 0) < CurrentQty
                    ORDER BY Item,
                             Line;
                    --返回第一个dateset 到前台 将明细表备料第一行带出
                    SELECT @xxbad_ship_id xxbad_ship_id,
                           @xxbad_order xxbad_order,
                           @xxbad_proline xxbad_proline,
                           @xxbad_part xxbad_part,
                           @xxbad_toloc xxbad_toloc,
                           @xxbad_scrapqty xxbad_scrapqty,
                           @xxbad_rj_qty xxbad_rj_qty;

                    --返回第二个dataset到前台 按照批次检索 前10行的箱标签
                    SELECT LableID USN,
                           CurrentLoc,
                           Qty,
                           ToLot Lot
                    FROM dbo.Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user;
                END;
            END;

        END;
        IF @interfaceid IN ( 10052 ) --成品计划外出库 
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN

                --判断标签是否扫描
                IF ISNULL(@xxbad_id, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#没有扫描任何标签!#No tags scanned!', 11, 1);

                END;
                --判断有没有输入本次领用量

                IF (ISNULL(@xxbad_extension2, '0') = '0' OR @xxbad_extension2 = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#领用数量不能为0!#The quantity received cannot be 0!', 11, 1);

                END;
                --判断是否超出需求量
                IF CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_rj_qty, '0')) < (CONVERT(
                                                                                     DECIMAL(18, 5),
                                                                                     ISNULL(@xxbad_extension2, '0')
                                                                                 )
                                                                          + CONVERT(
                                                                                       DECIMAL(18, 5),
                                                                                       ISNULL(@xxbad_extension3, '0')
                                                                                   )
                                                                         )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前零件超出需求量，请先拆箱!#The current part exceeds the required quantity, please unpack first!', 11, 1);

                END;
                IF ISNULL(@xxbad_extension5, '') = ''
                   AND ISNULL(@xxbad_purchacorder, '') <> ''
                BEGIN
                    SELECT @xxbad_extension5 = SN
                    FROM dbo.Barcode_UsingRequest
                    WHERE ID = @xxbad_purchacorder;
                END;
                --判断计划外号是不是为空
                IF ISNULL(@xxbad_extension5, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#计划外号不能为空，请重新选择!#The unplanned number cannot be empty, please select again!', 11, 1);

                END;
                --更新备料主表的状态 标记已经备料
                UPDATE Barcode_UsingRequest
                SET Status = 2
                WHERE SN = @xxbad_extension5;
                --更新备料明细中数量
                UPDATE dbo.Barcode_Using_Detail
                SET AllotQty = ISNULL(AllotQty, 0) + CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0'))
                WHERE SN = @xxbad_extension5
                      AND PartNum = @xxbad_part;
                --插入备料明细表
                INSERT INTO [dbo].[Using_DetailAllot]
                (
                    [SN],
                    [USN],
                    [LableQty],
                    [AllotQty],
                    [AllotUser],
                    [AllotTime]
                )
                SELECT @xxbad_extension5,
                       USN,
                       Qty,
                       CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0')),
                       @xxbad_user,
                       GETDATE()
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                --更新标签表的数量
                UPDATE dbo.Barocde_BoxlLable
                SET Qty = Qty - CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0'))
                WHERE USN = @xxbad_id;
                --插入计划外主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    BarcodeInterFaceID,
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto,
                    xxinbxml_reason
                )
                SELECT @xxbad_domain,
                       @interfaceid,
                       'IC_SHP',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       PoLine,
                       PartNum,
                       dbo.GetQADloc(CurrentLoc),
                       '',
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_extension5,
                       @xxbad_id,
                       CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0')),
                       '',
                       '',
                       @xxbad_ref,
                       @xxbad_ref,
                       @xxbad_emp
                FROM Barocde_BoxlLable
                WHERE USN = @xxbad_id;

                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_SHP',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       USN,
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       CurrentLoc,
                       '',
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_extension5,
                       @xxbad_id,
                       CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0')),
                       Lot,
                       '',
                       @xxbad_fromref,
                       @xxbad_toref
                FROM Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                RAISERROR(N'Info_MESSAGE#领料成功!#Material requisition successful!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                --获取备料单中第一行 等待备料的零件号
                SELECT TOP 1
                       @xxbad_part = PartNum
                FROM dbo.Barcode_Using_Detail
                WHERE SN =
                (
                    SELECT TOP 1
                           SN
                    FROM dbo.Barcode_UsingRequest
                    WHERE ID = @xxbad_purchacorder
                );
                --根据零件号获取库存分布
                SELECT TOP 1
                       @xxbad_loc = loc
                FROM dbo.barocde_stock
                WHERE partnum = @xxbad_part
                ORDER BY lot ASC;
                --返回第一个data到前台
                SELECT CONVERT(VARCHAR(100), Date, 112) xxbad_date,
                       Depart xxbad_extension1,
                       SN xxbad_extension5,
                       usinguser xxbad_user,
                       @xxbad_part xxbad_part,
                       @xxbad_loc xxbad_loc,
                       ISNULL(ResonCode, '') xxbad_emp,
                       ISNULL(Memo, '') xxbad_extension4,
                       0 xxbad_extension3
                FROM dbo.Barcode_UsingRequest
                WHERE ID = @xxbad_purchacorder;;

            END;
            ELSE IF @ScanData = 'ComboBox'
            BEGIN
                --获取备料单中第一行 等待备料的零件号
                SELECT TOP 1
                       @xxbad_part = PartNum,
                       @xxbad_rj_qty = Qty,
                       @xxbad_extension3 = ISNULL(AllotQty, 0)
                FROM dbo.Barcode_Using_Detail
                WHERE SN =
                (
                    SELECT TOP 1
                           SN
                    FROM dbo.Barcode_UsingRequest
                    WHERE ID = @xxbad_purchacorder
                );
                --根据零件号获取库存分布
                SELECT TOP 1
                       @xxbad_loc = loc
                FROM dbo.barocde_stock
                WHERE partnum = @xxbad_part
                ORDER BY lot ASC;
                --返回第一个data到前台
                SELECT CONVERT(VARCHAR(100), Date, 112) xxbad_date,
                       Depart xxbad_extension1,
                       SN xxbad_extension5,
                       usinguser xxbad_user,
                       '' xxbad_id,
                       '' xxbad_qty,
                       @xxbad_rj_qty xxbad_rj_qty,
                       @xxbad_extension3 xxbad_extension3,
                       @xxbad_part xxbad_part,
                       @xxbad_loc xxbad_loc,
                       ISNULL(ResonCode, '') xxbad_emp,
                       ISNULL(Memo, '') xxbad_extension4
                FROM dbo.Barcode_UsingRequest
                WHERE ID = @xxbad_purchacorder;

            END;
            ELSE --认为扫描的是成品条码
            BEGIN
                --读取标签中的信息
                SELECT @xxbad_id = USN,
                       @xxbad_qty = Qty,
                       @xxbad_part = PartNum,
                       @xxbad_fromloc = CurrentLoc
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @ScanData
                      AND Status = 3;
                --判断标签是否合法
                IF ISNULL(@xxbad_fromloc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                --判断标签数量是否为0
                IF CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_qty, 0)) <= 0
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前箱标签数量为0!#The current number of box labels is 0!', 11, 1);

                END;
                --获取当前标签的零件的需求量和累计备料量
                SELECT @xxbad_rj_qty = Qty,
                       @xxbad_loc = Loc,
                       @xxbad_extension3 = ISNULL(AllotQty, 0)
                FROM dbo.Barcode_Using_Detail
                WHERE SN = @xxbad_extension5
                      AND PartNum = @xxbad_part;
                --判断当前标签是否在计划外内
                IF ISNULL(@xxbad_rj_qty, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前标签不在计划外内!#The current label is not within the planned scope!', 11, 1);

                END;
                --判断当前标签是否从指定的库位出库
                IF ISNULL(@xxbad_loc, '') <> @xxbad_fromloc
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#必须从指定库位下面扫描当前零件!#You must scan the current part from the specified location!', 11, 1);

                END;
                --判断是否超出需求量
                IF CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_rj_qty, '0')) < (CONVERT(
                                                                                     DECIMAL(18, 5),
                                                                                     ISNULL(@xxbad_qty, '0')
                                                                                 )
                                                                          + CONVERT(
                                                                                       DECIMAL(18, 5),
                                                                                       ISNULL(@xxbad_extension3, '0')
                                                                                   )
                                                                         )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前零件超出需求量，请先拆箱!#The current part exceeds the required quantity, please unpack first!', 11, 1);

                END;
                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       @xxbad_part xxbad_part,
                       @xxbad_qty xxbad_qty,
                       @xxbad_rj_qty xxbad_rj_qty,
                       @xxbad_extension3 xxbad_extension3,
                       @xxbad_extension5 xxbad_extension5,
                       @xxbad_qty xxbad_extension2;
            END;

        END;
        IF @interfaceid IN ( 10054 ) --成品计划外入库  传入负数
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --将到库位转化成库区
                DECLARE @locarea10054 VARCHAR(50);
                SELECT TOP 1
                       @locarea10054 = LocArea
                FROM dbo.Barcode_Location
                WHERE xxlocation_loc = @xxbad_toloc;
                IF ISNULL(@locarea10054, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前到库位库区不存在!#The current storage location does not exist!', 11, 1);

                END;
                --将从库位转化成QAD库位
                DECLARE @QADfrom10054 VARCHAR(50);
                SELECT TOP 1
                       @QADfrom10054 = LocArea
                FROM dbo.Barcode_Location
                WHERE xxlocation_loc = @xxbad_fromloc;

                --判断标签有没有重复扫描
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barocde_BoxlLable
                    WHERE USN = @xxbad_id
                          AND ISNULL(Status, 0) > 2
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签已经入库!#The label has already been stored!', 11, 1);

                END;

                --判断标签关联的入库单的状态
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_UsingRequest
                    WHERE SN = @xxbad_ship_id
                          AND Status IN ( 1, 2, 3 )
                          AND FGorRM = 1
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#入库单未打印，请先打印入库单再入库!#The warehouse receipt has not been printed. Please print the warehouse receipt before proceeding with the storage!', 11, 1);

                END;
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_UsingRequest
                    WHERE SN = @xxbad_ship_id
                          AND ApproveStatus = 1
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签关联的入库单的未审批通过!#The associated warehouse receipt for the tag has not been approved!', 11, 1);

                END;
                --更新标签表的库位和入库时间批次
                UPDATE Barocde_BoxlLable
                SET FromLoc = CurrentLoc,
                    CurrentLoc = @xxbad_toloc,
                    Status = 3,
                    -- Lot = CONVERT(char(8), GETDATE(), 112),  目前批次是生成的时候生成的
                    InboundUser = @xxbad_user,
                    InboundTime = GETDATE()
                WHERE USN = @xxbad_id;
                --获取原因代码
                SELECT TOP 1
                       @xxbad_emp = ResonCode,
                       @xxbad_rmks = sys_depart.org_code
                FROM dbo.Barcode_UsingRequest
                    LEFT JOIN dbo.sys_depart
                        ON sys_depart.id = Barcode_UsingRequest.Depart
                WHERE SN = @xxbad_ship_id
                      AND Type = 1;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotto,
                    xxinbxml_lotfrm,
                    xxinbxml_reason,
                    xxinbxml_reffrm
                )
                SELECT @xxbad_domain,
                       'IC_SHP',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       PoLine,
                       PartNum,
                       dbo.GetQADloc(@xxbad_toloc),
                       '',
                       Site,
                       Site,
                       @xxbad_ship_id,
                       USN,
                       -Qty,
                       Lot,
                       Lot,
                       @xxbad_emp,
                       @xxbad_rmks
                FROM Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'PQ_IC_ICUNRC',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       USN,
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       '',
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       Qty,
                       Lot,
                       Lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                --关闭已经全部收货完成的入库单
                --汇总此入库单 标签中的数量
                DECLARE @SUMQTY10054 DECIMAL = 0;
                SELECT @SUMQTY10054 = SUM(Qty)
                FROM dbo.Barocde_BoxlLable
                WHERE WoNum = @xxbad_ship_id
                      AND ISNULL(Status, 0) >= 3;
                --汇总此入库单计划数量
                DECLARE @SUMQTY100542 DECIMAL = 1;
                SELECT @SUMQTY100542 = SUM(Qty)
                FROM dbo.Barcode_Using_Detail
                WHERE SN = @xxbad_ship_id;

                --累加明细行的备料量
                UPDATE dbo.Barcode_Using_Detail
                SET AllotQty = ISNULL(AllotQty, 0) + @xxbad_qty
                WHERE SN = @xxbad_ship_id
                      AND PartNum = @xxbad_part;
                --修改入库单的状态为已入库
                UPDATE dbo.Barcode_UsingRequest
                SET Status = 2
                WHERE SN = @xxbad_ship_id;
                --如果入库量等于计划量 则关闭单据
                IF @SUMQTY10054 = @SUMQTY100542
                BEGIN
                    UPDATE dbo.Barcode_UsingRequest
                    SET Status = 5,
                        FinishTime = GETDATE(),
                        FinshUser =
                        (
                            SELECT TOP 1
                                   Name
                            FROM dbo.System_Administrator
                            WHERE LoginCode = @xxbad_user
                        )
                    WHERE SN = @xxbad_ship_id;
                END;
                RAISERROR(N'Info_MESSAGE#入库完成!#Storage completed!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;
            END;
            ELSE IF @ScanData = 'xxbad_toloc'
            BEGIN
                SELECT @xxbad_ship_id xxbad_ship_id,
                       @xxbad_id xxbad_id,
                       @xxbad_part xxbad_part,
                       @xxbad_desc xxbad_desc,
                       @xxbad_supplier xxbad_supplier,
                       @xxbad_qty xxbad_qty,
                       @xxbad_toloc xxbad_toloc,
                       @xxbad_fromloc xxbad_fromloc;
            END;
            ELSE
            BEGIN
                --从标签中加载信息  并且判断标签状态
                SELECT @xxbad_ship_id = WoNum,
                       @xxbad_id = USN,
                       @xxbad_part = PartNum,
                       @xxbad_desc = PartDescription,
                       @xxbad_supplier = CustomNum,
                       @xxbad_site = Site,
                       @xxbad_qty = Qty,
                       @InspectUser = InspectUser,
                       @InspectType = InspectType,
                       @InspectResult = InspectResult,
                       @xxbad_fromloc = CurrentLoc
                FROM Barocde_BoxlLable
                WHERE USN = @xxbad_id;

                IF (ISNULL(@xxbad_part, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不正确!#Invalid tag!', 11, 1);

                END;
                --判断标签关联的入库单的状态
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_UsingRequest
                    WHERE SN = @xxbad_ship_id
                          AND Status IN ( 1, 2, 3 )
                          AND FGorRM = 1
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#入库单状态不正确，请检查入库单状态!#The status of the inbound order is incorrect. Please check the status of the inbound order!', 11, 1);
                END;
                --返回第一个dataset到前台
                SELECT @xxbad_ship_id xxbad_ship_id,
                       @xxbad_id xxbad_id,
                       @xxbad_part xxbad_part,
                       @xxbad_desc xxbad_desc,
                       @xxbad_supplier xxbad_supplier,
                       @xxbad_qty xxbad_qty,
                       pt_loc xxbad_toloc,
                       @xxbad_fromloc xxbad_fromloc
                FROM pt_mstr
                WHERE pt_part = @xxbad_part
                      AND pt_domain = @xxbad_domain
                      AND pt_site = @xxbad_site;
            END;

        END;
        IF @interfaceid IN ( 97 ) --活动签到
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                SELECT 1;
            END;
            ELSE IF @ScanData = 'xxbad_id'
            BEGIN
                --判断工号是否存在
                SELECT @xxbad_extension1 = username
                FROM dbo.sys_user
                WHERE work_no = @xxbad_id;
                IF ISNULL(@xxbad_extension1, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#工号不正确!#Incorrect employee ID!', 11, 1);
                END;
                --判断当前人员是不是 在生产班组中
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.grouppeople
                    WHERE users = @xxbad_id
                          AND offtime IS NULL
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请先退出生产班组!#Please exit the production team first!', 11, 1);
                END;

                --然后判断当前人员是否在小组中 如果在则更新上下班时间 如果不在则自动加入当前小组
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.signuser
                    WHERE users = @xxbad_extension1
                          AND activityid = @xxbad_extension3
                          AND ISNULL(closeflag, 0) <> 1
                )
                BEGIN
                    --获取用户的主键id
                    SELECT TOP 1
                           @xxbad_extension8 = id
                    FROM dbo.signuser
                    WHERE users = @xxbad_extension1
                          AND activityid = @xxbad_extension3
                          AND ISNULL(closeflag, 0) <> 1;
                    --签到时间为空 自动签到
                    UPDATE dbo.signuser
                    SET ontime = GETDATE(),
                        closeflag = 0,
                        worknum = @xxbad_id
                    WHERE id = @xxbad_extension8
                          AND ontime IS NULL;
                    --如果签到时间不为空 签退时间为空 则更新签退时间 插入接口表
                    UPDATE dbo.signuser
                    SET offtime = GETDATE(),
                        worknum = @xxbad_id,
                        closeflag = 1
                    WHERE id = @xxbad_extension8
                          AND offtime IS NULL
                          AND ontime IS NOT NULL;
                    -- 签退得到时候  需要插入接口表
                    INSERT dbo.xxzxs_det
                    (
                        xxzxs_emp,
                        xxzxs_date,
                        xxzxs_time,
                        xxzxs_s_time,
                        xxzxs_e_time,
                        xxzxs_accode,
                        id,
                        uploadstatus
                    )
                    SELECT @xxbad_id,
                           GETDATE(),
                           DATEDIFF(MINUTE, ontime, offtime),
                           dbo.GetQADtime(ontime),
                           dbo.GetQADtime(offtime),
                           @xxbad_order,
                           NEWID(),
                           0
                    FROM signuser
                    WHERE id = @xxbad_extension8
                          AND offtime IS NOT NULL
                          AND ontime IS NOT NULL;
                END;
                ELSE
                BEGIN
                    --直接进组
                    INSERT INTO dbo.signuser
                    (
                        id,
                        create_by,
                        create_time,
                        users,
                        ontime,
                        activityid,
                        worknum
                    )
                    SELECT NEWID(),
                           'SCAN',
                           GETDATE(),
                           username,
                           GETDATE(),
                           @xxbad_extension3,
                           @xxbad_id
                    FROM dbo.sys_user
                    WHERE work_no = @xxbad_id;
                END;
                --返回第一个
                SELECT @xxbad_id xxbad_id,
                       'xxbad_id' focus,
                       name xxbad_order,
                       code xxbad_extension3,
                       (
                           SELECT COUNT(1) FROM signuser WHERE activityid = @xxbad_extension3
                       ) xxbad_extension4,
                       CONVERT(VARCHAR(10), starttime, 111) xxbad_shipdate,
                       CONVERT(VARCHAR(100), starttime, 108) xxbad_extension1,
                       CONVERT(VARCHAR(100), endtime, 108) xxbad_extension2
                FROM dbo.componyactivty
                WHERE name = @xxbad_order;
                --返回第二个
                SELECT users,
                       ontime,
                       offtime,
                       worknum
                FROM signuser
                WHERE activityid = @xxbad_extension3;
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus,
                       CONVERT(VARCHAR(12), GETDATE(), 111) xxbad_shipdate;

            END;
            ELSE IF @ScanData = 'xxbad_order'
            BEGIN
                SELECT name xxbad_order,
                       CONVERT(VARCHAR(10), starttime, 111) xxbad_shipdate,
                       code xxbad_extension3,
                       (
                           SELECT COUNT(1) FROM signuser WHERE activityid = @xxbad_order
                       ) xxbad_extension4,
                       CONVERT(VARCHAR(100), starttime, 108) xxbad_extension1,
                       CONVERT(VARCHAR(100), endtime, 108) xxbad_extension2
                FROM dbo.componyactivty
                WHERE code = @xxbad_order;
                --返回第二个
                SELECT users,
                       ontime,
                       offtime,
                       worknum
                FROM signuser
                WHERE activityid = @xxbad_order;
            END;

        END;
        IF @interfaceid IN ( 93 ) --库存查询
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                SELECT @xxbad_part xxbad_part,
                       @xxbad_loc xxbad_loc,
                       @xxbad_id xxbad_id;
                --返回第一个dataset到前台
                IF (@xxbad_part <> '' AND @xxbad_loc <> '')
                BEGIN
                    SELECT loc,
                           partnum,
                           lot,
                           qty
                    FROM dbo.barocde_stock
                    WHERE (
                              partnum = @xxbad_part
                              AND loc = @xxbad_loc
                          )
                          AND qty > 0;
                END;
                ELSE
                BEGIN
                    SELECT loc,
                           partnum,
                           lot,
                           qty
                    FROM dbo.barocde_stock
                    WHERE (
                              partnum = @xxbad_part
                              OR loc = @xxbad_loc
                          )
                          AND qty > 0;
                END;
            END;
            ELSE IF @ScanData = 'xxbad_id'
            BEGIN
                SELECT @xxbad_part = partnum
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    SELECT @xxbad_part = PartNum
                    FROM dbo.Barocde_BoxlLable
                    WHERE USN = @xxbad_id;
                END;
                SELECT @xxbad_part xxbad_part;
            END;
            ELSE IF @ScanData = 'xxbad_part'
            BEGIN
                SELECT @xxbad_part xxbad_part,
                       @xxbad_loc xxbad_loc;
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;

            END;
            ELSE IF @ScanData = 'xxbad_loc'
            BEGIN
                SELECT @xxbad_loc xxbad_loc,
                       @xxbad_part xxbad_part;
            END;

        END;
        IF @interfaceid IN ( 95 ) --班组打卡
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                SELECT 1;
            END;
            ELSE IF @ScanData = 'xxbad_id'
            BEGIN
                --判断工号是否存在
                SELECT @xxbad_extension1 = username
                FROM dbo.sys_user
                WHERE work_no = @xxbad_id;
                IF ISNULL(@xxbad_extension1, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#工号不正确!#Incorrect employee ID!', 11, 1);
                END;
                IF ISNULL(@xxbad_order, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请先选择小组!#Please select a group first!', 11, 1);
                END;
                --然后判断当前人员是否在小组中 如果在则更新上下班时间 如果不在则自动加入当前小组
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.grouppeople
                    WHERE users = @xxbad_extension1
                          AND groupid = @xxbad_order
                )
                BEGIN
                    UPDATE dbo.grouppeople
                    SET ontime = GETDATE(),
                        workno = @xxbad_id
                    WHERE users = @xxbad_extension1
                          AND groupid = @xxbad_order
                          AND ontime IS NULL;
                    --如果是 出组 需要 记录日志
                    INSERT INTO dbo.groupuserlog
                    (
                        id,
                        create_by,
                        create_time,
                        update_by,
                        update_time,
                        sys_org_code,
                        users,
                        ontime,
                        offtime,
                        groupid,
                        workno
                    )
                    SELECT id,
                           create_by,
                           create_time,
                           update_by,
                           update_time,
                           sys_org_code,
                           users,
                           ontime,
                           GETDATE(),
                           groupid,
                           @xxbad_id
                    FROM grouppeople
                    WHERE users = @xxbad_extension1
                          AND groupid = @xxbad_order
                          AND offtime IS NULL;
                    --存入备份表之后 删除
                    DELETE FROM dbo.grouppeople
                    WHERE users = @xxbad_extension1
                          AND groupid = @xxbad_order
                          AND offtime IS NULL
                          AND ontime IS NOT NULL;
                END;
                ELSE
                BEGIN
                    INSERT INTO dbo.grouppeople
                    (
                        id,
                        create_by,
                        create_time,
                        users,
                        ontime,
                        groupid,
                        workno
                    )
                    SELECT NEWID(),
                           'SCAN',
                           GETDATE(),
                           username,
                           GETDATE(),
                           @xxbad_order,
                           @xxbad_id
                    FROM dbo.sys_user
                    WHERE work_no = @xxbad_id;
                END;
                --第一个dataset
                SELECT 'xxbad_id' focus,
                       CONVERT(VARCHAR(12), GETDATE(), 111) xxbad_shipdate,
                       @xxbad_order xxbad_order,
                       SUM(1) xxbad_extension3
                FROM grouppeople
                WHERE groupid = @xxbad_order;
                --第二个dataset
                SELECT b.realname users,
                       ontime,
                       offtime,
                       workno
                FROM grouppeople
                    LEFT JOIN dbo.sys_user b
                        ON users = b.username
                WHERE groupid = @xxbad_order;
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus,
                       CONVERT(VARCHAR(12), GETDATE(), 111) xxbad_shipdate;

            END;
            ELSE IF @ScanData = 'xxbad_order'
            BEGIN
                SELECT @xxbad_order xxbad_order,
                       SUM(1) xxbad_extension3
                FROM grouppeople
                WHERE groupid = @xxbad_order;
                --返回第二个dataset
                SELECT b.realname users,
                       ontime,
                       offtime,
                       workno
                FROM grouppeople
                    LEFT JOIN dbo.sys_user b
                        ON users = b.username
                WHERE groupid = @xxbad_order;
            END;

        END;
        IF @interfaceid IN ( 96 ) --工单统计
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --限制班组 同一时间点 只能生产一个工单
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM groupwocost
                    WHERE groupid = @xxbad_order
                          AND sn = @xxbad_extension1
                          AND endtime IS NULL
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前加工波次不需要结束!#The current processing batch does not need to end!', 11, 1);
                END;
                --结束工单的时候 必须限制 工单小组里面 有人员
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM grouppeople
                    WHERE groupid = @xxbad_order
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前小组没有任何人员!#There are no members in the current group!', 11, 1);
                END;
                --IF @xxbad_op IS NULL
                --            BEGIN
                --               RAISERROR(N'ERROR_MESSAGE#You must select a process!#You must select a process!', 11, 1);
                --            END;
                --结束工单 按钮
                UPDATE groupwocost
                SET endtime = GETDATE(),
                    xxbad_op = @xxbad_op
                WHERE groupid = @xxbad_order
                      AND sn = @xxbad_extension1
                      AND endtime IS NULL;
                --插入接口表
                INSERT dbo.xxwr_det
                (
                    id,
                    xxwr_line,
                    xxwr_s_time,
                    xxwr_date,
                    xxwr_time,
                    xxwr_name,
                    xxwr_site,
                    xxwr_woid,
                    xxwr_emp,
                    xxwr_e_time,
                    uploadstatus,
                    create_time,
                    xxwr_op
                )
                SELECT NEWID(),
                       c.Line,
                       dbo.GetQADtime(a.starttime),
                       GETDATE(),
                       DATEDIFF(MINUTE, a.starttime, a.endtime),
                       d.realname,
                       @xxbad_site,
                       a.wonum,
                       d.work_no,
                       dbo.GetQADtime(ISNULL(b.offtime, a.endtime)),
                       0,
                       GETDATE(),
                       @xxbad_op
                FROM groupwocost a
                    LEFT JOIN grouppeople b
                        ON a.groupid = b.groupid
                    LEFT JOIN FGWorkPlan c
                        ON a.wonum = c.WoNum
                    LEFT JOIN sys_user d
                        ON d.username = b.users
                WHERE a.groupid = @xxbad_order
                      AND a.sn = @xxbad_extension1;
                --返回第一个data
                SELECT TOP 1
                       @xxbad_order xxbad_order,
                       @xxbad_shipdate xxbad_shipdate,
                       'xxbad_woid' focus,
                       '结束成功' xxbad_rmks,
                       wonum xxbad_woid,
                       sn xxbad_extension1
                FROM groupwocost
                WHERE groupid = @xxbad_order
                      AND endtime IS NULL;
                --返回第二个
                SELECT sn,
                       starttime,
                       endtime,
                       wonum
                FROM groupwocost
                WHERE groupid = @xxbad_order
                      AND endtime IS NULL
                ORDER BY sn;
            END;
            ELSE IF @ScanData = 'xxbad_woid' --加工单号
            BEGIN
                --判断加工单 是不是存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.FGWorkPlan
                    WHERE WoNum = @xxbad_woid
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#加工单不正确!#Processing order is incorrect!', 11, 1);
                END;

                --判断班组 是不是选择了
                IF ISNULL(@xxbad_order, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请先选择班组!#Please select a team first!', 11, 1);
                END;
                --限制班组 同一时间点 只能生产一个工单
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM groupwocost
                    WHERE groupid = @xxbad_order
                          AND wonum = @xxbad_woid
                          AND endtime IS NULL
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前班组不能重复生产当前工单!#The current team cannot repeatedly produce the current work order!', 11, 1);
                END;
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM groupwocost
                    WHERE groupid = @xxbad_order
                          AND endtime IS NULL
                )
                   AND EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.workgroup
                    WHERE id = @xxbad_order
                          AND line IN
                              (
                                  SELECT LineCode FROM dbo.ProdLine WHERE Type = 1
                              )
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#前工程当前班组正在生产其他工单!#The previous process's current team is working on another order!', 11, 1);
                END;

                --生成加工波次
                DECLARE @wobatch VARCHAR(50) = 'P1';
                SELECT @wobatch = 'P' + CONVERT(VARCHAR(50), ISNULL(COUNT(1), 1))
                FROM dbo.groupwocost
                WHERE groupid = @xxbad_order;

                --插入明细表
                INSERT dbo.groupwocost
                (
                    id,
                    create_by,
                    create_time,
                    sn,
                    wonum,
                    starttime,
                    groupid,
                    xxbad_op
                )
                SELECT NEWID(),
                       'scan',
                       GETDATE(),
                       @wobatch,
                       WoNum,
                       GETDATE(),
                       @xxbad_order,
                       @xxbad_op
                FROM dbo.FGWorkPlan
                WHERE wonum = @xxbad_woid;
                --返回第一个dataset
                SELECT @xxbad_order xxbad_order,
                       @xxbad_shipdate xxbad_shipdate,
                       --wonum xxbad_woid,
                       @wobatch xxbad_extension1,
                       xxbad_op,
                       starttime xxbad_extension2,
                       endtime xxbad_extension3
                FROM groupwocost
                WHERE sn = @wobatch;
                --返回第二个
                SELECT TOP 20
                       sn,
                       starttime,
                       endtime,
                       wonum
                FROM groupwocost
                WHERE groupid = @xxbad_order
                      AND endtime IS NULL
                ORDER BY sn;
            --END;
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_woid' focus,
                       CONVERT(VARCHAR(12), GETDATE(), 111) xxbad_shipdate;
                SELECT 1;
            END;
            ELSE IF @ScanData = 'xxbad_order'
            BEGIN
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM groupwocost
                    WHERE groupid = @xxbad_order
                          AND endtime IS NULL
                )
                BEGIN
                    --返回第一个dataset
                    SELECT @xxbad_order xxbad_order,
                           CONVERT(VARCHAR(12), GETDATE(), 111) xxbad_shipdate,
                           wonum xxbad_woid,
                           sn xxbad_extension1,
                           xxbad_op,
                           starttime xxbad_extension2,
                           endtime xxbad_extension3
                    FROM groupwocost
                    WHERE groupid = @xxbad_order
                          AND endtime IS NULL;
                END;
                ELSE
                BEGIN
                    SELECT @xxbad_order xxbad_order;
                    SELECT 1;
                END;
                --返回第二个
                SELECT TOP 20
                       sn,
                       starttime,
                       endtime,
                       wonum
                FROM groupwocost
                WHERE groupid = @xxbad_order
                      AND endtime IS NULL
                ORDER BY sn;
            END;
        END;

        IF @interfaceid IN ( 94 ) --标签查询
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                SELECT @xxbad_part xxbad_part,
                       @xxbad_loc xxbad_loc;
                --返回第一个dataset到前台
                IF (@xxbad_part <> '' AND @xxbad_loc <> '')
                BEGIN
                    SELECT currentloc loc,
                           partnum,
                           usn,
                           qty
                    FROM dbo.barocde_materiallable
                    WHERE (
                              partnum = @xxbad_part
                              AND currentloc = @xxbad_loc
                          )
                          AND qty > 0
                    UNION ALL
                    SELECT CurrentLoc loc,
                           PartNum,
                           USN,
                           Qty
                    FROM dbo.Barocde_BoxlLable
                    WHERE (
                              PartNum = @xxbad_part
                              AND CurrentLoc = @xxbad_loc
                          )
                          AND Qty > 0;
                END;
                ELSE
                BEGIN
                    SELECT currentloc loc,
                           partnum,
                           usn,
                           qty
                    FROM dbo.barocde_materiallable
                    WHERE (
                              partnum = @xxbad_part
                              OR currentloc = @xxbad_loc
                          )
                          AND qty > 0
                    UNION ALL
                    SELECT CurrentLoc loc,
                           PartNum,
                           USN,
                           Qty
                    FROM dbo.Barocde_BoxlLable
                    WHERE (
                              PartNum = @xxbad_part
                              OR CurrentLoc = @xxbad_loc
                          )
                          AND Qty > 0;
                END;
            END;
            ELSE IF @ScanData = 'xxbad_id'
            BEGIN
                SELECT @xxbad_part = partnum
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
                SELECT '' xxbad_id;
                SELECT currentloc loc,
                       partnum,
                       usn,
                       qty
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id
                UNION ALL
                SELECT CurrentLoc loc,
                       PartNum,
                       USN,
                       Qty
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;

            END;
            ELSE IF @ScanData = 'xxbad_part'
            BEGIN
                SELECT @xxbad_part xxbad_part;
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;

            END;
            ELSE IF @ScanData = 'xxbad_loc'
            BEGIN
                SELECT @xxbad_loc xxbad_loc;
            END;

        END;

        IF @interfaceid IN ( 99 ) --领料单查询
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --返回第一个dataset到前台
                SELECT @xxbad_id xxbad_id;
                --返回第二个dataset到前台
                SELECT ps_comp,
                       UsingQty,
                       PlanQty
                FROM HSProdusing
                WHERE UsingNum = @xxbad_id;
            END;
            ELSE IF @ScanData = 'xxbad_id'
            BEGIN
                SELECT @xxbad_id xxbad_id;
                --返回第二个dataset到前台
                SELECT ps_comp,
                       ISNULL(UsingQty, 0) usingqty,
                       PlanQty
                FROM HSProdusing
                WHERE UsingNum = @xxbad_id;
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;
            END;
        END;
        IF @interfaceid IN ( 10062 ) --线边标签复制
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断当前零件当前批次当前酷我线边库存是否足够  暂时不判断，因为老系统导入库存
                DECLARE @stockqty DECIMAL;
                SELECT @stockqty = SUM(qty)
                FROM dbo.barocde_stock b
                WHERE b.partnum = @xxbad_part
                      AND b.lot = @xxbad_lot
                      AND b.loc = @xxbad_loc;
                IF ISNULL(@stockqty, 0) < ISNULL(@xxbad_qty, 0)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前零件当前批次线边库存不足，请核查!#Current batch line-side inventory of the part is insufficient, please check!', 11, 1);

                END;
                --生成一个新的标签号
                DECLARE @fid VARCHAR(50);
                CREATE TABLE #t2
                (
                    fid VARCHAR(30)
                );
                SELECT @xxbad_status = pt_pm_code
                FROM dbo.pt_mstr
                WHERE pt_part = @xxbad_part;
                IF (ISNULL(@xxbad_status, '') = 'P')
                BEGIN
                    --取出最大当前供应商当天最大的标签ID 在此基础上面递增
                    INSERT INTO #t2
                    EXEC [MakeSeqenceNum] '00000001', @xxbad_supplier;
                    SELECT @fid = fid
                    FROM #t2;
                    --判断标签是否合法
                    IF ISNULL(@fid, '') = ''
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#系统出错，生成的标签为空!#System error, generated label is empty!', 11, 1);

                    END;
                    --复制插入标签表
                    INSERT INTO barocde_materiallable
                    (
                        [usn],
                        [partnum],
                        partdescription,
                        site,
                        [toloc],
                        lot,
                        [qty],
                        [memo],
                        [ponum],
                        [poline],
                        [pkgqty],
                        supplynum,
                        [supplypartnum],
                        [supplyname],
                        [createtime],
                        po_duedate,
                        inspecttype,
                        whloc,
                        supplylot,
                        shipsn,
                        currentloc,
                        status
                    )
                    SELECT @fid,
                           partnum,
                           partdescription,
                           site,
                           toloc,
                           @xxbad_lot,
                           @xxbad_qty,
                           '线边条码复制',
                           [ponum],
                           [poline],
                           [pkgqty],
                           supplynum,
                           [supplypartnum],
                           [supplyname],
                           GETDATE(),
                           po_duedate,
                           inspecttype,
                           whloc,
                           supplylot,
                           shipsn,
                           @xxbad_loc,
                           4
                    FROM dbo.barocde_materiallable
                    WHERE usn = @xxbad_id;
                    --调用单标签打印的功能 打印标签
                    EXEC PrintMaterialLable @fid;
                END;
                ELSE
                BEGIN
                    --判断是不是半成品
                    IF LEFT(@xxbad_part, 2) = 'SF'
                    BEGIN
                        INSERT INTO #t2
                        EXEC [MakeSeqenceNum] '00000001', 'WS8888';
                    END;
                    ELSE
                    BEGIN
                        INSERT INTO #t2
                        EXEC GetFGSeqenceNum @xxbad_supplier, @xxbad_part, 1;
                    END;
                    SELECT @fid = fid
                    FROM #t2;
                    --判断标签是否合法
                    IF ISNULL(@fid, '') = ''
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#系统出错，生成的标签为空!#System error, generated label is empty!', 11, 1);

                    END;
                    INSERT INTO Barocde_BoxlLable
                    (
                        [USN],
                        [PartNum],
                        PartDescription,
                        Lot,
                        ProLine,
                        CurrentLoc,
                        [Qty],
                        [WoNum],
                        [Wo_DueDate],
                        [PkgQty],
                        Status,
                        CustomNum,
                        CustomName,
                        CreateTime,
                        Site,
                        SupplyNum,
                        CustomPO,
                        ShipTo,
                        DockLoaction,
                        CustomPartNum,
                        ExtendFiled2,
                        Memo
                    )
                    SELECT @fid,
                           PartNum,
                           PartDescription,
                           @xxbad_lot,
                           ProLine,
                           @xxbad_loc,
                           @xxbad_qty,
                           WoNum,
                           [Wo_DueDate],
                           [PkgQty],
                           3,
                           CustomNum,
                           CustomName,
                           GETDATE(),
                           Site,
                           SupplyNum,
                           CustomPO,
                           ShipTo,
                           DockLoaction,
                           CustomPartNum,
                           ExtendFiled2,
                           '线边条码复制'
                    FROM Barocde_BoxlLable
                    WHERE USN = @xxbad_id;
                    --调用单标签打印的功能 打印标签
                    EXEC dbo.PrintFGLable @@IDENTITY, '1594943751915634689';
                END;

                RAISERROR(N'Info_MESSAGE#复制成功!#Copy successful!', 11, 1);

            END;
            ELSE IF @ScanData = 'xxbad_part'
            BEGIN
                SELECT @xxbad_desc = pt_desc1,
                       @xxbad_status = pt_pm_code
                FROM dbo.pt_mstr
                WHERE pt_part = @xxbad_part;
                IF (ISNULL(@xxbad_status, '') = 'P')
                BEGIN
                    --生成JSON
                    SET @json =
                    (
                        SELECT DISTINCT
                               usn text,
                               usn value,
                               usn title
                        FROM dbo.barocde_materiallable
                        WHERE partnum = @xxbad_part
                        FOR JSON PATH
                    );
                END;
                ELSE
                BEGIN
                    SET @json =
                    (
                        SELECT DISTINCT
                               USN text,
                               USN value,
                               USN title
                        FROM dbo.Barocde_BoxlLable
                        WHERE PartNum = @xxbad_part
                        FOR JSON PATH
                    );
                END;
                SELECT @xxbad_desc xxbad_desc,
                       @xxbad_part xxbad_part,
                       @json xxbad_id_s;
                SELECT 1;
            END;
            ELSE IF @ScanData = 'xxbad_id'
            BEGIN
                SELECT @xxbad_desc = pt_desc1,
                       @xxbad_status = pt_pm_code
                FROM dbo.pt_mstr
                WHERE pt_part = @xxbad_part;
                IF (ISNULL(@xxbad_status, '') = 'P')
                BEGIN
                    --否则是标签号的翻动
                    SELECT supplynum xxbad_supplier,
                           destroytime xxbad_time,
                           lot xxbad_lot,
                           a.partnum xxbad_part,
                           a.qty xxbad_qty,
                           a.supplylot xxbad_shipper_lot
                    FROM dbo.barocde_materiallable a
                    WHERE usn = @xxbad_id;
                END;
                ELSE
                BEGIN
                    --否则是标签号的翻动
                    SELECT a.CustomNum xxbad_supplier,
                           DestroyTime xxbad_time,
                           Lot xxbad_lot,
                           a.PartNum xxbad_part,
                           a.Qty xxbad_qty,
                           a.CustomLot xxbad_shipper_lot
                    FROM dbo.Barocde_BoxlLable a
                    WHERE USN = @xxbad_id;
                END;


            END;
        END;
        IF @interfaceid IN ( 10068 ) --成品通用移库
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN

                --读取标签中的信息
                SELECT @xxbad_fromloc = CurrentLoc,
                       @xxbad_lot = Lot,
                       @xxbad_part = PartNum,
                       @xxbad_qty = Qty
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id
                      AND Status = 3;
                --判断标签是否合法
                IF ISNULL(@xxbad_fromloc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;

                --判断当前 库存 是否足够移库
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.barocde_stock
                    WHERE partnum = @xxbad_part
                          AND loc = @xxbad_fromloc
                          AND lot = @xxbad_lot
                          AND qty >= @xxbad_qty
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#从库位没有足够此批次的零件移库!#There are not enough parts of this batch in the storage location for transfer!', 11, 1);

                END;
                --判断当前库位 是否和到库位相同
                IF (ISNULL(@xxbad_fromloc, '') = ISNULL(@xxbad_toloc, ''))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前标签已经在到库位下面了!#The current label is already under the destination location!', 11, 1);

                END;
                --更新标签的库位
                UPDATE dbo.Barocde_BoxlLable
                SET FromLoc = CurrentLoc,
                    CurrentLoc = @xxbad_toloc
                WHERE USN = @xxbad_id;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg]
                )
                SELECT @xxbad_domain,
                       'IC_TR',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       dbo.GetQADloc(@xxbad_fromloc),
                       dbo.GetQADloc(@xxbad_toloc),
                       Lot,
                       Lot,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       USN,
                       Qty
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       USN,
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       @xxbad_fromloc,
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       @xxbad_id,
                       Qty,
                       Lot,
                       Lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                RAISERROR(N'Info_MESSAGE#提交成功!#Submission successful!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_toloc' READONLY;

            END;
            ELSE IF @ScanData = 'xxbad_toloc'
            BEGIN
                --判断库位是否合法
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_Location
                    WHERE xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    SELECT 'xxbad_toloc' READONLY;
                END;
                ELSE
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#库位不存在!#Location does not exist!', 11, 1);

                END;
            END;
            ELSE --认为扫描的是条码数据
            BEGIN
                --读取标签中的信息
                SELECT @xxbad_id = USN,
                       @xxbad_qty = Qty,
                       @xxbad_status = Status,
                       @xxbad_part = PartNum,
                       @xxbad_desc = PartDescription,
                       @xxbad_fromloc = CurrentLoc
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;

                --判断标签是否合法
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                --判断标签是否合法
                IF ISNULL(@xxbad_status, '0') <> '3'
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#必须是上架到仓库的箱码才能移库!#Only box codes that are stocked in the warehouse can be transferred!', 11, 1);

                END;
                --判断零件是否可以移库到到库位
                SELECT @msg_error = dbo.CheckLocArea(@xxbad_part, @xxbad_toloc, 1);
                IF ISNULL(@msg_error, '') <> ''
                BEGIN
                    RAISERROR(@msg_error, 11, 1);

                END;
                --判断零件是否可以从从库位移除
                SELECT @msg_error = dbo.CheckLocArea(@xxbad_part, @xxbad_fromloc, 0);
                IF ISNULL(@msg_error, '') <> ''
                BEGIN
                    RAISERROR(@msg_error, 11, 1);

                END;
                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       @xxbad_qty xxbad_qty,
                       @xxbad_part xxbad_part,
                       @xxbad_desc xxbad_desc,
                       @xxbad_fromloc xxbad_fromloc,
                       @xxbad_toloc xxbad_toloc;
            END;

        END;
        IF @interfaceid IN ( 10069 ) --原材料自由移库
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --读取标签中的信息
                SELECT @xxbad_fromloc = currentloc,
                       @xxbad_lot = lot,
                       @xxbad_part = partnum,
                       @xxbad_qty = qty
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id
                      AND status IN ( 3, 4 );
                --判断标签是否合法
                IF ISNULL(@xxbad_fromloc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;

                --判断当前库位 是否和到库位相同
                IF (ISNULL(@xxbad_fromloc, '') = ISNULL(@xxbad_toloc, ''))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前标签已经在到库位下面了!#The current label is already under the destination location!', 11, 1);

                END;
                --更新标签的库位
                UPDATE dbo.barocde_materiallable
                SET fromloc = currentloc,
                    currentloc = @xxbad_toloc
                WHERE usn = @xxbad_id;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg]
                )
                SELECT @xxbad_domain,
                       'IC_TR',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       '',
                       partnum,
                       dbo.GetQADloc(@xxbad_fromloc),
                       dbo.GetQADloc(@xxbad_toloc),
                       lot,
                       lot,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       usn,
                       qty
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       usn,
                       @xxbad_user,
                       '',
                       '',
                       partnum,
                       @xxbad_fromloc,
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       @xxbad_id,
                       qty,
                       lot,
                       lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
                RAISERROR(N'Info_MESSAGE#提交成功!#Submission successful!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_toloc' focus;
            END;
            ELSE IF @ScanData = 'xxbad_toloc'
            BEGIN
                --判断库位是否合法
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_Location
                    WHERE xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    SELECT 'xxbad_id' focus,
                           @xxbad_toloc xxbad_toloc;
                END;
                ELSE
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#库位不存在!#Location does not exist!', 11, 1);
                END;
            END;
            ELSE --认为扫描的是条码数据
            BEGIN
                --读取标签中的信息
                SELECT @xxbad_id = usn,
                       @xxbad_qty = qty,
                       @xxbad_status = status,
                       @xxbad_part = partnum,
                       @xxbad_desc = partdescription,
                       @xxbad_fromloc = currentloc
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;

                --判断标签是否合法
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;

                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       @xxbad_qty xxbad_qty,
                       @xxbad_part xxbad_part,
                       @xxbad_desc xxbad_desc,
                       @xxbad_fromloc xxbad_fromloc,
                       @xxbad_toloc xxbad_toloc;
            END;
        END;
        IF @interfaceid IN ( 10108 ) --成品箱码退货
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN

                --读取标签中的信息
                SELECT @xxbad_fromloc = CurrentLoc,
                       @xxbad_lot = Lot,
                       @xxbad_part = PartNum,
                       @xxbad_saleship_id = ShipSN,
                       @xxbad_order = PurchaseOrder,
                       @xxbad_line = PoLine,
                       @xxbad_qty = Qty
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;

                --判断标签是否合法
                IF ISNULL(@xxbad_fromloc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);
                END;

                --判断能否获取到合格的装柜计划明细
                SELECT TOP 1
                       @xxbad_ship_id = id
                FROM dbo.Barcode_SOShippingDetail
                WHERE ShipSN = @xxbad_saleship_id
                      AND PurchaseOrder = @xxbad_order
                      AND Line = @xxbad_line
                      AND AllotQty >= @xxbad_qty;

                IF ISNULL(@xxbad_ship_id, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签没有关联到订单行，不能退货!#The label is not associated with the order line, return is not possible!', 11, 1);
                END;
                --如果有明细行 减去备料量
                UPDATE Barcode_SOShippingDetail
                SET AllotQty = ISNULL(AllotQty, 0) - @xxbad_qty
                WHERE id = @xxbad_ship_id;
                --减去销售订单行的数量
                UPDATE sod_det
                SET sod_qty_ship = ISNULL(sod_qty_ship, 0) - @xxbad_qty,
                    sod_shipQty = ISNULL(sod_shipQty, 0) - @xxbad_qty
                FROM sod_det
                WHERE sod_nbr = @xxbad_order
                      AND sod_line = @xxbad_line;
                --判断当前 库存 是否足够移库
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.barocde_stock
                    WHERE partnum = @xxbad_part
                          AND loc = @xxbad_fromloc
                          AND lot = @xxbad_lot
                          AND qty >= @xxbad_qty
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#从库位没有足够此批次的零件移库!#There are not enough parts of this batch in the storage location for transfer!', 11, 1);
                END;
                --判断当前库位 是否和到库位相同
                IF (ISNULL(@xxbad_fromloc, '') = ISNULL(@xxbad_toloc, ''))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前标签已经在到库位下面了!#The current label is already under the destination location!', 11, 1);
                END;
                --更新标签的库位
                UPDATE dbo.Barocde_BoxlLable
                SET FromLoc = CurrentLoc,
                    Status = 3,
                    CurrentLoc = @xxbad_toloc
                WHERE USN = @xxbad_id;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg]
                )
                SELECT @xxbad_domain,
                       'IC_TR',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       @xxbad_order,
                       @xxbad_line,
                       PartNum,
                       dbo.GetQADloc(@xxbad_fromloc),
                       dbo.GetQADloc(@xxbad_toloc),
                       Lot,
                       Lot,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       USN,
                       Qty
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       USN,
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       @xxbad_fromloc,
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       @xxbad_id,
                       Qty,
                       Lot,
                       Lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                RAISERROR(N'Info_MESSAGE#提交成功!#Submission successful!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_toloc' focus;

            END;
            ELSE IF @ScanData = 'xxbad_toloc'
            BEGIN
                --判断库位是否合法
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_Location
                    WHERE xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    SELECT @xxbad_toloc xxbad_toloc;
                END;
                ELSE
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#库位不存在!#Location does not exist!', 11, 1);

                END;
            END;
            ELSE --认为扫描的是条码数据
            BEGIN
                --读取标签中的信息
                SELECT @xxbad_id = USN,
                       @xxbad_qty = Qty,
                       @xxbad_status = Status,
                       @xxbad_part = PartNum,
                       @xxbad_saleship_id = ShipSN,
                       @xxbad_order = PurchaseOrder,
                       @xxbad_line = PoLine,
                       @xxbad_desc = PartDescription,
                       @xxbad_fromloc = CurrentLoc
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;

                --判断标签是否合法
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                --判断标签是否合法
                IF ISNULL(@xxbad_status, '0') <> '5'
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#必须是销售出去的标签，才能退货!#Only sold tags can be returned!', 11, 1);
                END;
                --判断标签是否合法
                IF ISNULL(@xxbad_order, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签没有关联到订单行，不能退货!#The label is not associated with the order line, return is not possible!', 11, 1);
                END;
                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       @xxbad_qty xxbad_qty,
                       @xxbad_part xxbad_part,
                       @xxbad_desc xxbad_desc,
                       @xxbad_saleship_id xxbad_saleship_id,
                       @xxbad_order xxbad_order,
                       @xxbad_line xxbad_line,
                       @xxbad_fromloc xxbad_fromloc,
                       @xxbad_toloc xxbad_toloc;
            END;

        END;
        IF @interfaceid IN ( 10104 ) --原材料退库移库
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --   暂停这个功能的使用

                RAISERROR(N'ERROR_MESSAGE#暂停这个功能的使用，请使用其他功能!#This feature is temporarily unavailable. Please use other features!', 11, 1);
                --读取标签中的信息
                SELECT @xxbad_fromloc = currentloc,
                       @xxbad_lot = lot,
                       @xxbad_part = partnum,
                       @xxbad_qty = qty
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;

                --判断标签是否合法
                IF ISNULL(@xxbad_lot, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;

                --判断当前 库存 是否足够移库
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.barocde_stock
                    WHERE partnum = @xxbad_part
                          AND loc = @xxbad_fromloc
                          AND lot = @xxbad_lot
                          AND qty >= @xxbad_qty
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#从库位没有足够此批次的零件移库!#There are not enough parts of this batch in the storage location for transfer!', 11, 1);

                END;
                --判断当前库位 是否和到库位相同
                IF (ISNULL(@xxbad_fromloc, '') = ISNULL(@xxbad_toloc, ''))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前标签已经在到库位下面了!#The current label is already under the destination location!', 11, 1);

                END;
                --更新标签的库位
                UPDATE dbo.barocde_materiallable
                SET fromloc = currentloc,
                    currentloc = @xxbad_toloc
                WHERE usn = @xxbad_id;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg]
                )
                SELECT @xxbad_domain,
                       'IC_TR',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       '',
                       partnum,
                       dbo.GetQADloc(@xxbad_fromloc),
                       dbo.GetQADloc(@xxbad_toloc),
                       lot,
                       lot,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       usn,
                       qty
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       usn,
                       @xxbad_user,
                       '',
                       '',
                       partnum,
                       @xxbad_fromloc,
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       @xxbad_id,
                       qty,
                       lot,
                       lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
                RAISERROR(N'Info_MESSAGE#提交成功!#Submission successful!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus,
                       'tkq' xxbad_toloc;

            END;
            --ELSE IF @ScanData = 'xxbad_toloc'
            --BEGIN
            --    --判断库位是否合法
            --        SELECT 'xxbad_id' focus,
            --       @xxbad_toloc xxbad_toloc;
            --END;
            ELSE --认为扫描的是条码数据
            BEGIN
                --读取标签中的信息
                SELECT @xxbad_id = usn,
                       @xxbad_qty = qty,
                       @xxbad_status = status,
                       @xxbad_fromloc = currentloc,
                       @xxbad_part = partnum,
                       @xxbad_desc = partdescription,
                       @xxbad_fromloc = currentloc
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
                RAISERROR(N'ERROR_MESSAGE#暂停这个功能的使用，请使用其他功能!#This feature is temporarily unavailable. Please use other features!', 11, 1);
                --判断标签是否合法
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;

                --判断 有没有垮库区
                IF (dbo.GetQADloc(@xxbad_fromloc) <> dbo.GetQADloc(@xxbad_toloc))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#从库位和到库位的库区相同，不能使用此功能!#The source and destination storage areas are the same, this function cannot be used!', 11, 1);

                END;
                --IF NOT EXISTS
                --(
                --    SELECT TOP 1
                --           1
                --    FROM dbo.ProdLine
                --    WHERE LineCode = @xxbad_toloc
                --)
                --BEGIN
                --    RAISERROR(N'ERROR_MESSAGE#从库位必须是产线库位!#The source location must be a production line location!', 11, 1);

                --END;
                ----判断零件是否可以移库到到库位
                --SELECT @msg_error
                --    = dbo.CheckLocArea(@xxbad_part, @xxbad_toloc, 1);
                --IF ISNULL(@msg_error, '') <> ''
                --BEGIN
                --    RAISERROR(@msg_error, 11, 1);
                --    
                --END;
                ----判断零件是否可以从从库位移除
                --SELECT @msg_error
                --    = dbo.CheckLocArea(@xxbad_part, @xxbad_fromloc, 0);
                --IF ISNULL(@msg_error, '') <> ''
                --BEGIN
                --    RAISERROR(@msg_error, 11, 1);
                --    
                --END;
                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       @xxbad_qty xxbad_qty,
                       @xxbad_part xxbad_part,
                       @xxbad_desc xxbad_desc,
                       @xxbad_fromloc xxbad_fromloc,
                       @xxbad_toloc xxbad_toloc;
            END;

        END;
        --全局调试代码
        IF (@interfaceid = 100720)
        BEGIN
            PRINT @xxbad_op;
            PRINT CONVERT(VARCHAR, @xxbad_op);
            IF @xxbad_op IS NULL
            BEGIN
                RAISERROR(N'ERROR_MESSAGE#You must select whether it is qualified!#You must select whether it is qualified!', 11, 1);

            END;
        END;
        DECLARE @CustomBarcode VARCHAR(50) = ''; --编码规则
        IF @interfaceid IN ( 10072 ) --半成品装篮下线
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断包装量量不能是0
                IF ISNULL(@xxbad_qty, 0) = 0
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#包装量不能为空或者0!#The packaging quantity cannot be empty or zero!', 11, 1);

                END;
                --将包装量缓存起来
                SET @xxbad_scrapqty = @xxbad_qty;
                --篮数 乘以包装量 得到总量
                SET @xxbad_qty = CONVERT(INT, @xxbad_qty) * CONVERT(INT, @xxbad_rj_qty);
                --判断是否超量生成标签
                DECLARE @Makeqty DECIMAL;
                DECLARE @Planqty DECIMAL;
                DECLARE @pkgqty DECIMAL;
                DECLARE @CustomID VARCHAR(50);
                --获取产线的下线库位
                DECLARE @Loc VARCHAR(50); --下线库位
                SELECT TOP 1
                       @Makeqty = ISNULL(MakeQty, 0),
                       @Planqty = PlanQty,
                       @Loc = Line,
                       @xxbad_desc = PartDesc,
                       @xxbad_ship_id = wo_lot,
                       @CustomID = Customer
                FROM dbo.FGWorkPlan
                WHERE WoNum = @xxbad_extension3;
                --IF CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_qty, 0)) + @Makeqty > CONVERT(DECIMAL(18, 5), @Planqty)
                --BEGIN
                --    RAISERROR(N'ERROR_MESSAGE#下线总量不能超出计划量!#Pick List is complete!', 11, 1);

                --END;

                IF ISNULL(@Loc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#The offline storage location of the production line does not exist!#The offline storage location of the production line does not exist!', 11, 1);
                END;
                IF ISNULL(@xxbad_desc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#零件描述不能为空!#The part description cannot be empty!', 11, 1);
                END;
                IF @xxbad_op IS NULL
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#You must select whether it is qualified!#You must select whether it is qualified!', 11, 1);

                END;
                --如果选择了不合格 一定要指定不合格原因
                IF @xxbad_op IS NOT NULL
                   AND @xxbad_op <> 1
                BEGIN
                    PRINT @xxbad_op;
                    PRINT @xxbad_rmks;
                    IF ISNULL(@xxbad_extension8, '') = ''
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#必须输入不合格原因!#The reason for disqualification must be entered!', 11, 1);
                    END;
                END;
                --首先判断 是否设置回冲BOM
                --取出当前零件的BOM到临时表
                SELECT ps_comp,
                       ps_qty_per * @xxbad_qty ps_qty_per
                INTO #ps_mstr10072
                FROM dbo.WOps_mstr
                WHERE WoNum = @xxbad_extension3;
                --判断BOM是否存在
                --IF NOT EXISTS (SELECT TOP 1 1 FROM #ps_mstr10072)
                --BEGIN
                --    SET @xxbad_rmks = '警告：总成BOM缺失,';
                --END;
                --标签序列号规则
                IF ISNULL(@CustomBarcode, '') = ''
                BEGIN
                    SET @CustomBarcode = '00000023';
                END;

                --汇总 得到线边库存情况
                --SELECT partnum,
                --       SUM(CONVERT(DECIMAL(18, 5), qty)) Qty
                --INTO #Barocde_Stock10072
                --FROM bcpupmaterial
                --WHERE loc = @Loc
                --GROUP BY partnum;
                --查询缺少的原材料
                --DECLARE @lesspart10072 VARCHAR(2000) = '';
                --SELECT @lesspart10072 = COALESCE(a.ps_comp + '|', '')
                --FROM #ps_mstr10072 a
                --    LEFT JOIN #Barocde_Stock10072 b
                --        ON b.partnum = a.ps_comp
                --WHERE a.ps_qty_per > 0
                --      AND
                --      (
                --          b.Qty < a.ps_qty_per
                --          OR b.Qty = 0
                --          OR b.partnum IS NULL
                --      );
                --SET @ErrorMessage
                --    = N'ERROR_MESSAGE#' + @lesspart10072 + N'预判断线边库存不足，无法下线!#' + @lesspart10072 + N'Pre-judgment: Insufficient line-side inventory, unable to proceed!';

                ----判断在线库存是否不足
                --IF (ISNULL(@lesspart10072, '') <> '')
                --BEGIN
                --    RAISERROR(@ErrorMessage, 11, 1);

                --END;
                DECLARE @batch VARCHAR(64) = NEWID();

                --循环生成标签号 存入临时表#t1
                DECLARE @fi INT = 1;
                CREATE TABLE #sflable
                (
                    fid VARCHAR(30)
                );
                WHILE @fi <= CONVERT(INT, @xxbad_rj_qty)
                BEGIN
                    TRUNCATE TABLE #sflable;
                    INSERT INTO #sflable
                    EXEC [MakeSeqenceNum] '00000023', @xxbad_proline;
                    DECLARE @lableid VARCHAR(64) = NEWID();

                    --插入一个新的半成品标签
                    INSERT INTO Barocde_BoxlLable
                    (
                        ID,
                        [USN],
                        [PartNum],
                        PartDescription,
                        Lot,
                        ProLine,
                        CurrentLoc,
                        [Qty],
                        [WoNum],
                        [Wo_DueDate],
                        [PkgQty],
                        Status,
                        CustomNum,
                        CustomName,
                        CreateTime,
                        Site,
                        PrintQty,
                        BoxUser,
                        BoxTime,
                        ExtendFiled2,
                        labletype,
                        InspectResult,
                        InspectSN, --此处作为不良原因 使用
                        ExtendFiled3,
                        SupplyNum  --加工单号
                    )
                    SELECT @lableid,
                           fid,
                           @xxbad_part,
                           @xxbad_desc,
                           @xxbad_lot,
                           @xxbad_proline,
                           @Loc,
                           @xxbad_scrapqty,
                           @xxbad_extension3,
                           GETDATE(),
                           @pkgqty,
                           0,
                           @CustomID,
                           '天津佰安',
                           GETDATE(),
                           @xxbad_site,
                           @pkgqty,
                           @xxbad_user,
                           GETDATE(),
                           (
                               SELECT TOP 1
                                      pt_desc2
                               FROM dbo.pt_mstr
                               WHERE pt_part = @xxbad_part
                                     AND pt_domain = @xxbad_domain
                           ),
                           1,
                           @xxbad_op,
                           @xxbad_extension8,
                           @batch,
                           @xxbad_ship_id
                    FROM #sflable;

                    --调用半成品回冲存储过程 回冲

                    --EXEC BackFlushSFLbale @lableid, @xxbad_extension3;
                    EXEC BackFlushSFLbale_zero @lableid, @xxbad_extension3;
                    --打印箱码
                    -- EXEC PrintFGLable @lableid, '1594943751915634689'; --半成品打印路径
                    SET @fi = @fi + 1;
                END;
                PRINT @batch;
                --插入主队列  上报QAD  默认是缓存状态 ，生成扣料信息 之后 变成生成状态
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    xxinbxml_extid,
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_op,
                    xxinbxml_Proline,
                    xxinbxml_blp
                )
                SELECT @xxbad_domain,
                       'PQ_WO_BKFL',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       MAX(USN),
                       @xxbad_extension3,
                       0,
                       MAX(PartNum),
                       @xxbad_ship_id,
                       ISNULL(dbo.GetQADloc(@Loc), ''),
                       MAX(Lot),
                       MAX(Lot),
                       @xxbad_site,
                       @xxbad_site,
                       @xxbad_extension3,
                       (
                           SELECT COUNT(1) FROM #ps_mstr10072
                       ),
                       SUM(Qty),
                       MAX(WorkOp),
                       MAX(ProLine),
                       @xxbad_op
                FROM dbo.Barocde_BoxlLable
                WHERE ExtendFiled3 = @batch;

                --插入子队列  增加半成品库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'PQ_WO_BKFL',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       USN,
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       CurrentLoc,
                       CurrentLoc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       @xxbad_extension3,
                       Qty,
                       Lot,
                       Lot,
                       @xxbad_ref,
                       ''
                FROM dbo.Barocde_BoxlLable
                WHERE ExtendFiled3 = @batch;
                --更改加工单状态和下线数量
                UPDATE dbo.FGWorkPlan
                SET Status = 2,
                    MakeQty = ISNULL(MakeQty, 0) + @xxbad_qty
                WHERE WoNum = @xxbad_extension3
                      AND ISNULL(@xxbad_op, 1) = 1;
                UPDATE dbo.FGWorkPlan
                SET Status = 2,
                    DestoryQty = ISNULL(DestoryQty, 0) + @xxbad_qty
                WHERE WoNum = @xxbad_extension3
                      AND @xxbad_op = 0;
                SET @ErrorMessage
                    = N'Info_MESSAGE#' + ISNULL(@xxbad_extension3, '') + N'下线成功!#' + ISNULL(@xxbad_extension3, '') + N'Offline successfully!';
                RAISERROR(@ErrorMessage, 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN

                SELECT 1 xxbad_rj_qty,
                       'xxbad_woid' focus,
                       1 xxbad_op;
                SELECT 1;

            END;
            ELSE IF @ScanData = 'xxbad_op'
            BEGIN
                PRINT 'xxbad_op';
            END;
            ELSE IF @ScanData = 'xxbad_extension8'
            BEGIN
                PRINT 'xxbad_extension8';
            END;
            ELSE --认为扫描的加工单信息
            BEGIN
                DECLARE @Date DATETIME; --生产日期
                --取出扫描的加工单信息
                SELECT @xxbad_part = PartNum,
                       @Date = Date,
                       @xxbad_desc = PartDesc,
                       @xxbad_extension7 = PlanQty,
                       @xxbad_extension6 = MakeQty,
                       @xxbad_extension3 = WoNum,
                       @xxbad_proline = Line
                FROM FGWorkPlan
                WHERE wo_lot = @xxbad_woid;
                -- RAISERROR(N'管理员正在调试系统', 11, 1);
                --判断加工单是否合法
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#加工单不存在!#The processing order does not exist!', 11, 1);

                END;
                --自动生成半成品批次
                SET @xxbad_lot = CONVERT(CHAR(8), GETDATE(), 112);
                --返回第一个dataset 到前台
                SELECT @xxbad_extension3 xxbad_extension3,
                       @xxbad_woid xxbad_woid,
                       'xxbad_qty,xxbad_lot' READONLY,
                       @xxbad_part xxbad_part,
                       @xxbad_desc xxbad_desc,
                       @xxbad_extension7 xxbad_extension7,
                       @xxbad_extension6 xxbad_extension6,
                       1 xxbad_rj_qty,
                       @xxbad_lot xxbad_lot,
                       @xxbad_proline xxbad_proline;
            END;
        END;
        IF @interfaceid IN ( 10032 ) --多批次打包
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断批次和数量 不能为空
                IF @xxbad_extension1 = ''
                   OR @xxbad_extension2 = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请输入入箱批次和数量!#Please enter the batch number and quantity!', 11, 1);

                END;
                --判断箱标签不能超量打包
                IF (CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_rj_qty, '0'))
                    + CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension2, '0')) > @xxbad_qty
                   )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#箱标签不能超量打包!#Box labels cannot be overpacked!', 11, 1);

                END;
                --如果是首次打包插入 需要把自己本身插入进去
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barocde_FGlLable
                    WHERE InBoundBox = @xxbad_id
                )
                BEGIN
                    INSERT INTO [dbo].[Barocde_FGlLable]
                    (
                        [Lot],
                        [Qty],
                        CreateTime,
                        InBoundBox
                    )
                    SELECT Lot,
                           Qty,
                           CreateTime,
                           USN
                    FROM Barocde_BoxlLable
                    WHERE USN = @xxbad_id;
                END;
                --生成一个新的FG 小标签
                INSERT INTO [dbo].[Barocde_FGlLable]
                (
                    [Lot],
                    [Qty],
                    CreateTime,
                    InBoundBox
                )
                SELECT @xxbad_extension1,
                       @xxbad_extension2,
                       GETDATE(),
                       @xxbad_id;
                --更新箱标签的累计数量
                UPDATE dbo.Barocde_BoxlLable
                SET Qty = Qty + CONVERT(DECIMAL(18, 5), @xxbad_extension2),
                    IsComplex = 1
                WHERE USN = @xxbad_id;

                --返回第一个dataset 到前台
                SELECT USN xxbad_id,
                       PartNum xxbad_part,
                       CurrentLoc xxbad_loc,
                       PkgQty xxbad_qty,
                       Qty xxbad_rj_qty,
                       Lot xxbad_lot,
                       'xxbad_extension1,xxbad_extension2' READONLY
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                --返回第二个dataset到前台
                SELECT Lot,
                       Qty
                FROM dbo.Barocde_FGlLable
                WHERE InBoundBox = @xxbad_id;
            END;

            ELSE IF @ScanData = 'ReDo'
            BEGIN
                --清除缓存表
                DELETE FROM dbo.Barocde_FGlLable
                WHERE InBoundBox = @xxbad_id;
                UPDATE Barocde_BoxlLable
                SET Qty = 0,
                    Status = 1,
                    IsComplex = 1
                WHERE USN = @xxbad_id;
                --返回第一个dataset 到前台
                SELECT USN xxbad_id,
                       PartNum xxbad_part,
                       CurrentLoc xxbad_loc,
                       PkgQty xxbad_qty,
                       Qty xxbad_rj_qty,
                       Lot xxbad_lot,
                       'xxbad_extension1,xxbad_extension2' READONLY
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                --返回第二个dataset到前台
                SELECT Lot,
                       Qty
                FROM dbo.Barocde_FGlLable
                WHERE InBoundBox = @xxbad_id;

            END;
            ELSE
            BEGIN
                RAISERROR(N'ERROR_MESSAGE#此功能已经废弃，请使用并箱功能!#This feature has been deprecated. Please use the merge function!', 11, 1);

                --判断箱标签是否合法
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barocde_BoxlLable
                    WHERE USN = @ScanData
                          AND Status = 1
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#箱标签不合法!#Invalid box label!', 11, 1);

                END;
                --返回第一个dataset 到前台
                SELECT USN xxbad_id,
                       PartNum xxbad_part,
                       CurrentLoc xxbad_loc,
                       PkgQty xxbad_qty,
                       Qty xxbad_rj_qty,
                       Lot xxbad_lot,
                       'xxbad_extension1,xxbad_extension2' READONLY
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @ScanData;
                --返回第二个dataset到前台
                SELECT Lot,
                       Qty
                FROM dbo.Barocde_FGlLable
                WHERE InBoundBox = @ScanData;
            END;

        END;
        IF @interfaceid IN ( 10020 ) --箱码成品下线回冲 自动免提交版本
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN

                RAISERROR(N'Info_MESSAGE#下线成功!#Logout successful!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;
                SELECT 1;

            END;
            ELSE IF @ScanData = 'ComboBox'
            BEGIN
                SELECT 1;
                SELECT 1;

            END;
            ELSE IF @ScanData = 'xxbad_id'
            BEGIN

                --判断箱标签是否合法
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barocde_BoxlLable
                    WHERE USN = @xxbad_id
                          AND Status IN ( 0, 1 )
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#箱码或箱码状态不正确!#The box code or box code status is incorrect!', 11, 1);

                END;
                --判断箱标签是否已经回冲过了
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barocde_BoxlLable
                    WHERE USN = @xxbad_id
                          AND Status > 1
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#箱码已经回冲了!#The box code has already been reversed!', 11, 1);

                END;

                --获取标签信息
                SELECT TOP 1
                       @xxbad_id = USN,
                       @xxbad_woid = WoNum,
                       @xxbad_site = Site,
                       @xxbad_part = PartNum,
                       @xxbad_desc = PartDescription,
                       @xxbad_qty = Qty,
                       @xxbad_proline = ProLine,
                       @xxbad_lot = Lot,
                       @xxbad_loc = CurrentLoc
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id
                ORDER BY ID DESC;

                --根据获得的产线 查找回冲库位
                IF ISNULL(@xxbad_loc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#下线库位不能为空!#The offline storage location cannot be empty!', 11, 1);

                END;
                --判断下线批次不能为空
                IF ISNULL(@xxbad_lot, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#下线批次不能为空!#The offline batch cannot be empty!', 11, 1);

                END;
                DECLARE @waning NVARCHAR(50);
                --判断当前的工艺是否存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM ro_det
                    WHERE ro_routing = @xxbad_part
                          AND ro_start >= GETDATE()
                )
                BEGIN
                    SET @waning = N'工艺路线不存在 禁止下线';
                END;
                --取出当前零件的BOM到临时表 ,汇总得到每个零件计划扣料量
                SELECT ps_comp,
                       ps_qty_per * @xxbad_qty ps_qty_per
                INTO #ps_mstr
                FROM dbo.WOps_mstr
                WHERE WoNum = @xxbad_woid;
                --判断BOM是否存在
                IF NOT EXISTS (SELECT TOP 1 1 FROM #ps_mstr)
                BEGIN
                    SET @waning = N'警告：加工单没有设置BOM';
                END;
                --汇总 得到线边库存情况
                SELECT partnum,
                       SUM(qty) Qty
                INTO #Barocde_Stock
                FROM barocde_stock
                WHERE loc = @xxbad_loc
                GROUP BY partnum;

                ----查询缺少的原材料
                DECLARE @lesspart VARCHAR(2000);
                SELECT @lesspart = COALESCE(a.ps_comp + '|', '')
                FROM #ps_mstr a
                    LEFT JOIN #Barocde_Stock b
                        ON b.partnum = a.ps_comp
                WHERE a.ps_qty_per > 0
                      AND
                      (
                          b.Qty < a.ps_qty_per
                          OR b.Qty = 0
                          OR b.partnum IS NULL
                      );

                SET @ErrorMessage = N'ERROR_MESSAGE#' + @lesspart + N'线边库存不足，无法下线!#' + @lesspart + N'Insufficient line-side inventory, unable to go offline!';
                --判断在线库位是否不足
                IF (ISNULL(@lesspart, '') <> '')
                BEGIN
                    RAISERROR(@ErrorMessage, 11, 1);

                END;

                --判断加工单 是不是 已经关闭了或者完成
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.FGWorkPlan
                    WHERE WoNum = @xxbad_woid
                          AND Status IN ( 4, 5 )
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#加工单已经关闭或者删除，无法下线!#The work order has been closed or deleted and cannot be taken offline!', 11, 1);

                END;
                DECLARE @lableid10020 VARCHAR(50) =
                        (
                            SELECT TOP 1 ID FROM dbo.Barocde_BoxlLable WHERE USN = @xxbad_id
                        );

                --BOM回冲
                EXEC dbo.BackFlushFGLbale @lableid10020, @xxbad_woid;
                --插入主队列  上报QAD
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    xxinbxml_extid,
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_op,
                    xxinbxml_Proline
                )
                SELECT @xxbad_domain,
                       'PQ_WO_BKFL',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       USN,
                       WoNum,
                       0,
                       PartNum,
                       SupplyNum, --加工单号
                       ISNULL(dbo.GetQADloc(CurrentLoc), ''),
                       @xxbad_lot,
                       @xxbad_lot,
                       ISNULL(Site, @xxbad_site),
                       ISNULL(Site, @xxbad_site),
                       @xxbad_woid,
                       (
                           SELECT COUNT(1) FROM #ps_mstr
                       ),
                       Qty,
                       WorkOp,
                       ProLine
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'PQ_WO_BKFL',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       USN,
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       CurrentLoc,
                       CurrentLoc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       @xxbad_id,
                       Qty,
                       @xxbad_lot,
                       @xxbad_lot,
                       @xxbad_ref,
                       ''
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;

                --更新标签的状态,批次 和 回冲信息
                UPDATE dbo.Barocde_BoxlLable
                SET Status = 2,
                    FlushStatus = 1,
                    BackwashUser = @xxbad_user,
                    Lot = @xxbad_lot,
                    BackwashTime = GETDATE()
                WHERE USN = @xxbad_id;
                --累加加工单中完成数量
                UPDATE dbo.FGWorkPlan
                SET MakeQty = ISNULL(MakeQty, 0) + ISNULL(@xxbad_qty, 0),
                    Status = 3
                WHERE WoNum = @xxbad_woid;
                --自动关闭 计划量等于下线量的加工单
                UPDATE dbo.FGWorkPlan
                SET Status = 5
                WHERE WoNum = @xxbad_woid
                      AND PlanQty <= MakeQty;
                --返回第一个dataset 到前台 95130001 EC28BBE010P1
                SELECT @xxbad_woid xxbad_woid,
                       '' xxbad_id,
                       @xxbad_site xxbad_site,
                       @xxbad_part xxbad_part,
                       @xxbad_desc xxbad_desc,
                       @xxbad_qty xxbad_qty,
                       @xxbad_id + '：下线成功' + @waning xxbad_extension1,
                       @xxbad_proline xxbad_proline,
                       @xxbad_lot xxbad_lot,
                       @xxbad_loc xxbad_loc;
            END;

        END;
        IF @interfaceid IN ( 10021 ) --箱码成品下线回冲 手工版本
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断箱标签是否合法
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barocde_BoxlLable WITH (ROWLOCK)
                    WHERE USN = @xxbad_extension2
                          AND Status IN ( 0, 1 )
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#箱码或箱码状态不正确!#The box code or box code status is incorrect!', 11, 1);
                END;
                --判断箱标签是否已经回冲过了
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barocde_BoxlLable WITH (ROWLOCK)
                    WHERE USN = @xxbad_extension2
                          AND Status > 1
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#箱码已经回冲了!#The box code has already been reversed!', 11, 1);
                END;
                --判断加工单 是不是 已经关闭了或者完成
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.FGWorkPlan
                    WHERE WoNum = @xxbad_woid
                          AND Status IN ( 4, 5 )
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#加工单已经关闭或者删除，无法下线!#The work order has been closed or deleted and cannot be taken offline!', 11, 1);
                END;
                DECLARE @sql NVARCHAR(MAX);
                DECLARE @result TABLE
                (
                    exists_flag BIT
                );

                SET @sql
                    = N'SELECT * FROM OPENQUERY(MFGDBPROD, 
    ''SELECT TOP 1 1 FROM PUB.wo_mstr  WHERE wo_lot = ''''' + @xxbad_woid + N''''' WITH (NOLOCK) '')';

                INSERT INTO @result
                EXEC (@sql);

                IF NOT EXISTS (SELECT 1 FROM @result)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#QAD加工单已经删除，无法下线!#The QAD processing order has been deleted and cannot be taken offline!', 11, 1);
                END;
                --限制提交标签和扫描的标签 是同一个标签
                DECLARE @lableid100201 VARCHAR(50);
                SELECT TOP 1
                       @lableid100201 = ID,
                       @xxbad_qty = Qty
                FROM dbo.Barocde_BoxlLable WITH (ROWLOCK)
                WHERE USN = @xxbad_extension2;
                --BOM回冲
                EXEC dbo.BackFlushFGLbale @lableid100201, @xxbad_woid;

                --插入主队列  上报QAD
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    xxinbxml_extid,
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_op,
                    xxinbxml_Proline
                )
                SELECT @xxbad_domain,
                       'PQ_WO_BKFL',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       USN,
                       WoNum,
                       0,
                       PartNum,
                       SupplyNum, --加工单号
                       ISNULL(dbo.GetQADloc(CurrentLoc), ''),
                       Lot,
                       Lot,
                       ISNULL(Site, @xxbad_site),
                       ISNULL(Site, @xxbad_site),
                       @xxbad_woid,
                       '',
                       Qty,
                       WorkOp,
                       ProLine
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_extension2;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'PQ_WO_BKFL',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       USN,
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       CurrentLoc,
                       CurrentLoc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       USN,
                       Qty,
                       Lot,
                       Lot,
                       @xxbad_ref,
                       ''
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_extension2;

                --更新标签的状态,批次 和 回冲信息
                UPDATE dbo.Barocde_BoxlLable WITH (ROWLOCK)
                SET Status = 2,
                    FlushStatus = 1,
                    BackwashUser = @xxbad_user,
                    --Lot = @xxbad_lot,
                    BackwashTime = GETDATE()
                WHERE USN = @xxbad_extension2;
                --累加加工单中完成数量
                UPDATE dbo.FGWorkPlan
                SET MakeQty = ISNULL(MakeQty, 0) + ISNULL(@xxbad_qty, 0),
                    Status = 3
                WHERE WoNum = @xxbad_woid;
                --自动关闭 计划量等于下线量的加工单
                UPDATE dbo.FGWorkPlan
                SET Status = 5
                WHERE WoNum = @xxbad_woid
                      AND PlanQty <= MakeQty;
                -- 删除缓存中的数据
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND LableID = @xxbad_extension2
                      AND OpUser = @xxbad_user;
                --判断是否是重复提交QAD
                SELECT @xxbad_op = COUNT(1)
                FROM dbo.xxinbxml_mstr
                WHERE xxinbxml_extid = @xxbad_extension2
                      AND BarcodeInterFaceID = @interfaceid;
                IF @xxbad_op > 1
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#箱码已经回冲了!#The box code has already been reversed!', 11, 1);
                END;
                RAISERROR(N'Info_MESSAGE#下线成功!#Logout successful!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;
                SELECT 1;

            END;
            ELSE IF @ScanData = 'ComboBox'
            BEGIN
                SELECT 1;
                SELECT 1;

            END;
            ELSE IF @ScanData = 'xxbad_id'
            BEGIN
                --判断箱标签是否合法
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barocde_BoxlLable
                    WHERE USN = @xxbad_id
                          AND Status IN ( 0, 1 )
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#箱码或箱码状态不正确!#The box code or box code status is incorrect!', 11, 1);

                END;
                --判断箱标签是否已经回冲过了
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barocde_BoxlLable
                    WHERE USN = @xxbad_id
                          AND Status > 1
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#箱码已经回冲了!#The box code has already been reversed!', 11, 1);

                END;

                --获取标签信息
                SELECT TOP 1
                       @xxbad_id = USN,
                       @xxbad_woid = WoNum,
                       @xxbad_site = Site,
                       @xxbad_part = PartNum,
                       @xxbad_desc = PartDescription,
                       @xxbad_qty = Qty,
                       @xxbad_proline = ProLine,
                       @xxbad_lot = Lot,
                       @xxbad_loc = CurrentLoc
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id
                ORDER BY ID DESC;

                --根据获得的产线 查找回冲库位
                IF ISNULL(@xxbad_loc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#下线库位不能为空!#The offline storage location cannot be empty!', 11, 1);

                END;
                --判断下线批次不能为空
                IF ISNULL(@xxbad_lot, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#下线批次不能为空!#The offline batch cannot be empty!', 11, 1);

                END;
                DECLARE @waning10021 NVARCHAR(50);
                --判断当前的工艺是否存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM ro_det
                    WHERE ro_routing = @xxbad_part
                          AND ro_start >= GETDATE()
                )
                BEGIN
                    SET @waning10021 = N'工艺路线不存在 禁止下线';
                END;
                --取出当前零件的BOM到临时表 ,汇总得到每个零件计划扣料量
                SELECT ps_comp,
                       ps_qty_per * @xxbad_qty ps_qty_per
                INTO #ps_mstr10021
                FROM dbo.WOps_mstr
                WHERE WoNum = @xxbad_woid;
                --判断BOM是否存在
                IF NOT EXISTS (SELECT TOP 1 1 FROM #ps_mstr10021)
                BEGIN
                    SET @waning10021 = N'警告：加工单没有设置BOM';
                END;
                --汇总 得到线边库存情况
                SELECT partnum,
                       SUM(qty) Qty
                INTO #Barocde_Stock10021
                FROM barocde_stock
                WHERE loc = @xxbad_loc
                GROUP BY partnum;

                ----查询缺少的原材料
                DECLARE @lesspart10021 VARCHAR(2000);
                SELECT @lesspart10021 = COALESCE(a.ps_comp + '|', '')
                FROM #ps_mstr10021 a
                    LEFT JOIN #Barocde_Stock10021 b
                        ON b.partnum = a.ps_comp
                WHERE a.ps_qty_per > 0
                      AND
                      (
                          b.Qty < a.ps_qty_per
                          OR b.Qty = 0
                          OR b.partnum IS NULL
                      );

                SET @ErrorMessage
                    = N'ERROR_MESSAGE#' + @lesspart10021 + N'线边库存不足，无法下线!#' + @lesspart10021 + N'Insufficient line-side inventory, unable to proceed offline!';
                --判断在线库位是否不足
                IF (ISNULL(@lesspart10021, '') <> '')
                BEGIN
                    RAISERROR(@ErrorMessage, 11, 1);

                END;

                --判断加工单 是不是 已经关闭了或者完成
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.FGWorkPlan
                    WHERE WoNum = @xxbad_woid
                          AND Status IN ( 4, 5 )
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#加工单已经关闭或者删除，无法下线!#The work order has been closed or deleted and cannot be taken offline!', 11, 1);
                END;
                --判断如果 缓存表里面 有大于1行的 且不等于当前标签号 就要报错
                IF EXISTS
                (
                    SELECT 1
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND LableID <> @xxbad_id
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#上一个标签还没有提交，请先提交或者解除!#The previous tag has not been submitted yet. Please submit or cancel it first!', 11, 1);
                END;
                --如果在动态高速缓存表不存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND LableID = @xxbad_id
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    --从标签中获取标签信息 插入动态高速缓存表
                    INSERT INTO [dbo].[Barcode_OperateCache]
                    (
                        id,
                        [AppID],
                        [OpUser],
                        [LableID],
                        [PartNum],
                        [PartDescrition],
                        [Qty],
                        ToLot,
                        [FromLoc],
                        PoNum,
                        PoLine,
                        [CurrentLoc],
                        [ToLoc],
                        [FromSite],
                        [ToSite],
                        [ScanTime],
                        ExtendedField1,
                        ExtendedField2,
                        SupplyCode,
                        FromLot
                    )
                    SELECT TOP 1
                           NEWID(),
                           @interfaceid,
                           @xxbad_user,
                           @xxbad_id,
                           PartNum,
                           PartDescription,
                           Qty,
                           Lot,
                           CurrentLoc,
                           PurchaseOrder,
                           PoLine,
                           CurrentLoc,
                           CurrentLoc,
                           Site,
                           @xxbad_site,
                           GETDATE(),
                           @xxbad_kanban_id,
                           '',
                           @xxbad_supplier,
                           Lot
                    FROM dbo.Barocde_BoxlLable
                    WHERE USN = @xxbad_id;
                END;
                ELSE
                BEGIN
                    DELETE [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND LableID = @xxbad_id
                          AND OpUser = @xxbad_user;
                END;
                --返回第一个dataset 到前台 95130001 EC28BBE010P1
                SELECT @xxbad_woid xxbad_woid,
                       '' xxbad_id,
                       'xxbad_id' focus,
                       @xxbad_id xxbad_extension2,
                       @xxbad_site xxbad_site,
                       @xxbad_part xxbad_part,
                       @xxbad_desc xxbad_desc,
                       @xxbad_qty xxbad_qty,
                       @xxbad_id xxbad_extension1,
                       @xxbad_proline xxbad_proline,
                       @xxbad_lot xxbad_lot,
                       @xxbad_loc xxbad_loc;
            END;

        END;
        IF @interfaceid IN ( 10023 ) --设备报修
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断箱标签是否合法
                IF ISNULL(@xxbad_extension2, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#故障类型不能为空!#The fault type cannot be empty!', 11, 1);
                END;
                --生成序列号
                CREATE TABLE #t10023
                (
                    fid VARCHAR(30)
                );
                INSERT INTO #t10023
                EXEC dbo.MakeSeqenceNum '00000008', '';
                --插入报修表
                INSERT INTO dbo.appdevicereport
                (
                    id,
                    xxbad_id,
                    xxbad_desc,
                    xxbad_extension1,
                    xxbad_proline,
                    xxbad_extension2,
                    xxbad_extension3,
                    xxbad_user,
                    xxbad_time,
                    status
                )
                SELECT NEWID(),           -- id - varchar(36)
                       @xxbad_id,         -- xxbad_id - nvarchar(32)
                       @xxbad_desc,       -- xxbad_desc - nvarchar(32)
                       @xxbad_extension1, -- xxbad_extension1 - nvarchar(32)
                       @xxbad_proline,    -- xxbad_proline - nvarchar(32)
                       @xxbad_extension2, -- xxbad_extension2 - nvarchar(32)
                       fid,               -- tasknum - nvarchar(32)
                       @xxbad_user,       -- xxbad_user - nvarchar(32)
                       GETDATE(),
                       0
                FROM #t10023;
                RAISERROR(N'Info_MESSAGE#报修成功!#Repair request submitted successfully!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;
                SELECT 1;
            END;
            ELSE IF @ScanData = 'xxbad_id'
            BEGIN
                --判断设备条码是否合法
                IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.Equip WHERE EqNum = @xxbad_id)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#设备编码不存在!#Device code does not exist!', 11, 1);
                END;
                --返回第一个dataset 到前台 95130001 EC28BBE010P1
                SELECT EqNum xxbad_id,
                       EqType xxbad_extension1,
                       Description xxbad_desc,
                       Location xxbad_proline,
                       (
                           SELECT name text,
                                  name value
                           FROM dbo.deviceerror
                           WHERE deviceid = @xxbad_id
                           FOR JSON PATH
                       ) xxbad_extension2_s,
                       @xxbad_user xxbad_user
                FROM dbo.Equip
                WHERE EqNum = @xxbad_id;
            END;

        END;
        IF @interfaceid IN ( 10025 ) --接单维修
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断设备条码是否合法
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.appdevicereport
                    WHERE xxbad_extension3 = @xxbad_extension3
                          AND status = 0
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#报修单号不正确!#The repair order number is incorrect!', 11, 1);
                END;
                --判断箱标签是否合法
                IF ISNULL(@xxbad_extension4, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#故障原因不能为空!#The cause of the malfunction cannot be empty!', 11, 1);
                END;
                --更新维修人 维修时间
                UPDATE appdevicereport
                SET status = 1,
                    fixuser = @xxbad_user,
                    fixtime = GETDATE(),
                    xxbad_extension4 = @xxbad_extension4
                WHERE xxbad_extension3 = @xxbad_extension3
                      AND status = 0;
                --插入接口表
                INSERT dbo.xxsbs_det
                (
                    xxsbs_line,
                    xxsbs_sb_code,
                    xxsbs_time,
                    xxsbs_s_date,
                    xxsbs_s_time,
                    xxsbs_e_date,
                    xxsbs_e_time,
                    xxsbs_user,
                    uploadstatus,
                    id
                )
                SELECT xxbad_proline,
                       xxbad_id,
                       DATEDIFF(MINUTE, xxbad_time, fixtime),
                       xxbad_time,
                       dbo.GetQADtime(xxbad_time),
                       fixtime,
                       dbo.GetQADtime(fixtime),
                       xxbad_user,
                       0,
                       NEWID()
                FROM dbo.appdevicereport
                WHERE xxbad_extension3 = @xxbad_extension3;
                RAISERROR(N'Info_MESSAGE#报修成功!#Repair request submitted successfully!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;
                SELECT 1;
            END;
            ELSE IF @ScanData = 'xxbad_extension3'
            BEGIN
                --判断设备条码是否合法
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.appdevicereport
                    WHERE xxbad_extension3 = @xxbad_extension3
                          AND status = 0
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#报修单号不存在!#The repair order number does not exist!', 11, 1);
                END;
                --返回第一个dataset 到前台 95130001 EC28BBE010P1
                SELECT xxbad_id,
                       xxbad_extension1,
                       xxbad_desc,
                       xxbad_proline,
                       xxbad_user,
                       xxbad_extension2,
                       xxbad_extension3,
                       xxbad_time
                FROM dbo.appdevicereport
                WHERE xxbad_extension3 = @xxbad_extension3;
            END;

        END;
        IF @interfaceid IN ( 10110 ) --成品反向回冲 
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                RAISERROR(N'Info_MESSAGE#下线成功!#Logout successful!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;
                SELECT 1;
            END;
            ELSE IF @ScanData = 'ComboBox'
            BEGIN
                SELECT 1;
                SELECT 1;
            END;
            ELSE --认为扫描的是成品条码
            BEGIN

                --判断箱标签是否合法
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barocde_BoxlLable
                    WHERE USN = @xxbad_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#箱码不正确!#Incorrect box code!', 11, 1);

                END;
                --判断箱标签是否已经回冲过了
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barocde_BoxlLable
                    WHERE USN = @xxbad_id
                          AND Status > 1
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#箱码还没回冲，无法反向回冲!#The box code has not been recharged yet, reverse recharge is not possible!', 11, 1);

                END;

                --获取标签信息
                SELECT TOP 1
                       @xxbad_id = USN,
                       @xxbad_woid = WoNum,           --加工单ID
                       @xxbad_site = Site,
                       @xxbad_part = PartNum,
                       @xxbad_extension8 = InspectResult,
                       @xxbad_desc = PartDescription,
                       @xxbad_qty = Qty,
                       @xxbad_proline = ProLine,
                       @xxbad_lot = Lot,
                       @xxbad_extension7 = SupplyNum, --加工单号
                       @xxbad_loc = CurrentLoc
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id
                ORDER BY ID DESC;

                --根据获得的产线 查找回冲库位
                IF ISNULL(@xxbad_proline, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#下线库位不能为空!#The offline storage location cannot be empty!', 11, 1);

                END;
                --判断下线批次不能为空
                IF ISNULL(@xxbad_lot, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#下线批次不能为空!#The offline batch cannot be empty!', 11, 1);

                END;
                --判断标签必须 在产线库位
                IF @xxbad_proline <> @xxbad_loc
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签当前库位必须在产线库位!#The label's current location must be in the production line location!', 11, 1);
                END;
                --取出当前零件的BOM到临时表 ,汇总得到每个零件计划扣料量
                SELECT ps_comp,
                       ps_qty_per * @xxbad_qty ps_qty_per
                INTO #ps_mstr10110
                FROM dbo.WOps_mstr
                WHERE WoNum = @xxbad_woid;
                --判断BOM是否存在
                IF NOT EXISTS (SELECT TOP 1 1 FROM #ps_mstr10110)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#总成BOM缺失，无法反向回冲!#Assembly BOM missing, unable to backflush!', 11, 1);

                END;
                --判断当前标签是否有历史的回冲记录
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.QADbackflushDetail
                    WHERE FGlable = @xxbad_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#没有找到正向回冲记录，无法反向回冲!#No forward charge record found, unable to reverse charge!', 11, 1);

                END;
                --判断加工单 是不是 已经关闭了或者完成
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.FGWorkPlan
                    WHERE WoNum = @xxbad_woid
                          AND Status IN ( 4, 5 )
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#加工单已经关闭或者删除，无法反向回冲!#The processing order has been closed or deleted, reverse charge is not possible!', 11, 1);

                END;
                --插入库存表 扣减掉原材料的库存
                INSERT dbo.barocde_stock
                (
                    site,
                    loc,
                    partnum,
                    lot,
                    qty,
                    modifyuser,
                    modifytime,
                    ref
                )
                SELECT @xxbad_site,
                       Loc,
                       RMpart,
                       Lot,
                       ABS(CostQty),
                       @xxbad_user,
                       GETDATE(),
                       @xxbad_id
                FROM dbo.QADbackflushDetail
                WHERE FGlable = @xxbad_id;
                --插入QAD 回冲事务表 回冲掉qad 的原材料扣料记录
                INSERT INTO [dbo].QADbackflushDetail
                (
                    [FGlable],
                    [FGpart],
                    [FGqty],
                    [RMpart],
                    [CostQty],
                    [Loc],
                    Lot,
                    [WoNum],
                    [InsertUser],
                    [InsertTime],
                    Status,
                    woid,
                    rightqty
                )
                SELECT FGlable,
                       FGpart,
                       -FGqty,
                       RMpart,
                       -CostQty,
                       Loc,
                       Lot,
                       WoNum,
                       'BOM',
                       GETDATE(),
                       0,
                       woid,
                       rightqty
                FROM dbo.QADbackflushDetail
                WHERE FGlable = @xxbad_id;

                --插入负数产成品主队列  上报QAD
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    xxinbxml_extid,
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_op,
                    xxinbxml_Proline
                )
                SELECT @xxbad_domain,
                       'PQ_WO_BKFL',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       USN,
                       @xxbad_woid,
                       0,
                       PartNum,
                       @xxbad_extension7, --加工单号
                       ISNULL(dbo.GetQADloc(CurrentLoc), ''),
                       @xxbad_lot,
                       @xxbad_lot,
                       ISNULL(Site, @xxbad_site),
                       ISNULL(Site, @xxbad_site),
                       @xxbad_woid,
                       '',
                       -Qty,
                       WorkOp,
                       ProLine
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                --插入子队列 用于生成负数的产成品库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'PQ_WO_BKFL',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       USN,
                       @xxbad_user,
                       @xxbad_woid,
                       '',
                       PartNum,
                       CurrentLoc,
                       CurrentLoc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_woid,
                       @xxbad_id,
                       -Qty,
                       @xxbad_lot,
                       @xxbad_lot,
                       @xxbad_ref,
                       ''
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;

                --更新标签的状态,批次 和 回冲信息
                UPDATE dbo.Barocde_BoxlLable
                SET Status = 7,
                    Qty = 0,
                    DestroyUser = @xxbad_user,
                    DestroyMemo = @xxbad_extension8 + '反向回冲成功,数量：' + @xxbad_qty,
                    DestroyTime = GETDATE()
                WHERE USN = @xxbad_id;
                --累加加工单中完成数量
                IF @xxbad_extension8 = '1'
                BEGIN
                    UPDATE dbo.FGWorkPlan
                    SET MakeQty = ISNULL(MakeQty, 0) - ISNULL(@xxbad_qty, 0)
                    WHERE WoNum = @xxbad_woid;
                END;
                ELSE
                BEGIN
                    UPDATE dbo.FGWorkPlan
                    SET DestoryQty = ISNULL(DestoryQty, 0) - ISNULL(@xxbad_qty, 0)
                    WHERE WoNum = @xxbad_woid;
                END;

                --自动关闭 计划量等于下线量的加工单
                --UPDATE dbo.FGWorkPlan
                --SET Status = 5
                --WHERE WoNum = @xxbad_woid
                --      AND PlanQty < = MakeQty;
                --返回第一个dataset 到前台 95130001 EC28BBE010P1
                SELECT @xxbad_woid xxbad_woid,
                       '' xxbad_id,
                       @xxbad_site xxbad_site,
                       @xxbad_part xxbad_part,
                       @xxbad_desc xxbad_desc,
                       @xxbad_qty xxbad_qty,
                       @xxbad_id + '：反向回冲成功' xxbad_extension1,
                       @xxbad_proline xxbad_proline,
                       @xxbad_lot xxbad_lot,
                       @xxbad_loc xxbad_loc;
            END;

        END;
        IF @interfaceid IN ( 10111 ) --原材料上料
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                RAISERROR(N'Info_MESSAGE#下线成功!#Logout successful!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus;

            END;
            ELSE IF @ScanData = 'ComboBox'
            BEGIN
                SELECT 1;
                SELECT 1;

            END;
            ELSE --认为扫描的是原料条码
            BEGIN
                RAISERROR(N'Info_MESSAGE#此功能已经下线，不再使用!#This feature has been discontinued and is no longer available!', 11, 1);
                --判断箱标签是否合法
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.barocde_materiallable
                    WHERE usn = @xxbad_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不正确!#Invalid tag!', 11, 1);

                END;
                --判断箱标签是否合法
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.barocde_materiallable
                    WHERE usn = @xxbad_id
                          AND ISNULL(lot, '') = ''
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签批次不正确!#Incorrect label batch!', 11, 1);

                END;
                --判断箱标签是否标签还没有领用
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.barocde_materiallable
                    WHERE usn = @xxbad_id
                          AND status IN ( 5, 6 )
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签还没有领用，不能上料!#The label has not been issued yet, material cannot be loaded!', 11, 1);

                END;
                --判断是否 已经在上料记录表里面存在
                IF EXISTS (SELECT TOP 1 1 FROM bcpupmaterial WHERE usn = @xxbad_id)
                BEGIN
                    -- 下线的时候需要扣减标签的数量
                    UPDATE a
                    SET a.qty = b.qty,
                        a.status = 5,
                        a.memo = '已下料'
                    FROM barocde_materiallable a,
                         bcpupmaterial b
                    WHERE a.usn = b.usn
                          AND a.usn = @xxbad_id;
                    --如果已经存在则清除
                    DELETE FROM bcpupmaterial
                    WHERE usn = @xxbad_id;
                    SELECT '' xxbad_id,
                           '' xxbad_status,
                           '' xxbad_part,
                           '' xxbad_desc,
                           '' xxbad_qty,
                           usn + '：下料成功' xxbad_extension1,
                           '' xxbad_lot,
                           '' xxbad_loc
                    FROM dbo.barocde_materiallable
                    WHERE usn = @xxbad_id;
                END;
                ELSE
                BEGIN
                    INSERT INTO dbo.bcpupmaterial
                    (
                        id,
                        create_by,
                        create_time,
                        usn,
                        partnum,
                        qty,
                        loc,
                        lot,
                        line
                    )
                    SELECT NEWID(),
                           'system',
                           GETDATE(),
                           @xxbad_id,
                           partnum,
                           qty,
                           currentloc,
                           lot,
                           currentloc
                    FROM barocde_materiallable
                    WHERE usn = @xxbad_id;
                    --更新标签的状态 为 已经上料
                    UPDATE dbo.barocde_materiallable
                    SET status = 6,
                        memo = '已经上料'
                    WHERE usn = @xxbad_id;
                    SELECT usn xxbad_id,
                           status xxbad_status,
                           partnum xxbad_part,
                           partdescription xxbad_desc,
                           qty xxbad_qty,
                           usn + '：上料成功' xxbad_extension1,
                           lot xxbad_lot,
                           currentloc xxbad_loc
                    FROM dbo.barocde_materiallable
                    WHERE usn = @xxbad_id;
                END;
            END;

        END;
        IF @interfaceid IN ( 10088 ) --加工单分摊 
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断加工单号
                IF ISNULL(@xxbad_woid, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请先扫码加工单号!#Please scan the processing order number first!', 11, 1);
                END;

                --判断零件号
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请先扫码物料号!#Please scan the material number first!', 11, 1);
                END;
                --判断零件号
                IF ISNULL(@xxbad_qty, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请输入分摊数量!#Please enter the allocation quantity!', 11, 1);
                END;
                DECLARE @mainid VARCHAR(64) = NEWID();
                --生成新的差异分摊单
                INSERT INTO stockdiffanalysis
                (
                    create_by,
                    memo,
                    id,
                    create_time,
                    partnum,
                    pt_desc1,
                    pt_desc2,
                    loc,
                    status,
                    stockqty, --待分摊差异量
                    totaldiff --差异初始值
                )
                SELECT @xxbad_user,
                       '加工单报废',
                       @mainid,
                       GETDATE(),
                       @xxbad_part,
                       @xxbad_desc,
                       @xxbad_extension3,
                       Line,
                       1,
                       @xxbad_qty,
                       @xxbad_qty
                FROM dbo.FGWorkPlan
                WHERE WoNum = @xxbad_woid;
                --生成差异分摊明细表
                INSERT dbo.stockdiffanalysis_detail
                (
                    id,
                    create_by,
                    create_time,
                    wonum,
                    ps_par,
                    ps_comp,
                    ps_qty_per_b, --理论消耗总量
                    actualqty,    --差异分摊量
                    mainid,
                    loc,
                    woid,
                    accqty,       --实际消耗量
                    wostatus,
                    pt_desc1,
                    pt_desc2,
                    ps_scrp_pct,  --BOM数量
                    ps_fcst_pct,  --良品数量
                    ps_qty_per    --不良品数量
                )
                SELECT NEWID(),
                       '加工单报废',
                       GETDATE(),
                       a.WoNum,
                       PartNum,
                       @xxbad_part,
                       (ISNULL(a.MakeQty, 0) + ISNULL(a.DestoryQty, 0)) * b.ps_qty_per,
                       @xxbad_qty,
                       @mainid,
                       a.Line,
                       a.wo_lot,
                       (ISNULL(a.MakeQty, 0) + ISNULL(a.DestoryQty, 0)) * b.ps_qty_per + @xxbad_qty,
                       a.Status,
                       @xxbad_desc,
                       @xxbad_extension3,
                       b.ps_qty_per,
                       a.MakeQty,
                       a.DestoryQty
                FROM dbo.FGWorkPlan a
                    LEFT JOIN dbo.WOps_mstr b
                        ON a.WoNum = b.WoNum
                           AND b.ps_comp = @xxbad_part
                WHERE a.WoNum = @xxbad_woid;
                IF ISNULL(@xxbad_qty, '0') <> '0'
                BEGIN
                    --插入qad 接口表  插入stockdiffanalysis_detail 触发器里面已经做了
                    --INSERT INTO dbo.QADbackflushDetail
                    --(
                    --    FGpart,
                    --    RMpart,
                    --    CostQty,
                    --    Loc,
                    --    WoNum,
                    --    InsertUser,
                    --    InsertTime,
                    --    Status,
                    --    woid,
                    --    ftstatus,
                    --    ftmain
                    --)
                    --SELECT PartNum,
                    --       @xxbad_part,
                    --       -CONVERT(DECIMAL(18,5), @xxbad_qty),
                    --       Line,
                    --       WoNum,
                    --       '分摊app',
                    --       GETDATE(),
                    --       0,
                    --       wo_lot,
                    --       1,
                    --       @mainid
                    --FROM dbo.FGWorkPlan
                    --WHERE WoNum = @xxbad_woid;
                    --减去半成品的线边库存
                    EXEC dbo.reducepartstock_zero @xxbad_part,       -- varchar(64)
                                                  @xxbad_extension1, -- varchar(64)
                                                  @xxbad_qty;        -- decimal(18, 4)
                END;
                RAISERROR(N'Info_MESSAGE#报废成功!#Pick List is complete!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                --生成JSON
                SELECT 'xxbad_woid' focus;
            END;
            ELSE IF @ScanData = 'xxbad_woid'
            BEGIN
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.FGWorkPlan
                    WHERE WoNum = @xxbad_woid
                          AND Status <> 5
                          AND ISNULL(Line, '') <> ''
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#加工单不合法!#The processing order is invalid!', 11, 1);
                END;
                SELECT Line xxbad_extension1,
                       WoNum xxbad_woid,
                       wo_lot xxbad_extension2,
                       'xxbad_part' focus
                FROM dbo.FGWorkPlan
                WHERE WoNum = @xxbad_woid
                      AND Status <> 5
                      AND ISNULL(Line, '') <> '';
            END;
            ELSE IF @ScanData = 'xxbad_part'
            BEGIN
                --判断当前物料是否在在加工单BOM 中
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.WOps_mstr
                    WHERE WoNum = @xxbad_woid
                          AND ps_comp = @xxbad_part
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前物料不在在加工单BOM中!#The current material is not in the processing order BOM!', 11, 1);
                END;
                SELECT pt_part xxbad_part,
                       pt_desc1 xxbad_desc,
                       pt_desc2 xxbad_extension3,
                       'xxbad_qty' focus,
                       (
                           SELECT SUM(qty)
                           FROM dbo.barocde_stock
                           WHERE partnum = @xxbad_part
                                 AND loc = @xxbad_extension1
                       ) xxbad_qty,
                       @xxbad_extension1 xxbad_extension1,
                       @xxbad_woid xxbad_woid,
                       @xxbad_extension2 xxbad_extension2
                FROM dbo.pt_mstr
                WHERE pt_part = @xxbad_part;
            END;

        END;
        IF @interfaceid IN ( 10074 ) --领料单出库
        BEGIN
            DECLARE @pt_pm_code INT;
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --如果在动态高速缓存表不存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                          AND ScanTime IS NOT NULL
                          AND LableID = @xxbad_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请提交已经扫描的标签!#Please submit the scanned label!', 11, 1);
                END;
                ELSE
                BEGIN
                    --然后判断  请领用刚刚扫描的箱码标签
                    DECLARE @maxlable10074 VARCHAR(50);
                    SELECT TOP 1
                           @maxlable10074 = LableID
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND ScanTime IS NOT NULL
                          AND OpUser = @xxbad_user
                    ORDER BY ScanTime DESC;

                    IF @xxbad_id != @maxlable10074
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#请领用刚刚扫描的箱码标签!#Please collect the recently scanned box code label!', 11, 1);
                    END;
                END;
                --判断领用数量 必须大于0
                IF @xxbad_scrapqty = ''
                   OR CONVERT(DECIMAL(18, 5), @xxbad_scrapqty) <= 0
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请输入本箱领用量!#Please enter the usage amount for this box!', 11, 1);
                END;
                PRINT CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_scrapqty, '0'));
                --判断是不是扫描了箱码
                IF ISNULL(@xxbad_id, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请先扫描箱码!#Please scan the box code first!', 11, 1);
                END;
                --如果是成品领料单  就不允许超额领料
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM fgallotpaper
                    WHERE allotnum = @xxbad_ship_id
                )
                BEGIN
                    DECLARE @needqtysub DECIMAL(18, 5);
                    SELECT TOP 1
                           @needqtysub = PlanQty - ISNULL(UsingQty, 0) - CONVERT(DECIMAL(18, 5), @xxbad_scrapqty)
                    FROM dbo.HSProdusing
                    WHERE UsingNum = @xxbad_ship_id
                          AND ps_comp = @xxbad_part;
                    IF @needqtysub < 0
                        RAISERROR(N'ERROR_MESSAGE#成品领料单不允许超额发料!#Finished goods requisition form does not allow over-issuance!', 11, 1);
                END;
                --判断当前行 是不是已经被关闭了
                --IF NOT EXISTS
                --(
                --    SELECT TOP 1
                --           1
                --    FROM dbo.HSProdusing
                --    WHERE UsingNum = @xxbad_ship_id
                --          AND Status < 2
                --          AND ps_comp = @xxbad_part
                --)
                --BEGIN
                --    RAISERROR(N'ERROR_MESSAGE#当前领料单当前行已结束!#The current line of the material requisition has ended!', 11, 1);

                --END;
                --获取到库位
                SELECT @xxbad_toloc = AllotLoc,
                       @pt_pm_code = IsFG
                FROM dbo.HSProdusing
                WHERE UsingNum = @xxbad_ship_id
                      AND ps_comp = @xxbad_part;

                IF ISNULL(@xxbad_toloc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#领料到库位不能为空!#The storage location for material requisition cannot be empty!', 11, 1);
                END;
                --如果全箱领用，则更改标签库位，如果是半箱领用数量 则需要拆箱
                DECLARE @lableqty10074 DECIMAL(18, 5);
                SELECT @lableqty10074 = Qty
                FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND LableID = @xxbad_id;
                --判断领用数量 不能大于当前箱数量 
                IF @lableqty10074 < CONVERT(DECIMAL(18, 5), @xxbad_scrapqty)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#领用数量不能超出本箱数量!#The quantity received cannot exceed the quantity in this box!', 11, 1);
                END;

                --最终判断是不是 已经插入备料日志表
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM HSUsingProductLog
                    WHERE USN = @xxbad_id
                          AND UsingNum = @xxbad_ship_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#不能重复提交标签!#Duplicate tag submission is not allowed!', 11, 1);
                END;
                --从当前缓存表中清除本标签
                DELETE FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      -- AND OpUser = @xxbad_user
                      --AND PartNum = @xxbad_part
                      AND LableID = @xxbad_id;
                DECLARE @newlableid VARCHAR(64) = NEWID();
                --如果是原材料 从Barocde_MaterialLable 表取箱
                IF @pt_pm_code = 0
                BEGIN
                    --如果标签数量等于领用数量则移库,否则需要生成新标签拆箱
                    IF @lableqty10074 = CONVERT(DECIMAL(18, 5), @xxbad_scrapqty)
                    BEGIN
                        PRINT '相等';
                        --插入条码主队列
                        INSERT INTO [dbo].[xxinbxml_mstr]
                        (
                            [xxinbxml_domain],
                            [xxinbxml_appid],
                            BarcodeInterFaceID,
                            [xxinbxml_status],
                            [xxinbxml_crtdate],
                            [xxinbxml_cimdate],
                            [xxinbxml_type],
                            [xxinbxml_extusr],
                            [xxinbxml_ord],
                            [xxinbxml_line],
                            [xxinbxml_part],
                            [xxinbxml_locfrm],
                            [xxinbxml_locto],
                            xxinbxml_lotfrm,
                            xxinbxml_lotto,
                            [xxinbxml_sitefrm],
                            [xxinbxml_siteto],
                            [xxinbxml_pallet],
                            [xxinbxml_box],
                            [xxinbxml_qty_chg]
                        )
                        SELECT @xxbad_domain,
                               'IC_TR',
                               @interfaceid,
                               0,
                               GETDATE(),
                               GETDATE(),
                               'CIM',
                               @xxbad_user,
                               '',
                               '',
                               partnum,
                               dbo.GetQADloc(currentloc),
                               dbo.GetQADloc(@xxbad_toloc),
                               lot,
                               lot,
                               @xxbad_fromsite,
                               @xxbad_tosite,
                               @xxbad_ship_id,
                               usn,
                               CONVERT(DECIMAL(18, 5), @xxbad_scrapqty)
                        FROM dbo.barocde_materiallable
                        WHERE usn = @xxbad_id;
                        PRINT @xxbad_id;
                        --标签插入子队列 用于计算库存
                        INSERT INTO [dbo].[xxinbxml_Det]
                        (
                            xxinbxml_Mstid,
                            BarcodeInterFaceID,
                            [xxinbxml_domain],
                            [xxinbxml_appid],
                            [xxinbxml_status],
                            [xxinbxml_crtdate],
                            [xxinbxml_cimdate],
                            [xxinbxml_type],
                            xxinbxml_extid,
                            [xxinbxml_extusr],
                            [xxinbxml_ord],
                            [xxinbxml_line],
                            [xxinbxml_part],
                            [xxinbxml_locfrm],
                            [xxinbxml_locto],
                            [xxinbxml_sitefrm],
                            [xxinbxml_siteto],
                            [xxinbxml_pallet],
                            [xxinbxml_box],
                            [xxinbxml_qty_chg],
                            xxinbxml_lotfrm,
                            xxinbxml_lotto,
                            xxinbxml_reffrm,
                            xxinbxml_refto
                        )
                        SELECT @@IDENTITY,
                               @interfaceid,
                               @xxbad_domain,
                               'IC_TR',
                               0,
                               GETDATE(),
                               GETDATE(),
                               'CIM',
                               usn,
                               @xxbad_user,
                               '',
                               '',
                               partnum,
                               currentloc,
                               @xxbad_toloc,
                               @xxbad_fromsite,
                               @xxbad_tosite,
                               '',
                               @xxbad_extension8,
                               CONVERT(DECIMAL(18, 5), @xxbad_scrapqty),
                               lot,
                               lot,
                               @xxbad_ref,
                               @xxbad_ref
                        FROM dbo.barocde_materiallable
                        WHERE usn = @xxbad_id;
                        --将标签的库位直接 改变 做移库事务
                        UPDATE dbo.barocde_materiallable
                        SET fromloc = currentloc,
                            status = 5,
                            currentloc = @xxbad_toloc,
                            allotnum = @xxbad_ship_id
                        WHERE usn = @xxbad_id;
                    END;
                    ELSE
                    BEGIN
                        PRINT '不相等';
                        --BEGIN TRAN
                        --生成新的标签
                        INSERT barocde_materiallable
                        (
                            id,
                            [usn],
                            [partnum],
                            [partdescription],
                            [parttype],
                            [lot],
                            [currentloc],
                            [fromloc],
                            [toloc],
                            [whloc],
                            [qty],
                            [site],
                            [isalive],
                            [laststatus],
                            [status],
                            [productusn],
                            [memo],
                            [pkgqty],
                            [ponum],
                            [poline],
                            [shipsn],
                            [po_duedate],
                            [recipient],
                            [supplynum],
                            [supplylot],
                            [supplypartnum],
                            [supplyname],
                            [extendfiled1],
                            [extendfiled2],
                            [extendfiled3],
                            [createtime],
                            [printtime],
                            [receiveuser],
                            [receivetime],
                            [inspectsn],
                            [inspecttype],
                            [okqty],
                            [unokqty],
                            [inspectresult],
                            [inspectuser],
                            [inspecttime],
                            [inbounduser],
                            [inboundtime],
                            [destroytime],
                            [destroyuser],
                            [destroymemo],
                            [checkloc],
                            [unit],
                            [retruntime],
                            [retrunuser]
                        )
                        SELECT @newlableid,
                               dbo.GetNextUSN(usn, 1),
                               [partnum],
                               [partdescription],
                               [parttype],
                               [lot],
                               currentloc,
                               fromloc,
                               [toloc],
                               [whloc],
                               CONVERT(DECIMAL(18, 5), @xxbad_scrapqty),
                               [site],
                               [isalive],
                               [laststatus],
                               [status],
                               [productusn],
                               [memo],
                               [pkgqty],
                               [ponum],
                               [poline],
                               [shipsn],
                               [po_duedate],
                               [recipient],
                               [supplynum],
                               [supplylot],
                               [supplypartnum],
                               [supplyname],
                               [extendfiled1],
                               [extendfiled2],
                               [extendfiled3],
                               [createtime],
                               [printtime],
                               [receiveuser],
                               [receivetime],
                               [inspectsn],
                               [inspecttype],
                               [okqty],
                               [unokqty],
                               [inspectresult],
                               [inspectuser],
                               [inspecttime],
                               [inbounduser],
                               [inboundtime],
                               [destroytime],
                               [destroyuser],
                               [destroymemo],
                               [checkloc],
                               [unit],
                               [retruntime],
                               [retrunuser]
                        FROM dbo.barocde_materiallable
                        WHERE usn = @xxbad_id;

                        --将原来的箱子的里面的数量修改一下
                        UPDATE dbo.barocde_materiallable
                        SET qty = qty - CONVERT(DECIMAL(18, 5), @xxbad_scrapqty)
                        WHERE usn = @xxbad_id;
                        --插入条码主队列
                        INSERT INTO [dbo].[xxinbxml_mstr]
                        (
                            [xxinbxml_domain],
                            [xxinbxml_appid],
                            BarcodeInterFaceID,
                            [xxinbxml_status],
                            [xxinbxml_crtdate],
                            [xxinbxml_cimdate],
                            [xxinbxml_type],
                            [xxinbxml_extusr],
                            [xxinbxml_ord],
                            [xxinbxml_line],
                            [xxinbxml_part],
                            [xxinbxml_locfrm],
                            [xxinbxml_locto],
                            xxinbxml_lotfrm,
                            xxinbxml_lotto,
                            [xxinbxml_sitefrm],
                            [xxinbxml_siteto],
                            [xxinbxml_pallet],
                            [xxinbxml_box],
                            [xxinbxml_qty_chg]
                        )
                        SELECT @xxbad_domain,
                               'IC_TR',
                               @interfaceid,
                               0,
                               GETDATE(),
                               GETDATE(),
                               'CIM',
                               @xxbad_user,
                               '',
                               '',
                               partnum,
                               dbo.GetQADloc(currentloc),
                               dbo.GetQADloc(@xxbad_toloc),
                               lot,
                               lot,
                               @xxbad_fromsite,
                               @xxbad_tosite,
                               @xxbad_ship_id,
                               usn,
                               CONVERT(DECIMAL(18, 5), @xxbad_scrapqty)
                        FROM dbo.barocde_materiallable
                        WHERE id = @newlableid;
                        --标签插入子队列 用于计算库存
                        INSERT INTO [dbo].[xxinbxml_Det]
                        (
                            xxinbxml_Mstid,
                            BarcodeInterFaceID,
                            [xxinbxml_domain],
                            [xxinbxml_appid],
                            [xxinbxml_status],
                            [xxinbxml_crtdate],
                            [xxinbxml_cimdate],
                            [xxinbxml_type],
                            xxinbxml_extid,
                            [xxinbxml_extusr],
                            [xxinbxml_ord],
                            [xxinbxml_line],
                            [xxinbxml_part],
                            [xxinbxml_locfrm],
                            [xxinbxml_locto],
                            [xxinbxml_sitefrm],
                            [xxinbxml_siteto],
                            [xxinbxml_pallet],
                            [xxinbxml_box],
                            [xxinbxml_qty_chg],
                            xxinbxml_lotfrm,
                            xxinbxml_lotto,
                            xxinbxml_reffrm,
                            xxinbxml_refto
                        )
                        SELECT @@IDENTITY,
                               @interfaceid,
                               @xxbad_domain,
                               'IC_TR',
                               0,
                               GETDATE(),
                               GETDATE(),
                               'CIM',
                               usn,
                               @xxbad_user,
                               '',
                               '',
                               partnum,
                               currentloc,
                               @xxbad_toloc,
                               @xxbad_fromsite,
                               @xxbad_tosite,
                               '',
                               @xxbad_extension8,
                               CONVERT(DECIMAL(18, 5), @xxbad_scrapqty),
                               lot,
                               lot,
                               @xxbad_ref,
                               @xxbad_ref
                        FROM dbo.barocde_materiallable
                        WHERE id = @newlableid;

                        --将标签中当前库位,状态 修改一下
                        UPDATE barocde_materiallable
                        SET currentloc = @xxbad_toloc,
                            allotnum = @xxbad_ship_id
                        WHERE id = @newlableid;

                    END;
                    --将出库标签备份到日志表
                    INSERT INTO [dbo].[HSUsingProductLog]
                    (
                        [UsingNum],
                        [ps_comp],
                        [USN],
                        [CurrentLoc],
                        [Qty],
                        pt_desc1,
                        pt_desc2
                    )
                    SELECT @xxbad_ship_id,
                           @xxbad_part,
                           @xxbad_id,
                           @xxbad_toloc,
                           @xxbad_scrapqty,
                           partdescription,
                           pt_desc2
                    FROM dbo.barocde_materiallable
                    WHERE usn = @xxbad_id;
                END;
                ELSE
                BEGIN
                    --如果标签数量等于领用数量则移库 ，否则需要生成新标签拆箱
                    IF @lableqty10074 = CONVERT(DECIMAL(18, 5), @xxbad_scrapqty)
                    BEGIN
                        --插入条码主队列
                        INSERT INTO [dbo].[xxinbxml_mstr]
                        (
                            [xxinbxml_domain],
                            [xxinbxml_appid],
                            BarcodeInterFaceID,
                            [xxinbxml_status],
                            [xxinbxml_crtdate],
                            [xxinbxml_cimdate],
                            [xxinbxml_type],
                            [xxinbxml_extusr],
                            [xxinbxml_ord],
                            [xxinbxml_line],
                            [xxinbxml_part],
                            [xxinbxml_locfrm],
                            [xxinbxml_locto],
                            xxinbxml_lotfrm,
                            xxinbxml_lotto,
                            [xxinbxml_sitefrm],
                            [xxinbxml_siteto],
                            [xxinbxml_pallet],
                            [xxinbxml_box],
                            [xxinbxml_qty_chg]
                        )
                        SELECT @xxbad_domain,
                               'IC_TR',
                               @interfaceid,
                               0,
                               GETDATE(),
                               GETDATE(),
                               'CIM',
                               @xxbad_user,
                               '',
                               '',
                               PartNum,
                               dbo.GetQADloc(CurrentLoc),
                               dbo.GetQADloc(@xxbad_toloc),
                               Lot,
                               Lot,
                               @xxbad_fromsite,
                               @xxbad_tosite,
                               '',
                               USN,
                               CONVERT(DECIMAL(18, 5), @xxbad_scrapqty)
                        FROM dbo.Barocde_BoxlLable
                        WHERE USN = @xxbad_id;
                        --标签插入子队列 用于计算库存
                        INSERT INTO [dbo].[xxinbxml_Det]
                        (
                            xxinbxml_Mstid,
                            BarcodeInterFaceID,
                            [xxinbxml_domain],
                            [xxinbxml_appid],
                            [xxinbxml_status],
                            [xxinbxml_crtdate],
                            [xxinbxml_cimdate],
                            [xxinbxml_type],
                            xxinbxml_extid,
                            [xxinbxml_extusr],
                            [xxinbxml_ord],
                            [xxinbxml_line],
                            [xxinbxml_part],
                            [xxinbxml_locfrm],
                            [xxinbxml_locto],
                            [xxinbxml_sitefrm],
                            [xxinbxml_siteto],
                            [xxinbxml_pallet],
                            [xxinbxml_box],
                            [xxinbxml_qty_chg],
                            xxinbxml_lotfrm,
                            xxinbxml_lotto,
                            xxinbxml_reffrm,
                            xxinbxml_refto
                        )
                        SELECT @@IDENTITY,
                               @interfaceid,
                               @xxbad_domain,
                               'IC_TR',
                               0,
                               GETDATE(),
                               GETDATE(),
                               'CIM',
                               USN,
                               @xxbad_user,
                               '',
                               '',
                               PartNum,
                               CurrentLoc,
                               @xxbad_toloc,
                               @xxbad_fromsite,
                               @xxbad_tosite,
                               @xxbad_ship_id,
                               @xxbad_extension8,
                               CONVERT(DECIMAL(18, 5), @xxbad_scrapqty),
                               Lot,
                               Lot,
                               @xxbad_ref,
                               @xxbad_ref
                        FROM dbo.Barocde_BoxlLable
                        WHERE USN = @xxbad_id;
                        --将标签的库位变更 ，直接做移库
                        UPDATE dbo.Barocde_BoxlLable
                        SET FromLoc = CurrentLoc,
                            Status = 3,
                            CurrentLoc = @xxbad_toloc,
                            allotnum = @xxbad_ship_id
                        WHERE USN = @xxbad_id;
                    END;
                    ELSE
                    BEGIN
                        --生成新的标签
                        INSERT dbo.Barocde_BoxlLable
                        (
                            ID,
                            USN,
                            PartNum,
                            PartDescription,
                            Lot,
                            CurrentLoc,
                            FromLoc,
                            ToLoc,
                            WHloc,
                            Qty,
                            Site,
                            LastStatus,
                            Status,
                            WorkOp,
                            PkgQty,
                            WoNum,
                            ShipSN,
                            Wo_DueDate,
                            ProLine,
                            CustomNum,
                            CustomLot,
                            CustomPartNum,
                            CustomName,
                            ExtendFiled1,
                            ExtendFiled2,
                            ExtendFiled3,
                            CreateTime,
                            FlushStatus,
                            BackwashResult,
                            BackwashUser,
                            BackwashTime,
                            InspectSN,
                            InspectType,
                            OkQty,
                            UnOkQty,
                            InspectResult,
                            InspectUser,
                            InspectTime,
                            InboundUser,
                            InboundTime,
                            DestroyTime,
                            DestroyUser,
                            DestroyMemo,
                            PrintTime,
                            PurchaseOrder,
                            PoLine,
                            CheckLoc,
                            BoxTime,
                            BoxUser,
                            PrintQty,
                            PalletLable,
                            IsComplex
                        )
                        SELECT @newlableid,
                               dbo.GetNextUSN(USN, 0),
                               [PartNum],
                               [PartDescription],
                               [Lot],
                               CurrentLoc,
                               [FromLoc],
                               [ToLoc],
                               [WHloc],
                               CONVERT(DECIMAL(18, 5), @xxbad_scrapqty),
                               [Site],
                               [LastStatus],
                               [Status],
                               [WorkOp],
                               [PkgQty],
                               [WoNum],
                               [ShipSN],
                               [Wo_DueDate],
                               [ProLine],
                               [CustomNum],
                               [CustomLot],
                               [CustomPartNum],
                               [CustomName],
                               [ExtendFiled1],
                               [ExtendFiled2],
                               [ExtendFiled3],
                               [CreateTime],
                               [FlushStatus],
                               [BackwashResult],
                               [BackwashUser],
                               [BackwashTime],
                               [InspectSN],
                               [InspectType],
                               [OkQty],
                               [UnOkQty],
                               [InspectResult],
                               [InspectUser],
                               [InspectTime],
                               [InboundUser],
                               [InboundTime],
                               [DestroyTime],
                               [DestroyUser],
                               [DestroyMemo],
                               [PrintTime],
                               [PurchaseOrder],
                               [PoLine],
                               [CheckLoc],
                               [BoxTime],
                               [BoxUser],
                               [PrintQty],
                               [PalletLable],
                               [IsComplex]
                        FROM dbo.Barocde_BoxlLable
                        WHERE USN = @xxbad_id;
                        --将原来的箱子的里面的数量修改一下
                        UPDATE dbo.Barocde_BoxlLable
                        SET Qty = Qty - CONVERT(DECIMAL(18, 5), @xxbad_scrapqty)
                        WHERE USN = @xxbad_id;
                        --插入条码主队列
                        INSERT INTO [dbo].[xxinbxml_mstr]
                        (
                            [xxinbxml_domain],
                            [xxinbxml_appid],
                            BarcodeInterFaceID,
                            [xxinbxml_status],
                            [xxinbxml_crtdate],
                            [xxinbxml_cimdate],
                            [xxinbxml_type],
                            [xxinbxml_extusr],
                            [xxinbxml_ord],
                            [xxinbxml_line],
                            [xxinbxml_part],
                            [xxinbxml_locfrm],
                            [xxinbxml_locto],
                            xxinbxml_lotfrm,
                            xxinbxml_lotto,
                            [xxinbxml_sitefrm],
                            [xxinbxml_siteto],
                            [xxinbxml_pallet],
                            [xxinbxml_box],
                            [xxinbxml_qty_chg]
                        )
                        SELECT @xxbad_domain,
                               'IC_TR',
                               @interfaceid,
                               0,
                               GETDATE(),
                               GETDATE(),
                               'CIM',
                               @xxbad_user,
                               '',
                               '',
                               PartNum,
                               dbo.GetQADloc(CurrentLoc),
                               dbo.GetQADloc(@xxbad_toloc),
                               Lot,
                               Lot,
                               @xxbad_fromsite,
                               @xxbad_tosite,
                               '',
                               USN,
                               CONVERT(DECIMAL(18, 5), @xxbad_scrapqty)
                        FROM dbo.Barocde_BoxlLable
                        WHERE ID = @newlableid;
                        --标签插入子队列 用于计算库存
                        INSERT INTO [dbo].[xxinbxml_Det]
                        (
                            xxinbxml_Mstid,
                            BarcodeInterFaceID,
                            [xxinbxml_domain],
                            [xxinbxml_appid],
                            [xxinbxml_status],
                            [xxinbxml_crtdate],
                            [xxinbxml_cimdate],
                            [xxinbxml_type],
                            xxinbxml_extid,
                            [xxinbxml_extusr],
                            [xxinbxml_ord],
                            [xxinbxml_line],
                            [xxinbxml_part],
                            [xxinbxml_locfrm],
                            [xxinbxml_locto],
                            [xxinbxml_sitefrm],
                            [xxinbxml_siteto],
                            [xxinbxml_pallet],
                            [xxinbxml_box],
                            [xxinbxml_qty_chg],
                            xxinbxml_lotfrm,
                            xxinbxml_lotto,
                            xxinbxml_reffrm,
                            xxinbxml_refto
                        )
                        SELECT @@IDENTITY,
                               @interfaceid,
                               @xxbad_domain,
                               'IC_TR',
                               0,
                               GETDATE(),
                               GETDATE(),
                               'CIM',
                               USN,
                               @xxbad_user,
                               '',
                               '',
                               PartNum,
                               CurrentLoc,
                               @xxbad_toloc,
                               @xxbad_fromsite,
                               @xxbad_tosite,
                               @xxbad_ship_id,
                               @xxbad_extension8,
                               CONVERT(DECIMAL(18, 5), @xxbad_scrapqty),
                               Lot,
                               Lot,
                               @xxbad_ref,
                               @xxbad_ref
                        FROM dbo.Barocde_BoxlLable
                        WHERE ID = @newlableid;
                        --将标签中当前库位 修改一下
                        UPDATE Barocde_BoxlLable
                        SET CurrentLoc = @xxbad_toloc,
                            allotnum = @xxbad_ship_id
                        WHERE ID = @newlableid;
                    END;
                    --将出库标签备份到日志表
                    INSERT INTO [dbo].[HSUsingProductLog]
                    (
                        [UsingNum],
                        [ps_comp],
                        [USN],
                        [CurrentLoc],
                        [Qty],
                        pt_desc1,
                        pt_desc2
                    )
                    SELECT @xxbad_ship_id,
                           @xxbad_part,
                           @xxbad_id,
                           @xxbad_toloc,
                           @xxbad_scrapqty,
                           PartDescription,
                           ExtendFiled2
                    FROM Barocde_BoxlLable
                    WHERE USN = @xxbad_id;
                END;
                --从当前缓存表中清除本标签
                DELETE FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                      --AND PartNum = @xxbad_part
                      AND LableID = @xxbad_id;

                --改变当前领料单当前零件的状态和累计备料量
                UPDATE dbo.HSProdusing
                SET UsingQty = ISNULL(UsingQty, 0.00) + CONVERT(DECIMAL(18, 5), @xxbad_scrapqty),
                    Status = 1,
                    lablecount = ISNULL(lablecount, 0) + 1
                WHERE UsingNum = @xxbad_ship_id
                      AND ps_comp = @xxbad_part;
                --成品领料单如果累计备料量 已经大于计划量 则自动关闭当前行领料单   半成品不自动关闭
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM fgallotpaper
                    WHERE allotnum = @xxbad_ship_id
                )
                BEGIN
                    UPDATE dbo.HSProdusing
                    SET Status = 2,
                        AlltoTime = GETDATE()
                    WHERE UsingNum = @xxbad_ship_id
                          AND ps_comp = @xxbad_part
                          AND UsingQty >= PlanQty;
                END;
                --返回第一个dataset 到前台
                SELECT '' xxbad_id,
                       'xxbad_id' focus,
                       0 xxbad_scrapqty,
                       UsingQty xxbad_qty,
                       @xxbad_ship_id xxbad_ship_id,
                       pt_desc1 xxbad_desc,
                       PlanQty xxbad_rj_qty,
                       @xxbad_part xxbad_part
                FROM dbo.HSProdusing
                WHERE UsingNum = @xxbad_ship_id
                      AND ps_comp = @xxbad_part;
                --返回第二个dataset 到前台
                SELECT LableID USN,
                       Qty,
                       CurrentLoc
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND PartNum = @xxbad_part
                      AND OpUser = @xxbad_user
                ORDER BY LableID;
                RAISERROR(N'Info_MESSAGE#本箱领料出库成功!#Material issuance from this box was successful!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                --生成JSON
                SET @json =
                (
                    SELECT DISTINCT TOP 10
                           partnum
                    FROM dbo.barocde_materiallable
                    WHERE currentloc = 'Line2'
                    FOR JSON PATH
                );
                SELECT 'xxbad_ship_id' focus,
                       @json xxbad_part;
                SELECT 1;

            END;
            ELSE IF @ScanData = 'xxbad_ship_id'
            BEGIN
                SELECT 'xxbad_part' focus,
                       @xxbad_ship_id xxbad_ship_id,
                       @xxbad_purchacorder xxbad_purchacorder;
                SELECT 1;

            END;
            ELSE IF @ScanData = 'xxbad_part'
            BEGIN
                --从领料单表获取计划量与累计备料量
                SELECT @xxbad_rj_qty = PlanQty,
                       @pt_pm_code = IsFG,
                       @xxbad_extension2 = lablecount,
                       @xxbad_qty = ISNULL(UsingQty, '0')
                FROM dbo.HSProdusing
                WHERE ps_comp = @xxbad_part
                      AND UsingNum = @xxbad_ship_id;

                IF @pt_pm_code IS NULL
                BEGIN
                    SET @ErrorMessage = N'ERROR_MESSAGE#零件不包含在领料单中!#The part is not included in the picking list!';
                    RAISERROR(@ErrorMessage, 11, 1);
                END;

                --获取零件信息
                SELECT @xxbad_desc = pt_desc1,
                       @xxbad_extension1 = pt_desc2
                FROM dbo.pt_mstr
                WHERE pt_part = @xxbad_part;
                --判断当前零件 是不是被别人扫描提交了
                SELECT TOP 1
                       @cacheuser = OpUser
                FROM dbo.Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND ShipID = @xxbad_ship_id
                      AND PartNum = @xxbad_part
                      AND ScanTime IS NOT NULL;
                IF (ISNULL(@cacheuser, @xxbad_user) <> @xxbad_user)
                BEGIN
                    SET @ErrorMessage
                        = N'ERROR_MESSAGE#该箱码被用户' + @cacheuser + N'扫描，请提醒其操作!#The box code has been scanned by user ' + @cacheuser + N'. Please remind them to take action!';
                    RAISERROR(@ErrorMessage, 11, 1);
                END;
                CREATE TABLE #tempLable
                (
                    [ID] [INT] IDENTITY(1, 1) NOT NULL,
                    USN NVARCHAR(50) NULL,
                    Qty DECIMAL(18, 5) NULL,
                    CurrentLoc NVARCHAR(50) NULL,
                    lot NVARCHAR(50) NULL
                );
                --如果零件号是 原材料从原材料表 否则是半成品从箱标签表
                IF @pt_pm_code = 1
                BEGIN
                    INSERT INTO #tempLable
                    SELECT USN,
                           Qty,
                           CurrentLoc,
                           Lot
                    FROM dbo.Barocde_BoxlLable
                    WHERE PartNum = @xxbad_part
                          AND Status = 3
                          AND Qty > 0
                          AND dbo.GetlocAreaId(CurrentLoc) IN ( 4, 2 )
                    ORDER BY Lot,
                             USN ASC;
                END;
                ELSE
                BEGIN
                    --从原材料表 按照标签号排序
                    INSERT INTO #tempLable
                    SELECT usn,
                           qty,
                           currentloc,
                           lot
                    FROM barocde_materiallable
                    WHERE partnum = @xxbad_part
                          AND status = 4
                          AND Qty > 0
                          AND dbo.GetlocAreaId(CurrentLoc) IN ( 4, 2 )
                    ORDER BY lot,
                             usn ASC;
                END;

                --按照汇总数量排序临时表
                SELECT ID,
                       USN,
                       Qty,
                       CurrentLoc,
                       (
                           SELECT SUM(Qty) FROM #tempLable b WHERE a.ID >= b.ID
                       ) fQty,
                       a.lot
                INTO #t_lable
                FROM #tempLable a
                ORDER BY ID;

                --先删除然后 插入动态高速缓存表 (删除别人的)
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND ShipID = @xxbad_ship_id
                      AND PartNum = @xxbad_part;
                --删除自己的
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                --INSERT INTO [dbo].[Barcode_OperateCache]
                --(
                --    id,
                --    [AppID],
                --    [OpUser],
                --    LableID,
                --    [Qty],
                --    CurrentLoc,
                --    ExtendedField1,
                --    ExtendedField2,
                --    ShipID,
                --    PartNum
                --)
                --SELECT NEWID(),
                --       @interfaceid,
                --       @xxbad_user,
                --       a.USN,
                --       a.Qty,
                --       CurrentLoc,
                --       a.fQty,
                --       a.Qty,
                --       @xxbad_ship_id,
                --       @xxbad_part
                --FROM #t_lable a
                --WHERE ID <= ISNULL(
                --            (
                --                SELECT TOP 1
                --                       ID
                --                FROM #t_lable
                --                WHERE fQty > CONVERT(
                --                                        DECIMAL(18, 5),
                --                                        ISNULL(
                --                                                  (CONVERT(DECIMAL(18, 5), @xxbad_rj_qty)
                --                                                   - CONVERT(DECIMAL(18, 5), @xxbad_qty)
                --                                                  ),
                --                                                  0
                --                                              )
                --                                    )
                --                ORDER BY ID
                --            ),
                --            ID
                --                  )
                --      AND CONVERT(DECIMAL(18, 5), @xxbad_rj_qty) > CONVERT(DECIMAL(18, 5), @xxbad_qty);
                SELECT a.USN,
                       a.Qty,
                       CurrentLoc,
                       a.lot
                INTO #usnlotall
                FROM #t_lable a
                WHERE ID <= ISNULL(
                            (
                                SELECT TOP 1
                                       ID
                                FROM #t_lable
                                WHERE fQty > CONVERT(
                                                        DECIMAL(18, 5),
                                                        ISNULL(
                                                                  (CONVERT(DECIMAL(18, 5), @xxbad_rj_qty)
                                                                   - CONVERT(DECIMAL(18, 5), @xxbad_qty)
                                                                  ),
                                                                  0
                                                              )
                                                    )
                                ORDER BY ID
                            ),
                            ID
                                  )
                      AND CONVERT(DECIMAL(18, 5), @xxbad_rj_qty) > CONVERT(DECIMAL(18, 5), @xxbad_qty);
                --如果是半成品 需要从半成品 表 获取数据
                IF @pt_pm_code = 1
                BEGIN
                    INSERT INTO [dbo].[Barcode_OperateCache]
                    (
                        id,
                        [AppID],
                        [OpUser],
                        LableID,
                        [Qty],
                        CurrentLoc,
                        ExtendedField1,
                        ExtendedField2,
                        ShipID,
                        PartNum
                    )
                    SELECT NEWID(),
                           @interfaceid,
                           @xxbad_user,
                           a.USN,
                           a.Qty,
                           CurrentLoc,
                           a.Lot,
                           a.Qty,
                           @xxbad_ship_id,
                           @xxbad_part
                    FROM dbo.Barocde_BoxlLable a
                    WHERE a.PartNum = @xxbad_part
                          AND Status = 3
                          AND Qty > 0
                          AND dbo.GetlocAreaId(CurrentLoc) IN ( 4, 2 )
                          AND a.Lot IN
                              (
                                  SELECT lot FROM #usnlotall
                              )
                    ORDER BY Lot ASC;

                END;
                ELSE --如果是原材料 需要从原材料表 获取数据
                BEGIN
                    INSERT INTO [dbo].[Barcode_OperateCache]
                    (
                        id,
                        [AppID],
                        [OpUser],
                        LableID,
                        [Qty],
                        CurrentLoc,
                        ExtendedField1,
                        ExtendedField2,
                        ShipID,
                        PartNum
                    )
                    SELECT NEWID(),
                           @interfaceid,
                           @xxbad_user,
                           a.usn,
                           a.qty,
                           currentloc,
                           a.lot,
                           a.qty,
                           @xxbad_ship_id,
                           @xxbad_part
                    FROM dbo.barocde_materiallable a
                    WHERE partnum = @xxbad_part
                          AND status = 4
                          AND qty > 0
                          AND dbo.GetlocAreaId(CurrentLoc) IN ( 4, 2 )
                          AND a.lot IN
                              (
                                  SELECT lot FROM #usnlotall
                              )
                    ORDER BY lot ASC;
                END;
                --返回第一个dataset
                SELECT @xxbad_desc xxbad_desc,
                       @xxbad_rj_qty xxbad_rj_qty,
                       '0' xxbad_scrapqty,
                       '' xxbad_id,
                       @xxbad_extension1 xxbad_extension1,
                       @xxbad_extension2 xxbad_extension2,
                       @xxbad_purchacorder xxbad_purchacorder,
                       @xxbad_ship_id xxbad_ship_id,
                       'xxbad_id' focus,
                       @xxbad_part xxbad_part,
                       @xxbad_qty xxbad_qty;
                --按照大于等于需求量总标签列表  并存入第二个dataset
                SELECT LableID USN,
                       ExtendedField2 Qty,
                       CurrentLoc
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND PartNum = @xxbad_part
                      AND OpUser = @xxbad_user
                ORDER BY LableID;
            END;
            ELSE --只接受标签号扫描
            BEGIN
                --首先判断领料单号是不是合法
                IF ISNULL(@xxbad_ship_id, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请先选择领料单号!#Please select the material requisition number first!', 11, 1);

                END;
                --判断零件号 是不是合法
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请先选择零件号!#Please select a part number first!', 11, 1);

                END;
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM HSUsingProductLog
                    WHERE USN = @xxbad_id
                          AND UsingNum = @xxbad_ship_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#不能重复提交标签!#Duplicate tag submission is not allowed!', 11, 1);
                END;
                --限请扫描推荐的标签
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                          AND LableID = @xxbad_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请扫描推荐的标签!#Please scan the recommended tags!', 11, 1);
                END;
                DECLARE @currentlot VARCHAR(60) = '';
                SELECT @currentlot = ExtendedField1
                FROM dbo.Barcode_OperateCache
                WHERE LableID = @xxbad_id
                      AND AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                IF @currentlot = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#系统故障!#System failure!', 11, 1);
                END;
                --当同一种物料 有两个批次的时候 限制 必须优先扫描第一个批次
                DECLARE @minlot VARCHAR(60) = '';
                SELECT TOP 1
                       @minlot = MIN(ExtendedField1)
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                      AND ScanTime IS NULL;
                IF @currentlot <> @minlot
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请按照批次顺序扫描标签!#Please scan the labels in batch order!', 11, 1);
                END;
                --判断上一箱有没有点击提交按钮
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                          AND ScanTime IS NOT NULL
                          AND LableID <> @xxbad_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#上一张箱码没有点击领料按钮!#The previous box code did not click the material picking button!', 11, 1);

                END;
                DECLARE @needqty DECIMAL(18, 5) = 0;
                --如果是成品领料单  就不允许超额领料
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM fgallotpaper
                    WHERE allotnum = @xxbad_ship_id
                )
                BEGIN
                    --定义欠缴量  计划量 减去 已发量
                    SET @needqty
                        = CONVERT(DECIMAL(18, 5), @xxbad_rj_qty) - ISNULL(CONVERT(DECIMAL(18, 5), @xxbad_qty), 0);
                    IF @needqty < 0
                        RAISERROR(N'ERROR_MESSAGE#成品领料单不允许超额发料!#Finished goods requisition form does not allow over-issuance!', 11, 1);
                END;
                UPDATE [Barcode_OperateCache]
                SET ScanTime = GETDATE()
                WHERE LableID = @xxbad_id
                      AND AppID = @interfaceid;

                --返回第一个dataset  
                SELECT CASE
                           WHEN @needqty > 0
                                AND @needqty < Qty THEN
                               @needqty
                           ELSE
                               Qty
                       END xxbad_scrapqty,
                       @xxbad_desc xxbad_desc,
                       @xxbad_rj_qty xxbad_rj_qty,
                       @xxbad_id xxbad_id,
                       @xxbad_extension1 xxbad_extension1,
                       @xxbad_extension2 xxbad_extension2,
                       @xxbad_purchacorder xxbad_purchacorder,
                       @xxbad_ship_id xxbad_ship_id,
                       'xxbad_id' focus,
                       @xxbad_part xxbad_part,
                       @xxbad_qty xxbad_qty
                FROM [Barcode_OperateCache]
                WHERE LableID = @xxbad_id;
                --返回第二个data 到前台
                SELECT [LableID] USN,
                       ExtendedField2 Qty,
                       CurrentLoc,
                       ScanTime
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user
                      AND PartNum = @xxbad_part
                ORDER BY LableID;
            END;
        END;
        IF @interfaceid IN ( 10076 ) --原材料有标签退库  佰安汽车用品有限公司 使用的
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断当前库位 是否和到库位相同
                SELECT @xxbad_fromloc = currentloc,
                       @xxbad_rj_qty = qty
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id
                      AND status = 4;
                IF ISNULL(@xxbad_fromloc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                IF (ISNULL(@xxbad_fromloc, '') = ISNULL(@xxbad_toloc, ''))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前标签已经在到库位下面了!#The current label is already under the destination location!', 11, 1);

                END;
                --判断当前标签库位 是不是线边库位
                --IF (dbo.GetQADloc(@xxbad_fromloc) NOT IN
                --    (
                --        SELECT LineCode FROM dbo.ProdLine
                --    )
                --   )
                --BEGIN
                --    RAISERROR(N'ERROR_MESSAGE#当前标签不在线边库位!#The current label is not in the edge storage location!', 11, 1);

                --END;

                --判断退库数量 不能为空
                IF CONVERT(DECIMAL(18, 4), @xxbad_qty) <= 0
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请输入本次退库量!#Please enter the return quantity!', 11, 1);

                END;
                --判断退库数量不能大于标签总数量
                IF CONVERT(DECIMAL(18, 4), @xxbad_qty) > CONVERT(DECIMAL(18, 4), @xxbad_rj_qty)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#退库量不能大于箱标签数量!#The return quantity cannot exceed the number of box labels!', 11, 1);

                END;

                --如果是领料单出库的 需要回滚领用数量
                UPDATE dbo.HSProdusing
                SET UsingQty = UsingQty - @xxbad_qty
                WHERE UsingNum = @xxbad_ship_id
                      AND ps_comp = @xxbad_part;
                --更新标签的当前库位和当前数量  状态
                UPDATE dbo.barocde_materiallable
                SET fromloc = currentloc,
                    qty = @xxbad_qty,
                    memo = '线边退库',
                    status = 4,
                    currentloc = @xxbad_toloc
                WHERE usn = @xxbad_id;
                ----插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg]
                )
                SELECT @xxbad_domain,
                       'IC_TR',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       '',
                       partnum,
                       dbo.GetQADloc(@xxbad_fromloc),
                       dbo.GetQADloc(@xxbad_toloc),
                       lot,
                       lot,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       usn,
                       qty
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
                ----标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       usn,
                       @xxbad_user,
                       '',
                       '',
                       partnum,
                       @xxbad_fromloc,
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       @xxbad_id,
                       qty,
                       lot,
                       lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id;
                --打印标签
                --EXEC PrintMaterialLable @xxbad_id;
                RAISERROR(N'Info_MESSAGE#标签移库成功!#Label transfer successful!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus,
                       'tkq' xxbad_toloc;
            END;
            ELSE IF @ScanData = 'xxbad_toloc'
            BEGIN
                --判断库位是否合法
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_Location
                    WHERE xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    SELECT @xxbad_toloc xxbad_toloc,
                           'xxbad_id' focus;
                END;
                ELSE
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#库位不存在!#Location does not exist!', 11, 1);
                END;

            END;
            ELSE --认为扫描的是条码数据
            BEGIN
                --读取标签中的信息
                SELECT @xxbad_id = usn,
                       @xxbad_qty = qty,
                       @xxbad_part = partnum,
                       @xxbad_lot = lot,
                       @xxbad_ship_id = allotnum,
                       @xxbad_desc = partdescription,
                       @xxbad_fromloc = currentloc
                FROM dbo.barocde_materiallable
                WHERE usn = @xxbad_id
                      AND status IN ( 5, 6 );
                --判断标签是否合法
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       @xxbad_qty xxbad_qty,
                       @xxbad_part xxbad_part,
                       @xxbad_desc xxbad_desc,
                       @xxbad_lot xxbad_lot,
                       @xxbad_ship_id xxbad_ship_id,
                       'xxbad_toloc,xxbad_qty' READONLY,
                       @xxbad_fromloc xxbad_fromloc,
                       @xxbad_toloc xxbad_toloc;
            END;

        END;
        IF @interfaceid IN ( 10106 ) --半成品有标签退库 佰安汽车用品有限公司 使用的
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断当前库位 是否和到库位相同
                SELECT @xxbad_fromloc = CurrentLoc,
                       @xxbad_rj_qty = Qty
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id
                      AND Status = 3;
                IF ISNULL(@xxbad_fromloc, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                IF (ISNULL(@xxbad_fromloc, '') = ISNULL(@xxbad_toloc, ''))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前标签已经在到库位下面了!#The current label is already under the destination location!', 11, 1);
                END;
                --判断退库数量 不能为空
                IF CONVERT(DECIMAL(18, 5), @xxbad_qty) <= 0
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请输入本次退库量!#Please enter the return quantity!', 11, 1);

                END;
                --判断退库数量不能大于标签总数量
                IF CONVERT(DECIMAL(18, 5), @xxbad_qty) > CONVERT(DECIMAL(18, 5), @xxbad_rj_qty)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#退库量不能大于箱标签数量!#The return quantity cannot exceed the number of box labels!', 11, 1);

                END;
                --如果是领料单出库的 需要回滚领用数量
                UPDATE dbo.HSProdusing
                SET UsingQty = UsingQty - @xxbad_qty
                WHERE UsingNum = @xxbad_ship_id
                      AND ps_comp = @xxbad_part;
                --更新标签的当前库位和当前数量  状态
                UPDATE dbo.Barocde_BoxlLable
                SET FromLoc = CurrentLoc,
                    Qty = @xxbad_qty,
                    Memo = '线边退库',
                    Status = 3,
                    CurrentLoc = @xxbad_toloc
                WHERE USN = @xxbad_id;
                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg]
                )
                SELECT @xxbad_domain,
                       'IC_TR',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       dbo.GetQADloc(@xxbad_fromloc),
                       dbo.GetQADloc(@xxbad_toloc),
                       Lot,
                       Lot,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       USN,
                       Qty
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       USN,
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       @xxbad_fromloc,
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       @xxbad_id,
                       @xxbad_qty,
                       Lot,
                       Lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                RAISERROR(N'Info_MESSAGE#标签移库成功!#Label transfer successful!', 11, 1);
            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_id' focus,
                       'tkq' xxbad_toloc;
            END;
            ELSE IF @ScanData = 'xxbad_toloc'
            BEGIN
                --判断库位是否合法
                IF EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_Location
                    WHERE xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    SELECT @xxbad_toloc xxbad_toloc,
                           'xxbad_id' focus;
                END;
                ELSE
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#库位不存在!#Location does not exist!', 11, 1);

                END;
            END;
            ELSE --认为扫描的是条码数据
            BEGIN
                --读取标签中的信息
                SELECT @xxbad_id = USN,
                       @xxbad_qty = Qty,
                       @xxbad_part = PartNum,
                       @xxbad_lot = Lot,
                       @xxbad_ship_id = allotnum,
                       @xxbad_desc = PartDescription,
                       @xxbad_fromloc = CurrentLoc
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id
                      AND Status = 3;
                --判断标签是否合法
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);
                END;

                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       0 xxbad_qty,
                       @xxbad_part xxbad_part,
                       @xxbad_desc xxbad_desc,
                       @xxbad_qty xxbad_rj_qty,
                       @xxbad_ship_id xxbad_ship_id,
                       @xxbad_lot xxbad_lot,
                       'xxbad_toloc,xxbad_qty' READONLY,
                       @xxbad_fromloc xxbad_fromloc,
                       @xxbad_toloc xxbad_toloc;
            END;

        END;
        IF @interfaceid IN ( 10086 ) --出口件组托
        BEGIN
            DECLARE @palletqty DECIMAL; --一托的包装量 
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断是否扫描了标签  
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#您没有扫描任何标签!#You have not scanned any tags!', 11, 1);

                END;
                --判断是不是整托 已经装满，不装满不允许提交
                DECLARE @totalqty10078 DECIMAL(18, 5),
                        @totalbox INT;
                SELECT @totalqty10078 = SUM(Qty),
                       @totalbox = SUM(1)
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                IF ISNULL(@totalqty10078, 0) != ISNULL(@xxbad_scrapqty, 0)
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#本托还没有装满，请继续组托!#The pallet is not fully loaded yet, please continue stacking!', 11, 1);

                END;
                --更新箱标签表的所属托码
                UPDATE b
                SET --b.FromLoc = b.CurrentLoc,
                    --b.CurrentLoc = a.ToLoc,
                    --b.Status = 3,
                    --b.Lot = a.ToLot,
                    InboundUser = @xxbad_user,
                    b.PalletLable = @xxbad_kanban_id,
                    InboundTime = GETDATE()
                FROM Barcode_OperateCache a,
                     dbo.Barocde_BoxlLable b
                WHERE a.LableID = b.USN
                      AND a.AppID = @interfaceid
                      AND a.OpUser = @xxbad_user;
                --更新托标签的数量，打包人，装箱量
                UPDATE dbo.Barcode_PalletLable
                SET Qty = @totalqty10078,
                    BoxTime = GETDATE(),
                    BoxUser = @xxbad_user,
                    BoxNum = @totalbox
                WHERE USN = @xxbad_kanban_id;
                --打印托标签 
                DECLARE @ID INT =
                        (
                            SELECT TOP 1 ID FROM dbo.Barcode_PalletLable WHERE USN = @xxbad_kanban_id
                        );
                EXEC dbo.PrintPallteLable @ID; -- int
                EXEC dbo.PrintPallteLable @ID; -- int
                EXEC dbo.PrintPallteLable @ID; -- int
                EXEC dbo.PrintPallteLable @ID; -- int
                --清除缓存表
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                RAISERROR(N'Info_MESSAGE#组托完成!#Group creation completed!', 11, 1);

            END;
            ELSE IF @ScanData = 'Back'
            BEGIN
                --清除缓存表
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                --返回第一个dataset
                SELECT TOP 1
                       ToLoc xxbad_toloc,
                       PartNum xxbad_part,
                       FromLot xxbad_lot,
                       (
                           SELECT SUM(Qty)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_extension1,            --累积箱
                       (
                           SELECT SUM(Qty)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_rj_qty,                --累积量
                       ExtendedField2 xxbad_scrapqty, --包装量
                       SupplyCode xxbad_supplier,
                       ExtendedField1 xxbad_kanban_id
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                --返回第二个dataset
                SELECT *
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;

            END;
            ELSE
            BEGIN
                --处理扫描的条码
                SET @xxbad_rmks = '';
                --从标签中加载信息  并且判断标签状态
                SELECT @xxbad_ship_id = ShipSN,
                       @xxbad_id = USN,
                       @xxbad_part = PartNum,
                       @xxbad_desc = PartDescription,
                       @xxbad_qty = Qty,
                       @xxbad_lot = Lot,
                       @xxbad_supplier = CustomNum,
                       @InspectType = InspectType,
                       @InspectUser = InspectUser,
                       @InspectResult = InspectResult,
                       @xxbad_rmks = PalletLable,
                       @xxbad_fromloc = CurrentLoc
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id
                      AND Status IN ( 2, 3 );
                --标签不正确
                IF (ISNULL(@xxbad_part, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签或标签状态不正确!#Incorrect tag or tag status!', 11, 1);

                END;
                --标签不正确
                IF (ISNULL(@xxbad_rmks, '') <> '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不能重复组托!#Tags cannot be duplicated in the group!', 11, 1);

                END;
                --判断当前原材料是否被被人缓存了
                SELECT TOP 1
                       @cacheuser = OpUser
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND LableID = @xxbad_id;
                IF (ISNULL(@cacheuser, @xxbad_user) <> @xxbad_user)
                BEGIN
                    SET @ErrorMessage
                        = N'ERROR_MESSAGE#该箱码被用户' + @cacheuser + N'扫描，请提醒其操作!#The box code has been scanned by user ' + @cacheuser + N'. Please remind them to take action!';
                    RAISERROR(@ErrorMessage, 11, 1);

                END;

                --获取当前箱码关联的客户编码和零件号所对应的编码规则
                DECLARE @CustomBarcode10078 VARCHAR(50) = ''; --编码规则

                --取出包装量 客户名称，零件描述，客户的编码规则
                SELECT TOP 1
                       @CustomBarcode10078 = barcodeprefix,
                       @palletqty = allotpkg
                FROM barcode_custompartset
                WHERE partnum = @xxbad_part
                      AND customid = @xxbad_supplier;

                --如果托标签字段是空的，则生成一个新的托号
                IF ISNULL(@xxbad_kanban_id, '') = ''
                BEGIN

                    --如果客户编码规则没有维护
                    IF (ISNULL(@CustomBarcode10078, '') = '')
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#当前客户当前零件的编码规则没有维护，请先维护!#The coding rules for the current part of the current customer have not been maintained. Please maintain them first!', 11, 1);

                    END;
                    --生成托标签号临时表
                    CREATE TABLE #LableNumber10078
                    (
                        ft VARCHAR(20)
                    );

                    --生成一个新的托标签号
                    INSERT INTO #LableNumber10078
                    EXEC GetFGSeqenceNum @xxbad_supplier, @xxbad_part, 0;
                    SELECT @xxbad_kanban_id = ft
                    FROM #LableNumber10078;
                    --判断生成的托号 不为空且不能重复
                    IF (ISNULL(@xxbad_kanban_id, '') = '')
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#生成新的托号为空，请联系管理员!#The new tracking number is empty, please contact the administrator!', 11, 1);

                    END;
                    IF EXISTS
                    (
                        SELECT TOP 1
                               1
                        FROM dbo.Barcode_PalletLable
                        WHERE USN = @xxbad_kanban_id
                    )
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#生成新的托号重复，请联系管理员!#Duplicate new order number generated, please contact the administrator!', 11, 1);

                    END;
                    --插入一张新的箱标签
                    INSERT INTO Barcode_PalletLable
                    (
                        [USN],
                        [PartNum],
                        PartDescription,
                        Lot,
                        ProLine,
                        CurrentLoc,
                        [Qty],
                        [WoNum],
                        [Wo_DueDate],
                        [PkgQty],
                        Status,
                        CustomNum,
                        CustomName,
                        CreateTime,
                        Site,
                        ExtendFiled1,
                        ExtendFiled2,
                        InboundUser,
                        InboundTime,
                        CustomPartNum,
                        ShipTo,
                        DockLoaction,
                        CustomPO,
                        PurchaseOrder,
                        SupplyNum
                    )
                    SELECT @xxbad_kanban_id,
                           PartNum,
                           PartDescription,
                           Lot,
                           ProLine,
                           CurrentLoc,
                           0,
                           [WoNum],
                           [Wo_DueDate],
                           @palletqty,
                           Status,
                           CustomNum,
                           CustomName,
                           GETDATE(),
                           Site,
                           USN,
                           '成品箱码转化成托码',
                           InboundUser,
                           InboundTime,
                           CustomPartNum,
                           ShipTo,
                           DockLoaction,
                           CustomPO,
                           PurchaseOrder,
                           SupplyNum
                    FROM Barocde_BoxlLable
                    WHERE USN = @xxbad_id;
                --打印托标签
                END;
                --如果在动态高速缓存表不存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND LableID = @xxbad_id
                          AND OpUser = @xxbad_user
                )
                BEGIN

                    --判断和上一个标签是不是同一个零件号和客户编码  不能混装
                    IF EXISTS
                    (
                        SELECT TOP 1
                               1
                        FROM Barcode_OperateCache
                        WHERE AppID = @interfaceid
                              AND OpUser = @xxbad_user
                    )
                       AND NOT EXISTS
                    (
                        SELECT TOP 1
                               1
                        FROM Barcode_OperateCache
                        WHERE AppID = @interfaceid
                              AND OpUser = @xxbad_user
                              AND SupplyCode = @xxbad_supplier
                              AND PartNum = @xxbad_part
                              --AND FromLot = @xxbad_lot
                              AND CurrentLoc = @xxbad_fromloc
                    )
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#当前标签和上一个标签不是同一个零件号和客户编码，库位  不能混装!#The current label and the previous label do not have the same part number and customer code. The storage location cannot be mixed!', 11, 1);

                    END;
                    --判断 不能超出托包装量
                    IF @xxbad_scrapqty <> ''
                    BEGIN
                        IF CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_extension1, '0'))
                           + CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_qty, '0')) > CONVERT(
                                                                                           DECIMAL(18, 5),
                                                                                           ISNULL(@xxbad_scrapqty, '0')
                                                                                       )
                        BEGIN
                            RAISERROR(N'ERROR_MESSAGE#本托已经装满，请提交数据!#The bento box is full, please submit the data!', 11, 1);

                        END;
                    END;
                    --从标签中获取标签信息 插入动态高速缓存表
                    INSERT INTO [dbo].[Barcode_OperateCache]
                    (
                        id,
                        [AppID],
                        [OpUser],
                        [LableID],
                        [PartNum],
                        [PartDescrition],
                        [Qty],
                        ToLot,
                        [FromLoc],
                        PoNum,
                        PoLine,
                        [CurrentLoc],
                        [ToLoc],
                        [FromSite],
                        [ToSite],
                        [ScanTime],
                        ExtendedField1,
                        ExtendedField2,
                        SupplyCode,
                        FromLot
                    )
                    SELECT TOP 1
                           NEWID(),
                           @interfaceid,
                           @xxbad_user,
                           @xxbad_id,
                           PartNum,
                           PartDescription,
                           Qty,
                           Lot,
                           CurrentLoc,
                           PurchaseOrder,
                           PoLine,
                           CurrentLoc,
                           CurrentLoc,
                           Site,
                           @xxbad_site,
                           GETDATE(),
                           @xxbad_kanban_id,
                           @palletqty,
                           @xxbad_supplier,
                           Lot
                    FROM dbo.Barocde_BoxlLable
                    WHERE USN = @xxbad_id;
                END;
                ELSE
                BEGIN
                    DELETE [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND LableID = @xxbad_id
                          AND OpUser = @xxbad_user;
                END;
                --返回第一个dataset到前台
                SELECT TOP 1
                    --ToLoc xxbad_toloc,
                       PartNum xxbad_part,
                       '' xxbad_id,
                       SupplyCode xxbad_supplier,
                       FromLot xxbad_lot,
                       (
                           SELECT SUM(Qty)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_extension1,        --累积量
                       (
                           SELECT SUM(1)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_rj_qty,            --累积箱
                       @palletqty xxbad_scrapqty, --包装量
                       @xxbad_kanban_id xxbad_kanban_id,
                       CurrentLoc xxbad_loc
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                --返回第二个dataset到前台
                SELECT LableID,
                       PartNum,
                       PartDescrition
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
            END;

        END;
        IF @interfaceid IN ( 10078 ) --托标签上架
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断是否扫描了标签  
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#您没有扫描任何标签!#You have not scanned any tags!', 11, 1);

                END;
                --判断是否 导致负库存
                SELECT Site,
                       PartNum,
                       CurrentLoc,
                       Lot,
                       SUM(Qty) Qty
                INTO #Barocde_BoxlLable
                FROM Barocde_BoxlLable
                WHERE PalletLable IN
                      (
                          SELECT LableID
                          FROM Barcode_OperateCache
                          WHERE AppID = @interfaceid
                                AND OpUser = @xxbad_user
                      )
                      AND Status <> 7
                GROUP BY Site,
                         PartNum,
                         CurrentLoc,
                         Lot;
                DECLARE @Site NVARCHAR(500) = @xxbad_site;
                SELECT @Site = b.site
                FROM #Barocde_BoxlLable a
                    LEFT JOIN dbo.barocde_stock b
                        ON a.PartNum = b.partnum
                           AND a.CurrentLoc = b.loc
                           AND b.lot = a.Lot
                           AND b.site = a.Site
                           AND ISNULL(b.qty, 0) < a.Qty;

                IF ISNULL(@Site, '') <> ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#从库位没有足够的库存做此业务!#There is not enough stock in the location to perform this operation!', 11, 1);

                END;
                --更新托标签表的库位和状态
                UPDATE b
                SET b.FromLoc = b.CurrentLoc,
                    b.CurrentLoc = a.ToLoc,
                    b.Status = 3,
                    InboundUser = @xxbad_user,
                    InboundTime = GETDATE()
                FROM Barcode_OperateCache a,
                     dbo.Barcode_PalletLable b
                WHERE a.LableID = b.USN
                      AND a.AppID = @interfaceid
                      AND a.OpUser = @xxbad_user;

                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    BarcodeInterFaceID,
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @xxbad_domain,
                       @interfaceid,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       0,
                       b.PartNum,
                       dbo.GetQADloc(b.CurrentLoc),
                       dbo.GetQADloc(@xxbad_toloc),
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       SUM(b.Qty),
                       b.Lot,
                       b.Lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM Barcode_OperateCache a,
                     dbo.Barocde_BoxlLable b
                WHERE a.LableID = b.PalletLable
                      AND AppID = @interfaceid
                      AND OpUser = @xxbad_user
                      AND b.Status <> 7
                GROUP BY b.PartNum,
                         b.CurrentLoc,
                         b.Lot;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       b.USN,
                       @xxbad_user,
                       b.WoNum,
                       0,
                       b.PartNum,
                       b.CurrentLoc,
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       b.PalletLable,
                       @xxbad_id,
                       b.Qty,
                       b.Lot,
                       b.Lot,
                       @xxbad_fromref,
                       @xxbad_toref
                FROM Barcode_OperateCache a,
                     dbo.Barocde_BoxlLable b
                WHERE a.LableID = b.PalletLable
                      AND AppID = @interfaceid
                      AND OpUser = @xxbad_user
                      AND b.Status <> 7;
                --更新托标签的箱标签的库位，状态
                UPDATE dbo.Barocde_BoxlLable
                SET CurrentLoc = @xxbad_toloc,
                    Status = 3,
                    InboundUser = @xxbad_user,
                    InboundTime = GETDATE()
                WHERE PalletLable IN
                      (
                          SELECT LableID
                          FROM Barcode_OperateCache
                          WHERE AppID = @interfaceid
                                AND OpUser = @xxbad_user
                      )
                      AND Status <> 7;

                --清除缓存表
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                RAISERROR(N'Info_MESSAGE#上架完成!#Listing completed!', 11, 1);

            END;
            ELSE IF @ScanData = 'Back'
            BEGIN
                --清除缓存表
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                --如果缓存中 带不出库位，则自动推荐一个库位
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    SELECT TOP 1
                           @xxbad_toloc = xxlocation_loc
                    FROM dbo.Barcode_Location
                    WHERE LocArea IN ( 'FG-01' )
                          AND xxlocation_loc NOT IN
                              (
                                  SELECT loc FROM dbo.barocde_stock WHERE qty > 0
                              );
                    SELECT @xxbad_toloc xxbad_toloc;
                END;
                ELSE
                BEGIN
                    --返回第一个dataset
                    SELECT TOP 1
                           PartNum xxbad_part,
                           SupplyCode xxbad_supplier,
                           FromLot xxbad_lot,
                           ToLoc xxbad_toloc,
                           Qty xxbad_qty,
                           (
                               SELECT SUM(1)
                               FROM Barcode_OperateCache
                               WHERE AppID = @interfaceid
                                     AND OpUser = @xxbad_user
                           ) xxbad_scrapqty, --累积箱
                           LableID xxbad_kanban_id
                    FROM Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user;
                    --返回第二个dataset
                    SELECT *
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user;
                END;

            END;
            ELSE IF @ScanData = 'ToLoc'
            BEGIN
                --判断库位是否存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_Location
                    WHERE xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#库位不存在!#Location does not exist!', 11, 1);

                END;
                --返回第一个dateset 到前台
                SELECT @xxbad_toloc xxbad_toloc,
                       'xxbad_toloc' READONLY;
            END;
            ELSE
            BEGIN
                --从标签中加载信息  并且判断标签状态
                SELECT @xxbad_ship_id = ShipSN,
                       @xxbad_id = USN,
                       @xxbad_part = PartNum,
                       @xxbad_desc = PartDescription,
                       @xxbad_qty = Qty,
                       @xxbad_lot = Lot,
                       @xxbad_supplier = CustomNum,
                       @InspectType = InspectType,
                       @InspectUser = InspectUser,
                       @InspectResult = InspectResult,
                       @xxbad_fromloc = CurrentLoc
                FROM dbo.Barcode_PalletLable
                WHERE USN = @xxbad_kanban_id
                      AND (Status = 2);
                --标签不正确
                IF (ISNULL(@xxbad_part, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不正确!#Invalid tag!', 11, 1);

                END;
                --判断从库位不能为空
                IF (ISNULL(@xxbad_fromloc, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签库位不能为空!#The label location cannot be empty!', 11, 1);

                END;
                --不合格品不能上架
                --IF (
                --   (   ISNULL(@InspectResult, 0) = 0)
                --   AND ISNULL(@InspectType, 0) = 0
                --   )
                --BEGIN
                --    RAISERROR(
                --        N'ERROR_MESSAGE#不合格品不能上架!#Non-conforming products cannot be listed!',
                --        11,
                --        1
                --             );
                --    
                --END;

                --判断 到库位 是否在零件的配置的库区内
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_Location
                    WHERE LocArea IN
                          (
                              SELECT LocArea FROM Barcode_ItemLocArea WHERE ItemNum = @xxbad_part
                          )
                          AND xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前成品不能上架到此库区!#The current product cannot be placed in this storage area!', 11, 1);

                END;

                --判断当前零件的状态是否在QAD激活
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.pt_mstr
                    WHERE pt_part = @xxbad_part
                          AND pt_status = 'SOP'
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前零件未激活，请先到QAD激活!#The current part is not activated. Please activate it in QAD first!', 11, 1);

                END;
                --判断QAD中 从库位和到库位是否相同
                IF (dbo.GetQADloc(@xxbad_fromloc) = dbo.GetQADloc(@xxbad_toloc))
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#从库位和到库位的库区相同，不能生成上架队列!#The source and destination storage areas are the same, unable to generate the shelving queue!', 11, 1);

                END;
                --判断当前原材料是否被被人缓存了
                SELECT TOP 1
                       @cacheuser = OpUser
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND LableID = @xxbad_id;
                IF (ISNULL(@cacheuser, @xxbad_user) <> @xxbad_user)
                BEGIN
                    SET @ErrorMessage
                        = N'ERROR_MESSAGE#该箱码被用户' + @cacheuser + N'扫描，请提醒其操作!#The box code has been scanned by user ' + @cacheuser + N'. Please remind them to take action!';
                    RAISERROR(@ErrorMessage, 11, 1);

                END;
                --如果在动态高速缓存表不存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND LableID = @xxbad_id
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    --从标签中获取标签信息 插入动态高速缓存表
                    INSERT INTO [dbo].[Barcode_OperateCache]
                    (
                        [AppID],
                        [OpUser],
                        [LableID],
                        [PartNum],
                        [PartDescrition],
                        [Qty],
                        ToLot,
                        [FromLoc],
                        PoNum,
                        PoLine,
                        [CurrentLoc],
                        [ToLoc],
                        [FromSite],
                        [ToSite],
                        [ScanTime],
                        ExtendedField1,
                        ExtendedField2,
                        SupplyCode,
                        FromLot
                    )
                    SELECT TOP 1
                           @interfaceid,
                           @xxbad_user,
                           @xxbad_id,
                           PartNum,
                           PartDescription,
                           Qty,
                           Lot,
                           CurrentLoc,
                           PurchaseOrder,
                           PoLine,
                           CurrentLoc,
                           @xxbad_toloc,
                           Site,
                           @xxbad_site,
                           GETDATE(),
                           @xxbad_kanban_id,
                           @palletqty,
                           @xxbad_supplier,
                           Lot
                    FROM dbo.Barcode_PalletLable
                    WHERE USN = @xxbad_id;
                END;
                ELSE
                BEGIN
                    DELETE [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND LableID = @xxbad_id
                          AND OpUser = @xxbad_user;
                END;
                --返回第一个dataset到前台
                SELECT TOP 1
                       PartNum xxbad_part,
                       SupplyCode xxbad_supplier,
                       FromLot xxbad_lot,
                       '' xxbad_id,
                       Qty xxbad_qty,
                       (
                           SELECT SUM(1)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_scrapqty, --累积箱
                       LableID xxbad_kanban_id
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                --返回第二个dataset到前台
                SELECT LableID,
                       PartNum,
                       PartDescrition
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
            END;

        END;
        IF @interfaceid IN ( 10102 ) --托标签移库
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --判断是否扫描了标签  
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#您没有扫描任何标签!#You have not scanned any tags!', 11, 1);

                END;

                --更新托标签表的库位
                UPDATE b
                SET b.FromLoc = b.CurrentLoc,
                    b.CurrentLoc = a.ToLoc
                FROM Barcode_OperateCache a,
                     dbo.Barcode_PalletLable b
                WHERE a.LableID = b.USN
                      AND a.AppID = @interfaceid
                      AND a.OpUser = @xxbad_user;

                --插入条码主队列
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    BarcodeInterFaceID,
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @xxbad_domain,
                       @interfaceid,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       '',
                       0,
                       b.PartNum,
                       dbo.GetQADloc(b.CurrentLoc),
                       dbo.GetQADloc(@xxbad_toloc),
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       @xxbad_ship_id,
                       @xxbad_id,
                       SUM(b.Qty),
                       b.Lot,
                       b.Lot,
                       @xxbad_ref,
                       @xxbad_ref
                FROM Barcode_OperateCache a,
                     dbo.Barocde_BoxlLable b
                WHERE a.LableID = b.PalletLable
                      AND AppID = @interfaceid
                      AND OpUser = @xxbad_user
                GROUP BY b.PartNum,
                         b.CurrentLoc,
                         b.Lot;

                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'IC_TR',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       b.USN,
                       @xxbad_user,
                       b.WoNum,
                       0,
                       b.PartNum,
                       b.CurrentLoc,
                       @xxbad_toloc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       b.PalletLable,
                       @xxbad_id,
                       b.Qty,
                       b.Lot,
                       b.Lot,
                       @xxbad_fromref,
                       @xxbad_toref
                FROM Barcode_OperateCache a,
                     dbo.Barocde_BoxlLable b
                WHERE a.LableID = b.PalletLable
                      AND AppID = @interfaceid
                      AND OpUser = @xxbad_user;

                --更新托标签的箱标签的库位，状态
                UPDATE dbo.Barocde_BoxlLable
                SET CurrentLoc = @xxbad_toloc
                WHERE PalletLable IN
                      (
                          SELECT LableID
                          FROM Barcode_OperateCache
                          WHERE AppID = @interfaceid
                                AND OpUser = @xxbad_user
                      );

                --清除缓存表
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                RAISERROR(N'Info_MESSAGE#移库完成!#Relocation completed!', 11, 1);

            END;
            ELSE IF @ScanData = 'Back'
            BEGIN
                --清除缓存表
                DELETE FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                --如果缓存中 带不出库位，则自动推荐一个库位
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    SELECT TOP 1
                           @xxbad_toloc = xxlocation_loc
                    FROM dbo.Barcode_Location
                    WHERE LocArea IN ( 'FG-01' )
                          AND xxlocation_loc NOT IN
                              (
                                  SELECT loc FROM dbo.barocde_stock WHERE qty > 0
                              );
                    SELECT @xxbad_toloc xxbad_toloc;
                END;
                ELSE
                BEGIN
                    --返回第一个dataset
                    SELECT TOP 1
                           PartNum xxbad_part,
                           SupplyCode xxbad_supplier,
                           FromLot xxbad_lot,
                           ToLoc xxbad_toloc,
                           Qty xxbad_qty,
                           (
                               SELECT SUM(1)
                               FROM Barcode_OperateCache
                               WHERE AppID = @interfaceid
                                     AND OpUser = @xxbad_user
                           ) xxbad_scrapqty, --累积箱
                           LableID xxbad_kanban_id
                    FROM Barcode_OperateCache
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user;
                    --返回第二个dataset
                    SELECT *
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND OpUser = @xxbad_user;
                END;

            END;
            ELSE IF @ScanData = 'xxbad_toloc'
            BEGIN
                --判断库位是否存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_Location
                    WHERE xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#库位不存在!#Location does not exist!', 11, 1);

                END;
                --返回第一个dateset 到前台
                SELECT @xxbad_toloc xxbad_toloc,
                       'xxbad_toloc' READONLY;
            END;
            ELSE
            BEGIN
                --从标签中加载信息  并且判断标签状态
                SELECT @xxbad_ship_id = ShipSN,
                       @xxbad_id = USN,
                       @xxbad_part = PartNum,
                       @xxbad_desc = PartDescription,
                       @xxbad_qty = Qty,
                       @xxbad_lot = Lot,
                       @xxbad_supplier = CustomNum,
                       @InspectType = InspectType,
                       @InspectUser = InspectUser,
                       @InspectResult = InspectResult,
                       @xxbad_fromloc = CurrentLoc
                FROM dbo.Barcode_PalletLable
                WHERE USN = @xxbad_kanban_id
                      AND (Status = 3);
                --标签不正确
                IF (ISNULL(@xxbad_part, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不正确!#Invalid tag!', 11, 1);

                END;
                --判断从库位不能为空
                IF (ISNULL(@xxbad_fromloc, '') = '')
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签库位不能为空!#The label location cannot be empty!', 11, 1);

                END;
                --不合格品不能上架
                --IF (
                --   (   ISNULL(@InspectResult, 0) = 0)
                --   AND ISNULL(@InspectType, 0) = 0
                --   )
                --BEGIN
                --    RAISERROR(
                --        N'ERROR_MESSAGE#不合格品不能上架!#Non-conforming products cannot be listed!',
                --        11,
                --        1
                --             );
                --    
                --END;

                --判断 到库位 是否在零件的配置的库区内
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM Barcode_Location
                    WHERE LocArea IN
                          (
                              SELECT LocArea FROM Barcode_ItemLocArea WHERE ItemNum = @xxbad_part
                          )
                          AND xxlocation_loc = @xxbad_toloc
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前成品不能移库到此库区!#The current finished product cannot be moved to this storage area!', 11, 1);

                END;

                --判断当前零件的状态是否在QAD激活
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.pt_mstr
                    WHERE pt_part = @xxbad_part
                          AND pt_status = 'SOP'
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前零件未激活，请先到QAD激活!#The current part is not activated. Please activate it in QAD first!', 11, 1);

                END;

                --判断当前原材料是否被被人缓存了
                SELECT TOP 1
                       @cacheuser = OpUser
                FROM [Barcode_OperateCache]
                WHERE AppID = @interfaceid
                      AND LableID = @xxbad_id;
                IF (ISNULL(@cacheuser, @xxbad_user) <> @xxbad_user)
                BEGIN
                    SET @ErrorMessage
                        = N'ERROR_MESSAGE#该箱码被用户' + @cacheuser + N'扫描，请提醒其操作!#The box code has been scanned by user ' + @cacheuser + N'. Please remind them to take action!';
                    RAISERROR(@ErrorMessage, 11, 1);

                END;
                --如果在动态高速缓存表不存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND LableID = @xxbad_id
                          AND OpUser = @xxbad_user
                )
                BEGIN
                    --从标签中获取标签信息 插入动态高速缓存表
                    INSERT INTO [dbo].[Barcode_OperateCache]
                    (
                        [AppID],
                        [OpUser],
                        [LableID],
                        [PartNum],
                        [PartDescrition],
                        [Qty],
                        ToLot,
                        [FromLoc],
                        PoNum,
                        PoLine,
                        [CurrentLoc],
                        [ToLoc],
                        [FromSite],
                        [ToSite],
                        [ScanTime],
                        ExtendedField1,
                        ExtendedField2,
                        SupplyCode,
                        FromLot
                    )
                    SELECT TOP 1
                           @interfaceid,
                           @xxbad_user,
                           @xxbad_id,
                           PartNum,
                           PartDescription,
                           Qty,
                           Lot,
                           CurrentLoc,
                           PurchaseOrder,
                           PoLine,
                           CurrentLoc,
                           @xxbad_toloc,
                           Site,
                           @xxbad_site,
                           GETDATE(),
                           @xxbad_kanban_id,
                           @palletqty,
                           @xxbad_supplier,
                           Lot
                    FROM dbo.Barcode_PalletLable
                    WHERE USN = @xxbad_id;
                END;
                ELSE
                BEGIN
                    DELETE [Barcode_OperateCache]
                    WHERE AppID = @interfaceid
                          AND LableID = @xxbad_id
                          AND OpUser = @xxbad_user;
                END;
                --返回第一个dataset到前台
                SELECT TOP 1
                       PartNum xxbad_part,
                       SupplyCode xxbad_supplier,
                       FromLot xxbad_lot,
                       '' xxbad_id,
                       Qty xxbad_qty,
                       (
                           SELECT SUM(1)
                           FROM Barcode_OperateCache
                           WHERE AppID = @interfaceid
                                 AND OpUser = @xxbad_user
                       ) xxbad_scrapqty, --累积箱
                       LableID xxbad_kanban_id
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
                --返回第二个dataset到前台
                SELECT LableID,
                       PartNum,
                       PartDescrition
                FROM Barcode_OperateCache
                WHERE AppID = @interfaceid
                      AND OpUser = @xxbad_user;
            END;

        END;
        IF @interfaceid IN ( 10080 ) --出口件托标签解除
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --更新托标签状态，数量
                UPDATE dbo.Barcode_PalletLable
                SET Qty = 0,
                    BoxNum = 0,
                    Status = 7,
                    InboundUser = '',
                    DestroyTime = GETDATE(),
                    DestroyUser = @xxbad_user,
                    DestroyMemo = '托标签解除',
                    InboundTime = NULL
                WHERE USN = @xxbad_id;
                --更新箱标签的托号
                UPDATE dbo.Barocde_BoxlLable
                SET PalletLable = '',
                    Status = 2
                WHERE PalletLable = @xxbad_id;
                --抛出箱码@newlabel
                SET @ErrorMessage = N'Info_MESSAGE#拆托完成!#Dismantling completed!';
                RAISERROR(@ErrorMessage, 11, 1);

            END;

            ELSE
            BEGIN
                --判断托标签是否存在
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.Barcode_PalletLable
                    WHERE USN = @xxbad_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#托标签不正确!#Incorrect tag!', 11, 1);

                END;
                --获取成品标签中的信息返回第一个dataset到前台
                SELECT USN xxbad_id,
                       PartNum xxbad_part,
                       PartDescription xxbad_desc,
                       Qty xxbad_qty,
                       CustomNum xxbad_supplier,
                       BoxNum xxbad_rj_qty
                FROM dbo.Barcode_PalletLable
                WHERE USN = @xxbad_id;

                --返回第二个dataset到前台
                SELECT USN,
                       Qty
                FROM dbo.Barocde_BoxlLable
                WHERE PalletLable = @xxbad_id;
            END;

        END;
        IF @interfaceid IN ( 10084 ) --原材料反向回冲 
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                RAISERROR(N'ERROR_MESSAGE#功能已经废弃，重新做!#The feature has been deprecated, please redo it!', 11, 1);

                --判断数量 是否为空
                IF CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_qty, 0)) = 0
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#回冲数量不能为空!#The recharge quantity cannot be empty!', 11, 1);

                END;
                --限制退还数量不能 大于消耗数量

                --如果是扣料 需要判断线边库存是否足够
                IF CONVERT(DECIMAL(18, 5), ISNULL(@xxbad_qty, 0)) < 0
                BEGIN
                    DECLARE @stockqty10084 DECIMAL;
                    SELECT @stockqty10084 = SUM(qty)
                    FROM dbo.barocde_stock b
                    WHERE b.partnum = @xxbad_supplier_part
                          AND b.lot = @xxbad_lot
                          AND b.loc = @xxbad_loc;
                    IF ISNULL(@stockqty10084, 0) < ABS(ISNULL(@xxbad_qty, 0))
                    BEGIN
                        RAISERROR(N'ERROR_MESSAGE#当前原材料零件当前批次线边库存不足，请核查!#The current batch of raw material parts has insufficient line-side inventory. Please check!', 11, 1);

                    END;
                END;
                --插入库存表
                INSERT dbo.barocde_stock
                (
                    site,
                    loc,
                    partnum,
                    lot,
                    qty,
                    modifyuser,
                    modifytime,
                    queueid,
                    ref
                )
                SELECT @xxbad_site,
                       @xxbad_loc,
                       @xxbad_supplier_part,
                       @xxbad_lot,
                       @xxbad_qty,
                       @xxbad_user,
                       GETDATE(),
                       0,
                       @xxbad_id;
                --插入QAD 回冲队列 数量是负数  以后再做
                --插入主队列  上报QAD
                INSERT INTO [dbo].[xxinbxml_mstr]
                (
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    BarcodeInterFaceID,
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    [xxinbxml_extusr],
                    xxinbxml_extid,
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_op,
                    xxinbxml_Proline
                )
                SELECT @xxbad_domain,
                       'PQ_WO_BKFL',
                       @interfaceid,
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       @xxbad_user,
                       USN,
                       '',
                       0,
                       PartNum,
                       '',
                       ISNULL(dbo.GetQADloc(CurrentLoc), ''),
                       @xxbad_lot,
                       @xxbad_lot,
                       ISNULL(Site, @xxbad_site),
                       ISNULL(Site, @xxbad_site),
                       '',
                       '',
                       Qty,
                       WorkOp,
                       ProLine
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;
                --标签插入子队列 用于计算库存
                INSERT INTO [dbo].[xxinbxml_Det]
                (
                    xxinbxml_Mstid,
                    BarcodeInterFaceID,
                    [xxinbxml_domain],
                    [xxinbxml_appid],
                    [xxinbxml_status],
                    [xxinbxml_crtdate],
                    [xxinbxml_cimdate],
                    [xxinbxml_type],
                    xxinbxml_extid,
                    [xxinbxml_extusr],
                    [xxinbxml_ord],
                    [xxinbxml_line],
                    [xxinbxml_part],
                    [xxinbxml_locfrm],
                    [xxinbxml_locto],
                    [xxinbxml_sitefrm],
                    [xxinbxml_siteto],
                    [xxinbxml_pallet],
                    [xxinbxml_box],
                    [xxinbxml_qty_chg],
                    xxinbxml_lotfrm,
                    xxinbxml_lotto,
                    xxinbxml_reffrm,
                    xxinbxml_refto
                )
                SELECT @@IDENTITY,
                       @interfaceid,
                       @xxbad_domain,
                       'PQ_WO_BKFL',
                       0,
                       GETDATE(),
                       GETDATE(),
                       'CIM',
                       USN,
                       @xxbad_user,
                       '',
                       '',
                       PartNum,
                       CurrentLoc,
                       CurrentLoc,
                       @xxbad_fromsite,
                       @xxbad_tosite,
                       '',
                       @xxbad_id,
                       Qty,
                       @xxbad_lot,
                       @xxbad_lot,
                       @xxbad_ref,
                       ''
                FROM dbo.Barocde_BoxlLable
                WHERE USN = @xxbad_id;

                --更新标签的状态,批次 和 回冲信息
                UPDATE dbo.Barocde_BoxlLable
                SET Status = 7,
                    DestroyTime = GETDATE(),
                    DestroyUser = @xxbad_user,
                    DestroyMemo = '反向回冲注销'
                WHERE USN = @xxbad_id;
                --插入QAD 回冲事务表
                INSERT INTO [dbo].QADbackflushDetail
                (
                    [FGlable],
                    [FGpart],
                    [FGqty],
                    [RMpart],
                    [CostQty],
                    [Loc],
                    Lot,
                    [WoNum],
                    [InsertUser],
                    [InsertTime]
                )
                SELECT FGlable,
                       FGpart,
                       FGqty,
                       RMpart,
                       -CONVERT(DECIMAL(18, 5), @xxbad_qty),
                       Loc,
                       @xxbad_lot,
                       WoNum,
                       @xxbad_user,
                       GETDATE()
                FROM dbo.QADbackflushDetail
                WHERE FGlable = @xxbad_id
                      AND RMpart = @xxbad_supplier_part;
                RAISERROR(N'ERROR_MESSAGE#回冲成功!#Reversal successful!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 1;
                SELECT 1;

            END;
            ELSE IF @ScanData = 'ComboBox'
            BEGIN
                --返回第一个dataset 到前台 95130001 EC28BBE010P1
                SELECT TOP 1
                       FGlable xxbad_id,
                       WoNum xxbad_woid,
                       FGpart xxbad_part,
                       Loc xxbad_loc,
                       (
                           SELECT TOP 1
                                  pt_desc1
                           FROM dbo.pt_mstr
                           WHERE pt_part = @xxbad_supplier_part
                       ) xxbad_desc,
                       'xxbad_qty,xxbad_lot' READONLY,
                       (
                           SELECT TOP 1
                                  qty
                           FROM dbo.barocde_stock
                           WHERE partnum = @xxbad_supplier_part
                                 AND lot = a.lot
                                 AND loc = a.loc
                       ) xxbad_scrapqty,
                       Lot xxbad_lot
                FROM dbo.QADbackflushDetail a
                WHERE FGlable = @xxbad_id
                      AND RMpart = @xxbad_supplier_part;
                SELECT 1;

            END;
            ELSE --认为扫描的是成品条码
            BEGIN
                SET @xxbad_id = @ScanData;

                --判断箱标签是否合法
                IF NOT EXISTS
                (
                    SELECT TOP 1
                           1
                    FROM dbo.QADbackflushDetail
                    WHERE FGlable = @xxbad_id
                )
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#当前箱码没有回冲记录!#No backflush record for the current box code!', 11, 1);

                END;

                --返回第一个dataset 到前台 95130001 EC28BBE010P1
                SELECT TOP 1
                       FGlable xxbad_id,
                       WoNum xxbad_woid,
                       FGpart xxbad_part,
                       Loc xxbad_loc,
                       'xxbad_qty,xxbad_lot' READONLY,
                       (
                           SELECT RMpart text,
                                  RMpart value
                           FROM QADbackflushDetail
                           WHERE FGlable = @xxbad_id
                           FOR JSON PATH
                       ) xxbad_supplier_part
                FROM dbo.QADbackflushDetail
                WHERE FGlable = @xxbad_id;
            END;

        END;
        IF @interfaceid IN ( 10090 ) --外部标签绑定
        BEGIN
            --先处理命令  然后在处理数据
            IF @ScanData = 'Submit'
            BEGIN
                --再次判断提交的数据是否合法 
                IF ISNULL(@xxbad_id, '') = ''
                   OR ISNULL(@xxbad_extension1, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#请扫描标签 !#Please scan the label!', 11, 1);

                END;
                --更新托标签的 外部标签资源
                UPDATE dbo.Barcode_PalletLable
                SET ExtendFiled3 = @xxbad_extension1
                WHERE USN = @xxbad_id;

                RAISERROR(N'Info_MESSAGE#绑定成功!#Binding successful!', 11, 1);

            END;
            ELSE IF @ScanData = 'Cache'
            BEGIN
                SELECT 'xxbad_supplier,xxbad_qty' READONLY,
                       'Inspect' xxbad_toloc;

            END;

            ELSE IF @ScanData = 'xxbad_extension1'
            BEGIN
                SELECT 1;
            END;
            ELSE
            BEGIN

                --默认第一次扫描是标签 
                SELECT @xxbad_id = USN,
                       @xxbad_part = PartNum,
                       @xxbad_desc = PartDescription,
                       @xxbad_qty = Qty,
                       @xxbad_loc = CurrentLoc,
                       @xxbad_lot = Lot,
                       @xxbad_supplier = CustomNum,
                       @xxbad_extension2 = CustomName
                FROM dbo.Barcode_PalletLable
                WHERE USN = @xxbad_id
                      AND Status = 3;

                --判断标签是否合法
                IF ISNULL(@xxbad_part, '') = ''
                BEGIN
                    RAISERROR(N'ERROR_MESSAGE#标签不合法!#Invalid tag!', 11, 1);

                END;
                --返回第一个dataset 到前台
                SELECT @xxbad_id xxbad_id,
                       @xxbad_part xxbad_part,
                       @xxbad_qty xxbad_qty,
                       @xxbad_loc xxbad_loc,
                       @xxbad_desc xxbad_desc,
                       @xxbad_lot xxbad_lot,
                       @xxbad_supplier xxbad_supplier,
                       @xxbad_extension2 xxbad_extension2;
            END;
        END;
        --指定接口 不使用事务
        --IF @interfaceid NOT IN ( 10072 )
        --BEGIN
        IF XACT_STATE() = -1
        BEGIN
            PRINT 'hi  我回滚了';
            ROLLBACK TRAN; --回滚事务
        END;
        ELSE
        BEGIN
            PRINT 'hi  我提交了';
            COMMIT TRAN; --提交事务
        END;
    --END;

    END TRY
    BEGIN CATCH

        SELECT @ErrorMessage = ERROR_MESSAGE(),
               @ErrorSeverity = ERROR_SEVERITY(),
               @ErrorState = ERROR_STATE();

        IF XACT_STATE() = -1
        BEGIN
            PRINT 'hi  我回滚了';
            ROLLBACK TRAN; --回滚事务
        END;
        --判断有事务  如果不是自定义异常  回滚事务
        IF @@TRANCOUNT > 0
           AND @ErrorSeverity <> 11
        BEGIN
            PRINT 'hi  我回滚了';
            ROLLBACK TRAN; --
        END;
        --判断有事务 且是自定义异常 则提交事务
        IF @@TRANCOUNT > 0
           AND @ErrorSeverity = 11
        BEGIN
            PRINT 'hi  我提交了';
            COMMIT TRAN;
        END;
        --如果是系统异常 转成自定义异常传递给前台
        IF CHARINDEX('#', @ErrorMessage) <= 0
        BEGIN
            SET @ErrorMessage = N'ERROR_MESSAGE#' + @ErrorMessage + N'#' + @ErrorMessage + N'';
            INSERT INTO sys_log
            (
                [id],
                [log_type],
                [log_content],
                [operate_type],
                [userid],
                [username],
                [ip],
                [method],
                [request_url],
                [request_param],
                [request_type],
                [cost_time],
                [create_by],
                [create_time],
                [update_by],
                [update_time]
            )
            VALUES
            (NEWID(), @interfaceid, @ErrorMessage, 1, N'admin', N'管理员', @xxbad_id, @ScanData, NULL, N'', NULL, 368,
             NULL, GETDATE(), NULL, NULL);
        END;
        RAISERROR(   @ErrorMessage,  -- Message text.
                     @ErrorSeverity, -- Severity.
                     @ErrorState     -- State.
                 );
    END CATCH;
END;