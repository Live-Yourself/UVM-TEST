# SystemVerilog 语法速通（面向 Verilog 使用者，结合本工程）

本文专门解释：你当前 UVM 工程里每个 `.sv` 文件出现的、与 Verilog 不同/增强的语法。
目标是让你快速读懂这些文件在做什么、为什么要这么写。

---

## 1. 先建立整体认知：SV 比 Verilog 多了什么

你在本工程里会频繁见到以下“SV 核心能力”：

1) 面向对象（OOP）
- `class`、`extends`、`new()`、`super.new()`
- 用于搭建 UVM 组件与事务对象

2) 强类型与新数据类型
- `logic`、`bit`、`byte`、`string`、`int unsigned`
- `enum` 枚举、动态数组 `[]`、队列 `[$]`、关联数组 `[key_type]`

3) 随机化与约束
- `rand`、`constraint`、`inside`
- 用于构造可控随机激励

4) 接口与虚接口
- `interface` + `virtual interface`
- 用于把一组总线信号作为整体传给 class（driver/monitor）

5) 包与作用域
- `package`、`import`、`::`
- 用于组织类定义并进行命名空间访问

6) UVM 机制（基于 SV）
- 参数化类 `#(...)`
- 宏 `` `uvm_* ``
- `uvm_config_db#(T)::set/get`
- TLM analysis port/imp

---

## 2. 本工程文件与语法焦点一览

- [uvm/i2c_if.sv](uvm/i2c_if.sv)：`interface`、`logic`、`tri1`、接口内 `task`
- [uvm/i2c_cfg.sv](uvm/i2c_cfg.sv)：`class extends uvm_object`、构造函数、宏注册
- [uvm/i2c_item.sv](uvm/i2c_item.sv)：`enum`、`rand`、`constraint`、动态数组、队列
- [uvm/i2c_sequencer.sv](uvm/i2c_sequencer.sv)：参数化继承 `uvm_sequencer#(i2c_item)`
- [uvm/i2c_seqs.sv](uvm/i2c_seqs.sv)：`virtual task body()`、factory `type_id::create`
- [uvm/i2c_driver.sv](uvm/i2c_driver.sv)：`virtual i2c_if`、`uvm_config_db`、analysis port
- [uvm/i2c_monitor.sv](uvm/i2c_monitor.sv)：事件控制 `@(a or b)`、4态比较 `===`
- [uvm/i2c_agent.sv](uvm/i2c_agent.sv)：组件组装与 `connect_phase`
- [uvm/i2c_scoreboard.sv](uvm/i2c_scoreboard.sv)：analysis imp、关联数组、`exists()`
- [uvm/i2c_env.sv](uvm/i2c_env.sv)：env 层连接
- [uvm/i2c_tests.sv](uvm/i2c_tests.sv)：test 类、objection 机制
- [uvm/i2c_pkg.sv](uvm/i2c_pkg.sv)：`package/import/include`
- [uvm/tb_uvm_top.sv](uvm/tb_uvm_top.sv)：module 与 class 世界桥接（`config_db` 传 `vif`）

---

## 3. 按文件详细讲解（语法 + 文件作用）

## 3.1 [uvm/i2c_if.sv](uvm/i2c_if.sv)

### 文件作用
定义 I2C 引脚集合（`scl`、`sda` 等）和总线行为（开漏 + 上拉），供 DUT 与 UVM driver/monitor 共用。

### 关键 SV 语法

1) `interface i2c_if; ... endinterface`
- Verilog 没有 `interface` 概念。
- 它把多根信号与过程打包成“一个对象化连接点”。

2) `logic`
- 比 `wire/reg` 更统一，4 态（0/1/X/Z）。
- 过程赋值、连续赋值都能用（具体驱动规则仍要注意）。

3) `tri1 sda;`
- 网线类型，默认弱上拉到 1（无人驱动时为 1）。
- 适合 I2C SDA 开漏模型。

4) 接口内 `task`
- `task init_bus(); ... endtask`
- interface 不仅能放信号，也能放可复用过程。

