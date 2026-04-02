# SVG Renderer

基于仓颉语言（Cangjie）实现的 SVG 转 BMP 渲染器。

## 功能特性

- SVG 解析：支持 `<path>`、`<polygon>`、`<polyline>`、`<rect>`、`<circle>`、`<ellipse>`、`<line>` 等元素
- 路径命令：M/m、L/l、H/h、V/v、C/c、S/s、Q/q、T/t、A/a、Z/z
- 变换：`translate` + `scale` 组合变换，支持嵌套 `<g>` 级联
- 填充规则：`evenodd` / `nonzero`（支持继承）
- 颜色：hex 颜色值，`fill` 属性及 `style` 内联样式
- 抗锯齿：4x4 超采样（16 个子像素），贝塞尔曲线 64 步细分
- 输出：24 位 BMP 格式

## 环境要求

- 仓颉编译器 cjc 1.0.5+
- Windows 操作系统

## 编译

```powershell
# 编译（无警告）
cjc -Woff unused -o out\svg_renderer.exe src\main.cj

# 编译时间：约 5-10 秒
```

## 使用

```bash
out\svg_renderer.exe <输入.svg> [输出.bmp] [宽度] [高度]

不指定宽高时，渲染器根据 viewBox 比例自动计算，保证最短边至少 1000 像素。
```

### 参数说明

| 参数 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| 输入 SVG | 是 | - | SVG 文件路径 |
| 输出 BMP | 否 | 与 SVG 同目录同名 | BMP 文件路径（建议与SVG同目录） |
| 宽度 | 否 | 按比例自动计算 | 输出图片宽度（像素） |
| 高度 | 否 | 按比例自动计算 | 输出图片高度（像素） |

### 示例

```powershell
# 输出到 SVG 同目录（推荐）
# 用时：约 20-30 秒
out\svg_renderer.exe testcase\4-cat.svg testcase\4-cat.bmp

# 指定宽高
# 用时：约 30-45 秒
out\svg_renderer.exe testcase\4-cat.svg testcase\4-cat.bmp 2000 2000
```



## 测试用例

以下测试命令将生成BMP文件到 `testcase` 目录：

```powershell
# 测试1: 仓颉logo (简单)
# 用时：约 5-10 秒
out\svg_renderer.exe testcase\2-cangjie.svg testcase\2-cangjie.bmp

# 测试2: 引擎 (中等复杂度)
# 用时：约 15-25 秒
out\svg_renderer.exe testcase\2-engine.svg testcase\2-engine.bmp

# 测试3: 六边形 (简单)
# 用时：约 5-10 秒
out\svg_renderer.exe testcase\2-hexagon.svg testcase\2-hexagon.bmp

# 测试4: 蝴蝶 (中等复杂度)
# 用时：约 20-30 秒
out\svg_renderer.exe testcase\4-butterfly.svg testcase\4-butterfly.bmp

# 测试5: 猫 (中等复杂度)
# 用时：约 20-30 秒
out\svg_renderer.exe testcase\4-cat.svg testcase\4-cat.bmp

# 测试6: 鸟 (高复杂度，165KB SVG)
# 用时：约 60-90 秒
out\svg_renderer.exe testcase\6-bird.svg testcase\6-bird.bmp
```

### 性能说明

- **渲染时间**主要取决于：SVG文件大小、路径复杂度、输出分辨率
- 小文件 ( < 50KB)：5-20秒
- 中等文件 (50-100KB)：20-40秒
- 大文件 ( > 100KB)：40-90秒或更长
- 生成的BMP文件较大（几MB到几十MB），属于正常现象

### Baseline对比

项目中包含 `testcase\baseline\` 目录，内有标准输出文件，可用于对比验证渲染正确性。

## 项目结构

```
├── src/
│   └── main.cj          # 主源码（约1130行）
├── testcase/            # 测试用例
│   ├── 2-cangjie.svg    # 仓颉logo
│   ├── 2-engine.svg     # 引擎
│   ├── 2-hexagon.svg    # 六边形
│   ├── 4-butterfly.svg  # 蝴蝶
│   ├── 4-cat.svg        # 猫
│   ├── 6-bird.svg       # 鸟
│   └── baseline/        # 标准输出
├── out/                 # 编译输出目录
├── cjpm.toml            # 项目配置
└── README.md            # 本文档
```

## 注意事项

- 程序会自动处理路径中的斜杠（/ 和 \）
- 输出目录必须存在，否则程序会报错（建议输出到testcase目录）
- 使用 `OpenMode.Write` 模式写入文件，无需手动删除旧文件
- 程序使用4x4超采样抗锯齿，输出质量较高


