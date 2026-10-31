REPORT z_sales_order_reporting_suite.

*-----------------------------------------------------------------------
* Sales Order Reporting Suite
* Classic ABAP / SAP S/4HANA 2023 (assumed)
* Purpose: Display open sales orders and drill down to item details.
*-----------------------------------------------------------------------

TABLES: vbak.

CONSTANTS:
  gc_completed_status TYPE vbak-gbstk VALUE 'C',
  gc_activity_display TYPE c LENGTH 2 VALUE '03'.

SELECT-OPTIONS:
  s_erdat FOR vbak-erdat,
  s_kunnr FOR vbak-kunnr.

PARAMETERS:
  p_vkorg TYPE vbak-vkorg OBLIGATORY.

TYPES:
  BEGIN OF ty_order,
    vbeln TYPE vbak-vbeln,
    erdat TYPE vbak-erdat,
    vkorg TYPE vbak-vkorg,
    kunnr TYPE vbak-kunnr,
    name1 TYPE kna1-name1,
    auart TYPE vbak-auart,
    gbstk TYPE vbak-gbstk,
    netwr TYPE vbak-netwr,
    waerk TYPE vbak-waerk,
  END OF ty_order,
  tt_orders TYPE STANDARD TABLE OF ty_order WITH EMPTY KEY,

  BEGIN OF ty_item,
    vbeln  TYPE vbap-vbeln,
    posnr  TYPE vbap-posnr,
    matnr  TYPE vbap-matnr,
    arktx  TYPE vbap-arktx,
    kwmeng TYPE vbap-kwmeng,
    vrkme  TYPE vbap-vrkme,
    netwr  TYPE vbap-netwr,
  END OF ty_item,
  tt_items TYPE STANDARD TABLE OF ty_item WITH EMPTY KEY.

CLASS lcl_order_logic DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS is_open
      IMPORTING iv_status TYPE vbak-gbstk
      RETURNING VALUE(rv_open) TYPE abap_bool.
ENDCLASS.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS run.
  PRIVATE SECTION.
    DATA mt_orders TYPE tt_orders.
    METHODS:
      check_authority,
      read_orders,
      display_orders,
      display_items IMPORTING iv_vbeln TYPE vbak-vbeln,
      on_double_click
        FOR EVENT double_click OF cl_salv_events_table
        IMPORTING row column.
ENDCLASS.

CLASS lcl_order_logic IMPLEMENTATION.
  METHOD is_open.
    "Overall processing status C means completed; A/B remain open/in process.
    rv_open = xsdbool( iv_status <> gc_completed_status ).
  ENDMETHOD.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    check_authority( ).
    read_orders( ).

    IF mt_orders IS INITIAL.
      MESSAGE 'No open sales orders found for the selection.' TYPE 'S'
        DISPLAY LIKE 'I'.
      RETURN.
    ENDIF.

    display_orders( ).
  ENDMETHOD.

  METHOD check_authority.
    "Read-only sales-order reporting: check display authorization for sales org.
    AUTHORITY-CHECK OBJECT 'V_VBAK_VKO'
      ID 'VKORG' FIELD p_vkorg
      ID 'ACTVT' FIELD gc_activity_display.

    IF sy-subrc <> 0.
      MESSAGE 'You are not authorized to display sales orders for this sales organization.'
        TYPE 'E'.
    ENDIF.
  ENDMETHOD.

  METHOD read_orders.
    "Join customer master once in SQL; avoids SELECT inside a processing loop.
    SELECT h~vbeln,
           h~erdat,
           h~vkorg,
           h~kunnr,
           c~name1,
           h~auart,
           h~gbstk,
           h~netwr,
           h~waerk
      FROM vbak AS h
      INNER JOIN kna1 AS c
        ON c~kunnr = h~kunnr
      WHERE h~vkorg = @p_vkorg
        AND h~erdat IN @s_erdat
        AND h~kunnr IN @s_kunnr
        AND h~gbstk <> @gc_completed_status
      ORDER BY h~vbeln
      INTO TABLE @mt_orders.
  ENDMETHOD.

  METHOD display_orders.
    DATA lo_alv TYPE REF TO cl_salv_table.
    DATA lo_events TYPE REF TO cl_salv_events_table.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = lo_alv
          CHANGING  t_table      = mt_orders ).

        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->get_columns( )->set_optimize( abap_true ).

        lo_events = lo_alv->get_event( ).
        SET HANDLER me->on_double_click FOR lo_events.

        "Double-click a sales order row to display its item list.
        lo_alv->display( ).

      CATCH cx_salv_msg INTO DATA(lx_salv).
        MESSAGE lx_salv->get_text( ) TYPE 'E'.
    ENDTRY.
  ENDMETHOD.

  METHOD on_double_click.
    READ TABLE mt_orders INDEX row INTO DATA(ls_order).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    display_items( ls_order-vbeln ).
  ENDMETHOD.

  METHOD display_items.
    DATA lt_items TYPE tt_items.
    DATA lo_alv TYPE REF TO cl_salv_table.

    "Fetch only the selected order's items; no SELECT is executed in a loop.
    SELECT vbeln,
           posnr,
           matnr,
           arktx,
           kwmeng,
           vrkme,
           netwr
      FROM vbap
      WHERE vbeln = @iv_vbeln
      ORDER BY posnr
      INTO TABLE @lt_items.

    IF lt_items IS INITIAL.
      MESSAGE 'No items found for the selected sales order.' TYPE 'S'
        DISPLAY LIKE 'I'.
      RETURN.
    ENDIF.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = lo_alv
          CHANGING  t_table      = lt_items ).

        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->get_columns( )->set_optimize( abap_true ).
        lo_alv->display( ).

      CATCH cx_salv_msg INTO DATA(lx_salv).
        MESSAGE lx_salv->get_text( ) TYPE 'E'.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  NEW lcl_app( )->run( ).

*-----------------------------------------------------------------------
* ABAP Unit tests for the isolated business rule.
*-----------------------------------------------------------------------
CLASS ltc_order_logic DEFINITION FINAL
  FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS:
      status_a_is_open FOR TESTING,
      status_b_is_open FOR TESTING,
      status_c_is_completed FOR TESTING.
ENDCLASS.

CLASS ltc_order_logic IMPLEMENTATION.
  METHOD status_a_is_open.
    cl_abap_unit_assert=>assert_equals(
      exp = abap_true
      act = lcl_order_logic=>is_open( 'A' ) ).
  ENDMETHOD.

  METHOD status_b_is_open.
    cl_abap_unit_assert=>assert_equals(
      exp = abap_true
      act = lcl_order_logic=>is_open( 'B' ) ).
  ENDMETHOD.

  METHOD status_c_is_completed.
    cl_abap_unit_assert=>assert_equals(
      exp = abap_false
      act = lcl_order_logic=>is_open( 'C' ) ).
  ENDMETHOD.
ENDCLASS.