---

## 3.2 [uvm/i2c_cfg.sv](uvm/i2c_cfg.sv)

### 文件作用
保存可配置时序参数（高低电平时间、额外低电平等），由 test 下发到 driver。

### 关键 SV/UVM 语法

1) `class i2c_cfg extends uvm_object;`
- 类继承，Verilog 不支持。
- `uvm_object` 表示“非层次对象”（不是组件树节点）。

2) `` `uvm_object_utils(i2c_cfg) ``
- UVM 宏，完成工厂注册等元信息。
- 没这个宏就无法用 `type_id::create()` 工厂创建。

3) `function new(string name = "i2c_cfg");`
- 构造函数默认参数（SV 特性）。

---

## 3.3 [uvm/i2c_item.sv](uvm/i2c_item.sv)

### 文件作用
定义事务 `i2c_item`：一次读/写操作需要哪些字段。

### 关键 SV 语法

1) `typedef enum {I2C_WRITE, I2C_READ} i2c_op_e;`
- 枚举类型，读写方向语义化。
- 比 `parameter`/`localparam` 更类型安全。

2) `rand`
- `rand bit [6:0] dev_addr;`
- 声明该字段可被随机化。

3) 动态数组
- `rand bit [7:0] wdata[];`
- 长度运行时决定，`new[n]` 分配。

4) 队列
- `bit ack_bits[$];`
- `$` 表示可变长度队列，支持 `push_back()`。

5) 约束块
- `constraint c_len { if (op == I2C_WRITE) wdata.size() inside {[1:16]}; }`
- `inside` 表示属于某个集合/范围。

6) 字符串与格式化
- `function string convert2string();`
- `$sformatf(...)` 返回格式化字符串。

---

## 3.4 [uvm/i2c_sequencer.sv](uvm/i2c_sequencer.sv)

### 文件作用
sequence 与 driver 之间的事务仲裁/派发组件。

### 关键语法

1) 参数化类继承
- `class i2c_sequencer extends uvm_sequencer#(i2c_item);`
- `#(i2c_item)` 指定该 sequencer 处理的事务类型。

---

## 3.5 [uvm/i2c_seqs.sv](uvm/i2c_seqs.sv)

### 文件作用
定义激励场景（smoke、非法地址、拉长时钟等）。

### 关键 SV/UVM 语法

1) `class ... extends ...`
- 多层继承：`i2c_smoke_seq extends i2c_base_seq`。

2) `virtual task body();`
- sequence 主执行体。
- `virtual` 便于子类重写。

3) 工厂创建
- `i2c_item::type_id::create("wr")`
- 与直接 `new` 相比，可被 factory override。

4) sequence 事务握手 API
- `start_item(wr); ... finish_item(wr);`
- 把 item 交给 sequencer/driver 流。

5) 动态数组分配
- `wr.wdata = new[1];`

---

## 3.6 [uvm/i2c_driver.sv](uvm/i2c_driver.sv)

### 文件作用
把事务对象转成 I2C 引脚时序，属于 pin-level 驱动层。

### 关键 SV/UVM 语法

1) `virtual i2c_if vif;`
- class 里不能直接放 interface 实例，需用 `virtual interface` 句柄。

2) 参数化静态方法调用
- `uvm_config_db#(virtual i2c_if)::get(...)`
- `#(T)` 明确配置值类型。

3) UVM 报告宏
- `` `uvm_fatal / `uvm_warning / `uvm_info ``
- 统一日志等级与格式。

4) 参数化类实例
- `uvm_analysis_port#(i2c_item) ap;`
- 用于把驱动后的事务广播给 scoreboard。

5) `input/output` 形参 + 默认值
- `task write_bit(bit b, int unsigned extra = 0);`
- 这是 SV 更丰富的子程序形参语法。

6) 队列操作
- `tr.ack_bits.push_back(ack);`

7) `case` + 枚举
- `case (tr.op) I2C_WRITE: ...`
- 可读性高于裸数字状态值。

---

