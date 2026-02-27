---
title: Excel 2024 Power Query 实战：自动获取并处理电子证照统计数据
subtitle: 告别 VBA，用 Power Query 轻松搞定 API 数据抓取与清洗
date: 2025-12-17T00:00:00+08:00
categories:
  - 工作分享/电子证照
tags:
  - Excel
  - Power Query
  - 电子证照
  - 数据处理
---

# Excel 2024 Power Query 实战：自动获取并处理电子证照统计数据

> 在日常工作中，我们经常需要从接口获取数据并整理成报表。本文将分享如何使用 Excel 2024 的 Power Query 功能，通过配置 API 接口，自动抓取电子证照的汇聚量、签章率等数据，并进行自动清洗和汇总，彻底告别繁琐的手动复制粘贴和复杂的 VBA 代码。

## 📅 需求背景

我们需要统计各区划的电子证照数据，包括以下核心指标：
*   **区划名称**
*   **证照类型汇聚数**
*   **录入量**
*   **已签章**
*   **未签章数**
*   **签章率**

数据源是一个 API 接口，返回的是 JSON 格式的数据。

## 🛠️ 工具选择

虽然 VBA 也可以实现网络请求和 JSON 解析，但在 **Microsoft Office 专业增强版 2024** 中，最推荐且最稳健的方法是使用内置的 **Power Query (获取和转换数据)** 功能。

**为什么选择 Power Query？**
1.  **原生支持 JSON**：无需像 VBA 那样引入第三方库即可轻松解析多层嵌套的 JSON 数据。
2.  **配置简单**：通过可视化界面或简单的脚本即可完成 POST 请求配置。
3.  **维护方便**：代码清晰，逻辑直观，且支持一键刷新。
4.  **兼容性好**：Excel 2024 对 Power Query 的支持非常完美。

## 🚀 实操步骤

以下是详细的操作指南：

### 第一步：打开 Power Query 空白查询

1.  打开 Excel。
2.  点击顶部菜单栏的 **【数据】 (Data)** 选项卡。
3.  点击左侧的 **【获取数据】 (Get Data)** -> **【来自其他源】** -> **【空白查询】 (Blank Query)**。
4.  此时会弹出一个“Power Query 编辑器”窗口。

### 第二步：输入接口脚本 (高级编辑器)

Power Query 的 `Web.Contents` 函数默认是用 GET 方法。为了让它变成 POST，我们需要在请求中添加一个 `Content` 参数。

1.  在 Power Query 编辑器中，点击顶部菜单的 **【高级编辑器】 (Advanced Editor)** 按钮。
2.  **清空** 里面的所有代码。
3.  **复制并粘贴** 以下代码：

```powerquery
let
    // 1. 定义接口地址
    Url = "http://59.196.23.204/license/main/api/getAreaDeptTypeStatisByBigPage?areaCode=150900",
    
    // 2. 发送 POST 请求 (通过 Content 字段强制识别为 POST)
    Source = Json.Document(Web.Contents(Url, [Content=Text.ToBinary("")])),
    
    // 3. 取出 data 下的 list 节点
    List = Source[data][list],
    
    // 4. 将 List 转为 Table
    TableFromList = Table.FromList(List, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    
    // 5. 展开记录字段，并重命名为中文表头
    Expanded = Table.ExpandRecordColumn(TableFromList, "Column1", 
        {"AREA_NAME", "LICENSE_REAL_DTLTYPE", "INPUT", "SIGNED", "SIGN_RATIO"}, 
        {"区划名称", "证照类型汇聚数", "录入量", "已签章", "签章率"}),
    
    // 6. 添加自定义列：未签章数 = 录入量 - 已签章
    WithUnsigned = Table.AddColumn(Expanded, "未签章数", each [录入量] - [已签章], Int64.Type),
    
    // 7. 特殊逻辑处理：合并“乌兰察布市”和“市直部门”为“市本级”
    // 提取行
    UlanRow = Table.SelectRows(WithUnsigned, each [区划名称] = "乌兰察布市"),
    CityRow = Table.SelectRows(WithUnsigned, each [区划名称] = "市直部门"),
    
    // 计算汇总值 (List.Sum 自动处理 null)
    Sum录入量 = List.Sum(UlanRow[录入量]) + List.Sum(CityRow[录入量]),
    Sum已签章 = List.Sum(UlanRow[已签章]) + List.Sum(CityRow[已签章]),
    Sum未签章数 = Sum录入量 - Sum已签章,
    Sum证照类型汇聚数 = List.Sum(UlanRow[证照类型汇聚数]) + List.Sum(CityRow[证照类型汇聚数]),
    
    // 计算签章率 (保留两位小数)
    Sum签章率 = if Sum录入量 = 0 then "0.00%" 
                else Text.From(Number.Round(100 * Sum已签章 / Sum录入量, 2)) & "%",
    
    // 创建“市本级”汇总行
    SummaryRow = #table(
        {"区划名称", "证照类型汇聚数", "录入量", "已签章", "未签章数", "签章率"},
        {{"市本级", Sum证照类型汇聚数, Sum录入量, Sum已签章, Sum未签章数, Sum签章率}}
    ),
    
    // 8. 排除原始的“乌兰察布市”和“市直部门”行
    FilteredTable = Table.SelectRows(WithUnsigned, each [区划名称] <> "乌兰察布市" and [区划名称] <> "市直部门"),
    
    // 9. 将“市本级”置顶，拼接剩余数据
    Combined = Table.Combine({SummaryRow, FilteredTable}),
    
    // 10. 最终整理列顺序
    FinalTable = Table.ReorderColumns(Combined, {"区划名称", "证照类型汇聚数", "录入量", "已签章", "未签章数", "签章率"})

in
    FinalTable
```

4.  点击 **【完成】 (Done)**。

### 第三步：输出到 Excel 表格

1.  你现在应该在编辑器中间看到了预览的数据表格，包含了我们计算好的“市本级”以及其他区划的数据。
2.  点击左上角的 **【关闭并上载】 (Close & Load)**。
3.  数据就会自动填充到 Excel 的新工作表中了。

## 🔄 如何更新数据？

脚本配置好之后，以后的工作就非常简单了。如果接口数据发生了变化（例如每天的录入量在增加），你不需要重复上面的步骤。

只需要：
*   在表格上点击 **右键** -> 选择 **【刷新】 (Refresh)**。

Excel 会自动重新发送 POST 请求，执行所有的计算逻辑，并拉取最新的数据展示给你。

---

通过这种方式，我们将一个原本可能需要写几十行代码的任务，变成了可重复使用的自动化流程，极大地提高了工作效率。