## 3.7 [uvm/i2c_monitor.sv](uvm/i2c_monitor.sv)

### 文件作用
监听总线并报告 START/STOP（当前为轻量监控器）。

### 关键语法

1) 事件列表触发
- `@(vif.sda or vif.scl);`
- 任一信号变化都触发。

2) 4 态全等比较
- `===` 与 `!==`
- 会把 X/Z 也纳入比较，不像 `==`/`!=` 会因 X 产生不确定。

---

## 3.8 [uvm/i2c_agent.sv](uvm/i2c_agent.sv)

### 文件作用
把 `sequencer/driver/monitor` 封装成一个 agent。

### 关键语法

1) 组件工厂创建
- `i2c_driver::type_id::create("drv", this);`
- 第二参数 `this` 指定父组件，挂接到 UVM 层次树。

2) TLM 连接
- `drv.seq_item_port.connect(sqr.seq_item_export);`
- 这是 UVM 组件间通信连接语法，不是 Verilog 端口连线。

---

## 3.9 [uvm/i2c_scoreboard.sv](uvm/i2c_scoreboard.sv)

### 文件作用
实现参考模型与结果比对，输出 pass/fail 信息。

### 关键 SV/UVM 语法

1) analysis imp
- `uvm_analysis_imp#(i2c_item, i2c_scoreboard) imp;`
- 接收来自 analysis port 的事务。

2) 关联数组
- `byte unsigned model_mem [byte unsigned];`
- 索引不是固定范围位宽，而是 key-value 形式。

3) `exists()`
- `model_mem.exists(tr.reg_addr)`
- 判断 key 是否存在。

4) `return;` in function
- 在 `function void write(...)` 中可提前返回。

---

## 3.10 [uvm/i2c_env.sv](uvm/i2c_env.sv)

### 文件作用
环境层：把 agent 和 scoreboard 组合起来并完成连接。

### 关键语法

1) 层次化组件句柄访问
- `agent.drv.ap.connect(scb.imp);`
- 表示跨子组件层次访问端口并连接。

---

## 3.11 [uvm/i2c_tests.sv](uvm/i2c_tests.sv)

### 文件作用
定义测试用例，控制 sequence 启动、配置修改和仿真结束时机。

### 关键 SV/UVM 语法

1) `extends uvm_test`
- test 是 UVM 入口级组件。

2) `uvm_config_db#(i2c_cfg)::set(...)`
- 在 test 层向下发配置对象。

3) objection 机制
- `phase.raise_objection(this);`
- `phase.drop_objection(this);`
- 防止 run_phase 提前结束。

4) 运行时延时
- `#1000ns;`
- 带时间单位的延时写法。

5) 重写 `build_phase`
- `i2c_stretch_test` 中重写并修改 `cfg.scl_low_extra`。

---

## 3.12 [uvm/i2c_pkg.sv](uvm/i2c_pkg.sv)

### 文件作用
统一打包所有 UVM 类文件，供 top 一次性 import。

### 关键语法

1) `package ... endpackage`
- 命名空间容器。

2) `import uvm_pkg::*;`
- 导入 UVM 包中符号。

3) `` `include "xxx.sv" ``
- 文本级包含；常用于把多个 class 汇总进一个 package。

---

## 3.13 [uvm/tb_uvm_top.sv](uvm/tb_uvm_top.sv)

### 文件作用
DUT 实例化、时钟复位、UVM 启动与 `vif` 下发。

### 关键 SV/UVM 语法

1) module 中导入 package
- `import uvm_pkg::*;`
- `import i2c_pkg::*;`

2) interface 实例化
- `i2c_if i2c_vif();`

3) 参数化配置下发
- `uvm_config_db#(virtual i2c_if)::set(...)`

4) `run_test();`
- UVM 仿真入口（由 `+UVM_TESTNAME=...` 决定具体 test）。

---

## 4. 你最该先掌握的 12 条 SV 语法（按优先级）

1. `class` / `extends`
2. `new()` / `super.new()`
3. `package` / `import`
4. `interface` / `virtual interface`
5. `logic` / `bit` / `byte` / `string`
6. `enum` + `typedef`
7. 动态数组 `[]`
8. 队列 `[$]`
9. 关联数组 `[key_type]`
10. `rand` + `constraint` + `inside`
11. 参数化类型 `#(...)`
12. `::` 作用域访问（如 `type_id::create`、`uvm_config_db#(...)::get`）

---

## 5. 阅读这些 UVM 文件的建议顺序

1) 先看 [uvm/tb_uvm_top.sv](uvm/tb_uvm_top.sv)：知道仿真怎么启动。
2) 再看 [uvm/i2c_pkg.sv](uvm/i2c_pkg.sv)：知道类文件怎么组织。
3) 再看 [uvm/i2c_tests.sv](uvm/i2c_tests.sv)：知道 test 如何启动 sequence。
4) 再看 [uvm/i2c_seqs.sv](uvm/i2c_seqs.sv) + [uvm/i2c_item.sv](uvm/i2c_item.sv)：知道激励内容。
5) 再看 [uvm/i2c_driver.sv](uvm/i2c_driver.sv) + [uvm/i2c_if.sv](uvm/i2c_if.sv)：知道如何落到引脚。
6) 最后看 [uvm/i2c_monitor.sv](uvm/i2c_monitor.sv)、[uvm/i2c_scoreboard.sv](uvm/i2c_scoreboard.sv)、[uvm/i2c_env.sv](uvm/i2c_env.sv)、[uvm/i2c_agent.sv](uvm/i2c_agent.sv)：理解检查闭环。

---

## 6. 你可以直接对照的“Verilog -> SV/UVM”迁移思路

- 传统 testbench 里的“过程激励任务” -> UVM 中的 `sequence` + `driver`
- 传统全局变量配置 -> `uvm_config_db`
- 传统 monitor always 块 -> `uvm_monitor::run_phase`
- 传统自写比对逻辑 -> `scoreboard` + analysis port
- 单文件堆叠式 tb -> package + 类分层组织

如果你把这 5 条转变建立起来，后续看复杂 UVM 验证平台会非常快。

---

## 7. Factory 机制专章（结合当前工程）

### 7.1 Factory 的本质

`factory` 是 UVM 的“对象创建中心”，核心目标是：
- 创建点不写死具体实现；
- 后续可以替换实现（override）而不改原创建代码；
- 提升 testbench 复用性与可扩展性。

一句话：你写“要什么类型”，factory 决定“最终给你哪个实现类”。

### 7.2 三个必要步骤

1) 注册类型
- 对 `uvm_object` 子类用 `` `uvm_object_utils(...) ``。
- 对 `uvm_component` 子类用 `` `uvm_component_utils(...) ``。

2) 用工厂创建
- 统一用 `type_id::create(...)`。
- 不建议在 UVM 组件树里直接 `new` 子组件。

3)（可选）做 override
- 在 test 层把“基类 -> 子类”映射改掉。
- 原代码无需改动，运行时自动替换。

### 7.3 你工程里的 Factory 证据

- agent 注册：见 [uvm/i2c_agent.sv](uvm/i2c_agent.sv#L2)
- agent 用工厂创建三件套：
	- [sqr 创建](uvm/i2c_agent.sv#L14)
	- [drv 创建](uvm/i2c_agent.sv#L15)
	- [mon 创建](uvm/i2c_agent.sv#L16)
- sequence 里 item 工厂创建：见 [uvm/i2c_seqs.sv](uvm/i2c_seqs.sv#L19) 与 [uvm/i2c_seqs.sv](uvm/i2c_seqs.sv#L27)

### 7.4 为什么 `create("name", this)` 里要有 `this`

- 第二参数 `this` 是父组件句柄。
- 这样新组件会挂到 UVM 层次树下，路径正确，后续 `config_db`、report、topology 才可追踪。

### 7.5 一个最小 override 示例（教学示例）

思路：把 `i2c_driver` 替换为 `i2c_driver_dbg`，而不改 agent。

流程：
1. 定义 `class i2c_driver_dbg extends i2c_driver;`
2. 在 `i2c_driver_dbg` 里注册 `` `uvm_component_utils(i2c_driver_dbg) ``。
3. 在 test 的 `build_phase` 里设置 type override（基类映射到子类）。
4. 保持 agent 里仍是 [uvm/i2c_agent.sv](uvm/i2c_agent.sv#L15) 这句 `i2c_driver::type_id::create(...)`。

运行后，factory 会返回 `i2c_driver_dbg` 实例。你无需改 agent 文件。

---

## 8. 三大 Phase 专章（含常见用法与语句拆解）

### 8.1 为什么函数签名是 `...(uvm_phase phase)`

- 这是 UVM 基类定义好的回调接口签名。
- 你是在“重写”框架方法，参数类型和个数必须匹配。
- 变量名可以不是 `phase`，但工程里统一写 `phase` 便于阅读。

### 8.2 为什么 `build/connect` 是 `function`，`run` 是 `task`

- `build_phase` / `connect_phase` 是零时间阶段，不允许阻塞等待与延时，故用 `function void`。
- `run_phase` 需要时序行为（`forever`、`@`、`#`），会消耗仿真时间，故用 `task`。

### 8.3 `build_phase`：含义与常见用法

含义：创建组件、读取配置、做句柄初始化。

常见用法：
- `type_id::create(...)`
- `uvm_config_db::get(...)`
- 默认值处理与基础合法性检查

你工程中的例子：
- agent 创建子组件：见 [uvm/i2c_agent.sv](uvm/i2c_agent.sv#L12-L17)
- driver 获取 `vif/cfg`：见 [uvm/i2c_driver.sv](uvm/i2c_driver.sv#L13-L21)
- monitor 获取 `vif`：见 [uvm/i2c_monitor.sv](uvm/i2c_monitor.sv#L10-L14)

### 8.4 `connect_phase`：含义与常见用法

含义：连接 TLM 端口，建立组件间数据路径。

常见用法：
- `seq_item_port.connect(seq_item_export)`（sequencer->driver）
- `analysis_port.connect(analysis_imp)`（producer->scoreboard）

你工程里的关键语句：
- [uvm/i2c_agent.sv](uvm/i2c_agent.sv#L21)

拆解 `drv.seq_item_port.connect(sqr.seq_item_export);`：
1. `drv.seq_item_port`：driver 的请求端口（向 sequencer 取事务）。
2. `sqr.seq_item_export`：sequencer 的导出端。
3. `connect(...)`：把二者连成通路。

连好后，driver 才能在 [uvm/i2c_driver.sv](uvm/i2c_driver.sv#L122) 执行 `get_next_item(tr)`。

如果没连这条线，driver 将拿不到事务，`run_phase` 不能正常工作。

补充一个同类连接：
- env 里把 driver 的 analysis port 接到 scoreboard：见 [uvm/i2c_env.sv](uvm/i2c_env.sv#L17)

### 8.5 `run_phase`：含义与常见用法

含义：执行实际时序动作与协议行为。

常见用法：
- 驱动器：`forever + get_next_item + item_done`
- 监视器：`forever + @(...)` 采样
- test：`raise/drop_objection` 控制结束

你工程中的典型实现：
- driver 主循环：见 [uvm/i2c_driver.sv](uvm/i2c_driver.sv#L117-L129)
- monitor 监听循环：见 [uvm/i2c_monitor.sv](uvm/i2c_monitor.sv#L16-L28)
- test objection：见 [uvm/i2c_tests.sv](uvm/i2c_tests.sv#L25-L30)

### 8.6 为什么 agent 常见 `build+connect`，driver/monitor 常见 `build+run`

- agent 的职责是“组装与连线”，自然重心在 `build/connect`。
- driver/monitor 的职责是“时序执行与采样”，自然重心在 `run`（并在 build 拿配置）。

注意：这不是语法限制，而是职责分层最佳实践。
