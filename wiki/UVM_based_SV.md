# SystemVerilog 与 UVM 验证实践要点（基于本工程）

> 面向 I2C Slave 验证场景整理。重点覆盖：SystemVerilog 常用语法、UVM 类体系、工厂机制、phase 机制、TLM 连接与 `config_db` 配置传递。

---

## 1. SystemVerilog 变量与数据结构

### 1.1 常用变量类型

| 类型 | 典型场景 | 说明 |
|---|---|---|
| `bit` / `logic` | 接口信号、临时标志 | `bit` 为二值（0/1）；`logic` 为四值（0/1/X/Z），接口与 RTL 连接建议优先 `logic` |
| `int` / `integer` | 计数器、配置参数 | `int`：32 位有符号；`integer`：四值有符号（旧代码常见）；验证中地址/长度常用 `int unsigned` |
| `byte` / `shortint` / `longint` | 数据缓存 | 分别 8/16/64 位，按需选位宽可节省内存 |
| `real` / `shortreal` | 模拟参数 | 实数建模使用，纯数字逻辑验证较少 |
| `string` | 日志、路径名 | `uvm_info` 消息、`uvm_config_db` 路径、文件路径 |
| `enum` | 状态机、操作类型 | 可读性高，适合 opcode/state（如 `IDLE/START/DATA/STOP`） |
| 队列 / 动态数组 / 关联数组 | 数据收集与模型存储 | 队列适合流式缓存；动态数组适合可变长度 payload；关联数组适合稀疏/键值映射模型 |

### 1.2 典型声明示例

#### 枚举定义
```systemverilog
typedef enum {I2C_WRITE, I2C_READ} i2c_op_e;
```

参数/语义说明：
- `typedef`：类型定义关键字，为枚举类型创建别名。
- `enum`：定义命名常量集合，提升可读性与可维护性。
- `I2C_WRITE, I2C_READ`：枚举成员，默认从 `0` 递增。
- `i2c_op_e`：枚举类型名，`_e` 是常见命名后缀。

#### 非随机动态数组
```systemverilog
bit [7:0] rdata[];
```

参数/语义说明：
- `bit [7:0]`：元素类型为 8 位二值数据。
- `rdata[]`：动态数组，长度运行时分配。
- 未加 `rand`：不参与随机化，常用于保存 DUT 返回数据。

#### 队列
```systemverilog
bit ack_bits[$];
```

参数/语义说明：
- `bit`：队列元素类型。
- `[$]`：队列大小可动态变化。
- 典型用途：记录每个 byte 对应的 ACK/NACK 位。

#### 关联数组
```systemverilog
byte unsigned model_mem[byte unsigned];
```

参数/语义说明：
- 左侧 `byte unsigned`：值类型（存储的内容）。
- `model_mem`：数组名。
- 右侧 `[byte unsigned]`：索引类型（键类型）。
- 适合做寄存器/存储器参考模型（稀疏地址空间友好）。

常用方法：
- `array.size()`
- `array.delete([key])`
- `array.exists(key)`
- `array.first(key)` / `array.last(key)`
- `foreach(array[key]) ...`

---

## 2. UVM 类体系与职责划分

### 2.1 类别总览

| 类别 | 典型基类 | 核心职责 | 工程实践建议 |
|---|---|---|---|
| Transaction（事务） | `uvm_sequence_item` | 封装一次传输的数据字段与约束 | 实现 `copy/compare/convert2string`，必要时实现 `pack/unpack` |
| Sequence（序列） | `uvm_sequence` | 组织和生成激励流 | 在 `body()` 中构造场景，可复用、可嵌套 |
| Driver（驱动） | `uvm_driver #(T)` | 事务级到引脚级转换 | 在 `run_phase()` 中执行握手、时序驱动 |
| Monitor（监视） | `uvm_monitor` | 引脚级到事务级采样重建 | 通过 analysis 端口广播给 scoreboard/coverage |
| Sequencer（序列器） | `uvm_sequencer #(T)` | 调度 sequence 与 driver 握手 | 管理事务发放与仲裁 |
| Agent（代理） | `uvm_agent` | 封装 `sqr+drv+mon` | 支持 active/passive，可配置复用 |
| Scoreboard（记分板） | `uvm_scoreboard` | 预期/实测比对 | 建议使用队列或关联数组做参考模型 |
| Env（环境） | `uvm_env` | 集成多个 agent 与检查组件 | 在 `connect_phase` 完成 TLM 连线 |
| Test（测试） | `uvm_test` | 顶层场景控制 | 构建环境、下发配置、启动 sequence |
| Config（配置对象） | `uvm_object` | 参数集中管理 | 通过 `uvm_config_db` 分发给下层组件 |

### 2.2 继承示例

```systemverilog
class i2c_item extends uvm_sequence_item;
```

语句解释：
- `class`：定义类。
- `i2c_item`：事务类名，表示一次 I2C 传输抽象。
- `extends`：继承关键字。
- `uvm_sequence_item`：UVM 事务基类，提供随机化、打印、比较等基础能力。

```systemverilog
class i2c_sequencer extends uvm_sequencer #(i2c_item);
class i2c_driver    extends uvm_driver    #(i2c_item);
```

语句解释：
- `#(i2c_item)`：参数化类型，指定 sequencer/driver 处理的事务类型。
- `uvm_sequencer #(i2c_item)`：调度并向 driver 发放 `i2c_item`。
- `uvm_driver #(i2c_item)`：从 sequencer 获取 `i2c_item` 后驱动到引脚时序。

---

## 3. `new` 与对象创建方式

| 用法 | 语法 | 说明 |
|---|---|---|
| 直接构造对象 | `obj = new();` / `obj = new("name");` | 不经过工厂，不能 type override |
| 动态数组创建 | `arr = new[size];` | 元素按类型默认值初始化 |
| 动态数组复制 | `arr2 = new[n](arr1);` | 新数组可与旧数组长度不同 |
| 随机化 | `assert(obj.randomize());` | 先 `new` 再随机化 |
| 工厂创建（推荐） | `T::type_id::create("name", parent)` | 支持 override 与统一管理 |

> 说明：在 UVM 环境中，组件与事务对象优先使用工厂创建。

---

## 4. UVM 工厂机制（Factory）

### 4.1 注册宏选择

| 宏 | 用于 | 示例 |
|---|---|---|
| `` `uvm_object_utils(T)`` | 非参数化 `uvm_object` 派生类 | item、cfg、sequence |
| `` `uvm_component_utils(T)`` | 非参数化 `uvm_component` 派生类 | driver、monitor、agent、env、test |
| `` `uvm_object_param_utils(T)`` | 参数化 object | `packet #(DWIDTH)` |
| `` `uvm_component_param_utils(T)`` | 参数化 component | `agent #(CFG_T)` |

自动字段宏（`*_utils_begin/end`）可减少样板代码，但有性能成本，建议按需使用。

### 4.2 构造函数模板

#### 对象
```systemverilog
class i2c_item extends uvm_sequence_item;
  `uvm_object_utils(i2c_item)

  function new(string name = "i2c_item");
    super.new(name);
  endfunction
endclass
```

关键说明：
- 对象类构造函数通常为 `new(string name = "...")`。
- `super.new(name)` 用于初始化父类对象信息。
- 对象类无 `parent`，不参与 UVM 组件层次树。

#### 组件
```systemverilog
class i2c_sequencer extends uvm_sequencer #(i2c_item);
  `uvm_component_utils(i2c_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
```

关键说明：
- 组件类构造函数必须带 `parent`：`new(string name, uvm_component parent)`。
- `super.new(name, parent)` 建立组件层次关系。
- 组件存在于拓扑中，受 phase 机制统一调度。

### 4.3 工厂创建示例

```systemverilog
cfg = i2c_cfg::type_id::create("cfg");          // object：不需要 parent
env = i2c_env::type_id::create("env", this);    // component：需要 parent
```

---

## 5. UVM Phase 机制（重点）

### 5.1 `build_phase(uvm_phase phase)`
- 作用：创建组件/对象、读取配置（零时间）。
- 类型：`function`。
- 典型内容：
  - `type_id::create(...)`
  - `uvm_config_db::get(...)`

### 5.2 `connect_phase(uvm_phase phase)`
- 作用：连接 TLM 端口（零时间）。
- 类型：`function`。
- 典型内容：
  - `drv.seq_item_port.connect(sqr.seq_item_export);`
  - `mon.ap.connect(scb.imp);`

### 5.3 `run_phase(uvm_phase phase)`
- 作用：执行有时间行为（驱动、采样、等待）。
- 类型：`task`。
- 典型内容：
  - `forever` 循环
  - `@(...)` / `#...` 时序行为
  - `phase.raise_objection(this)` / `phase.drop_objection(this)`

### 5.4 重写构建阶段（示例）

```systemverilog
function void build_phase(uvm_phase phase);
  super.build_phase(phase);
  cfg.scl_low_extra = 300;
endfunction
```

说明：
- 先调用 `super.build_phase(phase)`，保证父类构建流程完整执行。
- 再覆盖/细化配置参数（如 `cfg.scl_low_extra`）。
- 在 `build_phase` 中修改配置，可确保在后续连接与运行前生效。

---

## 6. 常用操作符与语法速查

### 6.1 比较与集合判断

| 符号/语法 | 作用 | 示例 |
|---|---|---|
| `===` / `!==` | 四态严格比较（含 X/Z） | `1'bz === 1'bz` |
| `==?` / `!=?` | 通配比较（右侧 X/Z 视为通配） | `a ==? 4'b1x0x` |
| `inside` | 集合成员判断 | `x inside {[1:10],20}` |

### 6.2 位操作、拼接与数据重排

| 符号/语法 | 作用 | 示例 |
|---|---|---|
| `<<` / `<<<` | 逻辑左移 / 算术左移 | `a << 2`, `sa <<< 2` |
| `{}` / `{{}}` | 拼接 / 复制拼接 | `{a,b}`, `{4{a}}` |
| `{<<{}}` / `{>>{}}` | 流式打包/解包 | `{<<8{data}}` |
| `'1` / `'0` / `'x` | 填充值 | `logic [7:0] a='1;` |

### 6.3 赋值与自增

| 符号/语法 | 作用 | 示例 |
|---|---|---|
| `++` | 自增 | `i++`, `++i` |
| `+=` / `-=` / `*=` / `%=` / `^=` | 复合赋值 | `a += b`, `a ^= b` |

### 6.4 作用域与面向对象相关

| 符号/语法 | 作用 | 示例 |
|---|---|---|
| `::` | 作用域解析 | `cls::var` |
| `->` | 类句柄成员访问 | `p->data` |
| `virtual` | 虚方法/虚接口 | `virtual task ...`, `virtual i2c_if vif;` |
| `typedef` | 类型别名 | `typedef logic [7:0] byte_t;` |

### 6.5 过程块关键字

| 符号/语法 | 作用 | 示例 |
|---|---|---|
| `always_comb` | 组合逻辑过程块 | 自动敏感列表 |
| `always_latch` | 锁存逻辑过程块 | `always_latch begin ... end` |
| `always_ff` | 时序逻辑过程块 | `@(posedge clk)` |

### 6.6 常见系统函数

| 符号/语法 | 作用 | 示例 |
|---|---|---|
| <code>&#36;sformatf</code> | 格式化字符串 | <code>&#36;sformatf("v=%0d", v)</code> |
| <code>&#36;random</code> | 有符号随机数 | <code>val = &#36;random();</code> |
| <code>&#36;clog2</code> | 向上取整对数 | <code>int w = &#36;clog2(depth);</code> |

---

## 7. UVM 常用 API 速查

| 类别 | 方法/宏 | 说明 |
|---|---|---|
| 对象创建 | `type_id::create` / `new` | 工厂创建 / 直接创建 |
| 配置管理 | `uvm_config_db::set/get` | 跨层传参 |
| 报告机制 | `` `uvm_info / `uvm_warning / `uvm_error / `uvm_fatal`` | 日志与错误处理 |
| 相位 | `build_phase/connect_phase/run_phase` | 生命周期入口 |
| objection | `raise_objection/drop_objection` | 控制测试结束时机 |
| 序列驱动握手 | `get_next_item/item_done` | sequencer-driver 通道 |
| 事务工具 | `copy/compare/print/convert2string` | 调试与比对 |
| 随机化 | `randomize` | 约束随机激励 |

### 报告宏默认行为

| 宏 | 默认 verbosity | 是否终止仿真 |
|---|---|---|
| `` `uvm_fatal`` | `UVM_NONE` | 是 |
| `` `uvm_error`` | `UVM_NONE` | 否 |
| `` `uvm_warning`` | `UVM_MEDIUM` | 否 |
| `` `uvm_info`` | `UVM_MEDIUM` | 否 |

---

## 8. TLM 连接模型：Analysis 与 Seq-Drv 握手

### 8.1 Analysis 广播（发布/订阅）

- 端口类型：`uvm_analysis_port` / `uvm_analysis_imp`
- 回调约定：`write(T t)`
- 典型链路：`monitor(or driver) -> scoreboard/coverage`

关键关系：
1. 发布端定义：`uvm_analysis_port #(i2c_item) ap;`
2. 订阅端定义：`uvm_analysis_imp #(i2c_item, i2c_scoreboard) imp;`
3. 拓扑连接：`agent.drv.ap.connect(scb.imp);`
4. 发布事务：`ap.write(tr);`（框架回调到订阅者 `write()`）

关键语句解释：
- `uvm_analysis_port #(i2c_item) ap;`：声明广播发布端。
- `uvm_analysis_imp #(i2c_item, i2c_scoreboard) imp;`：声明订阅入口，回调到 `i2c_scoreboard::write()`。
- `agent.drv.ap.connect(scb.imp);`：把发布端和接收端连通。
- `ap.write(tr);`：发布事务给所有订阅者（1 对多）。

### 8.2 Sequencer-Driver 事务握手

- 端口类型：`seq_item_port` / `seq_item_export`
- 关键方法：
  - `seq_item_port.get_next_item(req);`
  - `seq_item_port.item_done();`

连接语句：
```systemverilog
drv.seq_item_port.connect(sqr.seq_item_export);
```

未连接时，`get_next_item()` 无法正常取到事务，导致仿真异常或停滞。

关键语句解释：
- `seq_item_port.get_next_item(req)`：driver 阻塞等待 sequencer 发下一个事务。
- `seq_item_port.item_done()`：通知 sequencer 当前事务处理完成。
- `drv.seq_item_port.connect(sqr.seq_item_export)`：建立 sequencer → driver 握手通道。

---

## 9. `uvm_config_db` 配置传递机制

### 9.1 配置下发（set）

```systemverilog
uvm_config_db#(i2c_cfg)::set(this, "env.agent*", "cfg", cfg);
```

含义：
- 类型为 `i2c_cfg`
- 从 `this` 作用域发布
- 路径匹配 `env.agent*`
- 键名 `cfg`
- 值为配置对象 `cfg`

参数解释（`set(cntxt, inst_name, field_name, value)`）：
- `this`：发布配置的起始上下文。
- `"env.agent*"`：目标实例路径（支持通配符 `*`）。
- `"cfg"`：配置键名。
- `cfg`：实际下发的配置对象。

### 9.2 配置读取（get）

```systemverilog
if (!uvm_config_db#(virtual i2c_if)::get(this, "", "vif", vif))
  `uvm_fatal("NOVIF", "vif not set")
```

说明：
- 获取 `virtual i2c_if` 类型的虚接口
- 键名为 `vif`
- 未取到则 `uvm_fatal` 终止仿真

参数解释（`get(cntxt, inst_name, field_name, value_out)`）：
- `this`：当前组件上下文（谁来取）。
- `""`：实例名不过滤（在当前可见范围内查找）。
- `"vif"`：要读取的键名。
- `vif`：输出变量（取到后写入该句柄）。

---

## 10. Driver 骨架（推荐模板）

```systemverilog
class i2c_driver extends uvm_driver #(i2c_item);
  `uvm_component_utils(i2c_driver)

  virtual i2c_if vif;
  i2c_cfg cfg;
  uvm_analysis_port #(i2c_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual i2c_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "vif not set")
    if (!uvm_config_db#(i2c_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = i2c_cfg::type_id::create("cfg");
      `uvm_warning("NOCFG", "cfg not set, use default")
    end
  endfunction

  task run_phase(uvm_phase phase);
    i2c_item tr;
    vif.init_bus();

    forever begin
      seq_item_port.get_next_item(tr);
      `uvm_info("DRV", $sformatf("Drive: %s", tr.convert2string()), UVM_MEDIUM)
      case (tr.op)
        I2C_WRITE: do_write(tr);
        I2C_READ : do_read(tr);
      endcase
      ap.write(tr);
      seq_item_port.item_done();
    end
  endtask
endclass
```

关键语句逐行说明：
- `virtual i2c_if vif;`：类里保存虚接口句柄，不能直接例化 interface 实体。
- `uvm_analysis_port #(i2c_item) ap;`：用于把 driver 事务广播给 scoreboard/coverage。
- `ap = new("ap", this);`：在构造函数中创建 analysis 端口。
- `super.build_phase(phase);`：先执行父类构建逻辑。
- `uvm_config_db::get(..."vif", vif)`：从配置库提取虚接口。
- `` `uvm_fatal("NOVIF", ...)``：接口缺失时立即终止，避免空句柄驱动。
- `uvm_config_db::get(..."cfg", cfg)`：读取配置对象；缺失时创建默认配置并告警。
- `seq_item_port.get_next_item(tr);`：获取待驱动事务。
- `` `uvm_info("DRV", $sformatf(...), UVM_MEDIUM)``：打印调试日志。
- `case (tr.op)`：按事务操作类型选择写/读驱动流程。
- `ap.write(tr);`：把“已执行事务”发送到分析通道。
- `seq_item_port.item_done();`：完成握手，允许发下一个事务。

`uvm_info` 详细级别补充：
- 常见等级：`UVM_NONE / UVM_LOW / UVM_MEDIUM / UVM_HIGH / UVM_FULL / UVM_DEBUG`。
- 建议默认使用 `UVM_MEDIUM`，调试难题时临时提升 verbosity。

---

## 11. 易错点与检查清单

- `build_phase()` 忘记 `super.build_phase(phase)`。
- `driver` 未拿到 `vif` 却继续仿真。
- `seq_item_port` 与 `seq_item_export` 未连接。
- `item_done()` 漏调用导致 sequence 卡死。
- object/component 的 `new()` 形参写错：
  - object：`new(string name="...")`
  - component：`new(string name, uvm_component parent)`
- 组件类与对象类注册宏混用。

---

## 12. 建议阅读顺序（给初学者）

1. 第 2 章：先建立 UVM 组件分工概念。  
2. 第 5 章：理解 phase 何时做什么。  
3. 第 8 章：吃透两类核心连接（analysis、seq-drv）。  
4. 第 9~10 章：按模板落地到工程代码。  
5. 第 11 章：对照清单逐项排查。

---

如需下一步，我可以继续把该文档按“面试问答版”再整理一版（每个知识点配 1 个典型追问和标准回答）。
<!-- 下面是旧版草稿内容，已归档，不再作为主文档阅读
[TOC](目录)
## 变量
| 变量类型  |  典型场景  |  说明及实例  |
|-----|-----|:------|
bit/ logic​|接口信号、临时标志|- bit：二值（0/1），用于不需要X/Z状态的内部逻辑 <br>- logic：四值（0/1/X/Z），推荐用于接口信号，可检测不定态
int/ integer​|计数器、配置参数| - int：32位有符号，常用于循环计数<br>- integer：四值有符号，旧代码常见 <br>- 验证中多用int unsigned表示地址、长度等无符号值
byte/ shortint/ longint​|数据存储|按需选择位数，节省内存：<br>- byte：8位（有符号）<br>- shortint：16位<br>- longint：64位
real/ shortreal​|模拟参数|模拟电路延时、电压等实数参数，较少用于RTL验证​
string​|消息、路径名|打印消息、uvm_config_db路径名、文件路径
enum(枚举)​|状态机、操作码|提高可读性：enum {IDLE, START, DATA, STOP} state;
队列/动态数组/关联数组​|数据收集|- data_q[$]：记分板存储<br>- data_da[]：动态大小数据包<br>- assoc_array[string]：基于字符串索引的配置

### 示例
#### 1. 枚举类型定义
- **typedef enum {I2C_WRITE, I2C_READ} i2c_op_e;**
  - typedef：类型定义关键字，为枚举类型创建别名
  - enum：定义枚举类型，创建命名常量集，提高代码可读性
  -  I2C_WRITE, I2C_READ：枚举成员，默认值从0开始（0,1）
  -  i2c_op_e：枚举类型名，_e是常见后缀表示枚举

#### 2. 非随机动态数组
- **bit [7:0] rdata[];**
  - 无rand：不参与随机化
  - rdata[]：存储读取数据，由DUT返回

#### 3. 队列声明
- **bit ack_bits[$];**
  - bit：队列元素类型
  - ack_bits[ $ ]：队列声明，$表示大小动态。用于存储每个字节传输的ACK/NACK位

#### 4. 关联数组声明
- **byte unsigned model_mem [byte unsigned];**
  - byte unsigned：数组元素类型（无符号字节）
  - model_mem：数组名
  - [byte unsigned]：索引类型（无符号字节）
  - 这是关联数组，索引可以是任意字节值（0-255）
- **常见方法：**
  - array.size()：返回元素个数
  - array.delete([key])：删除元素
  - array.exists(key)：检查键是否存在
  - array.first(ref key)：获取第一个键
  - array.rsort()：降序排列
  - array.reverse()：反转顺序
  - value = array[key]; 直接通过键获取对应键值
  - foreach(array[key, value])：遍历所有键值

## 类
| 类别  |  父类  |  核心用途  | 项目实践要点
|-----|-----|------|:-------|
**数据对象类**
事务类 (Transaction)​|uvm_sequence_item|封装数据传输单元|- 包含协议字段+约束<br>- 实现pack/unpack用于序列化<br>- 包含compare、copy等方法
配置类 (Configuration)​|uvm_object|环境参数集中管理|- 包含DUT可配置参数<br>- 通过uvm_config_db传递<br>- 支持随机化生成不同场景
**激励生成类**
序列类 (Sequence)​|uvm_sequence|激励生成与组织|- 在body()中组织事务流<br>- 可嵌套、可复用<br>- 通过sequencer发送到driver
组件类 (Component)​|uvm_component|验证环境构建块|- Driver/ Monitor/ Agent/ Env/ Test等<br>- 在验证层次中固定存在<br>- 有phase生命周期管理
**验证组件类**
驱动器|uvm_driver|事务→信号转换|1. 在run_phase中循环获取事务<br>2. 调用虚拟接口驱动信号<br>3. 处理协议时序和握手
监视器|uvm_monitor|信号→事务转换|1. 采样接口信号组装事务<br>2. 通过analysis port广播<br>3. 内嵌断言检查协议
序列器|uvm_sequencer|调度sequence和driver|1. 管理sequence优先级<br>2. 处理driver请求<br>3. 支持锁定机制
代理|uvm_agent|封装driver+monitor+sequencer|1. 根据配置启用/禁用组件<br>2. 提供统一配置接口<br>3. 支持VIP复用
环境|uvm_env|封装多个agent和组件|1. 构建验证子环境<br>2. 配置组件间连接<br>3. 支持层次化复用
测试|uvm_test|顶层测试控制|1. 构建验证环境<br>2. 创建并启动sequence<br>3. 配置测试参数
**功能检查类**
记分板 (Scoreboard)​|uvm_scoreboard|数据检查与比对|- 实现write()接口接收数据<br>- 使用队列或关联数组缓存预期<br>- 比较实际vs预期并报告
断言监控|uvm_monitor|协议断言检查|1. 内嵌SVA断言<br>2. 收集断言覆盖率<br>3. 报告断言违规
功能覆盖|通常内嵌在monitor|收集功能覆盖率|1. 在monitor中采样covergroup<br>2. 定义覆盖点和交叉覆盖<br>3. 生成覆盖率报告
**回调扩展类**
回调类 (Callback)​|uvm_callback|非侵入式扩展功能|- 错误注入、覆盖率收集<br>- 在不修改原代码时扩展功能


### 继承
#### 1. 类继承
- **class i2c_item extends uvm_sequence_item;**
  - class：定义类，面向对象编程基础
  -  i2c_item：事务类名，通常表示一个完整的事务/数据包
  -  extends：继承关键字
  - uvm_sequence_item：UVM事务基类，提供事务级方法（如随机化、序列化）

#### 2. 参数化类继承
- **class i2c_sequencer extends uvm_sequencer#(i2c_item);**
  - **#(i2c_item)**：类型参数，指定此`序列器`处理的事务类型
- **class i2c_driver extends uvm_driver#(i2c_item);**
  - **#(i2c_item)**：类型参数，指定此`driver`处理的事务类型为i2c_item
## new用法
| 用法  |  语法  |  作用  | 示例 | 注意
|-----|-----|------|-------|------|
**对象创建**​|obj = new();<br>obj = new("name");|调用构造函数创建对象|i2c_item item = new("item");|不通过工厂，不支持重写
**动态数组​**|arr = new[size];|创建指定大小的动态数组|int data[] = new[10];|元素为默认值（0, X等）
**数组复制**​|arr = new[old_size] (old_arr);| 创建新数组并复制旧值|new_data = new[5] (data);|新数组大小可不同
**数组初始化**​|arr = new[size]**'**{values};|创建并初始化数组|int arr[] = new[3]'{1,2,3};|初始化列表必须匹配大小
**队列创建​**|q = new();|创建队列对象|queue#(int) q = new();|通常队列直接声明使用
**字符串创建​**|str = new[len];|创建指定长度字符串|string s = new[10];|不常用，通常直接赋值
**关联数组​**|aa = new();|创建关联数组对象|int aa[string] = new();|通常直接声明使用
**内存分配**​|mem = new[size];|动态分配内存|bit [7:0] mem[] = new[1024];|用于大型数据缓冲区
**随机化创建**​|obj.randomize();|创建随机化对象|assert(item.randomize());|在new后调用
**工厂创建**​|type_id::create()|通过工厂创建对象|i2c_item::type_id::create()|支持重写，推荐使用

## factory机制
### UVM工厂注册宏
| 宏类型  |  适用场景  |  代码示例  | 说明与注意事项 
|-----|-----|------|-------|
`uvm_object_utils(T)​|普通对象类|uvm_object_utils(i2c_transaction)|事务、配置等数据对象必须使用，否则无法通过工厂创建
`uvm_component_utils(T)​|组件类|uvm_component_utils(i2c_driver)|所有验证组件必须使用，支持层次化创建
`uvm_object_param_utils(T)​|参数化对象|uvm_object_param_utils(packet #(DWIDTH))|带参数的类需要此宏
`uvm_component_param_utils(T)​|参数化组件|uvm_component_param_utils(agent #(CFG))|参数化组件注册
uvm_object_utils_begin/end​|需要字段自动化的类|uvm_object_utils_begin(my_trans) uvm_field_int(data, UVM_ALL_ON) uvm_object_utils_end|自动实现copy、compare、print等方法，性能有损耗，谨慎使用​
uvm_component_utils_begin/end​|组件字段自动化|同上，用于组件|同样有性能影响

### 工厂注册

#### 工厂注册使用类的判断原则
| 类的特性  |  应使用的工厂注册宏 |  示例  | 理由
|-----|-----|------|-------|
在验证层次中永久存在<br>（有parent参数）|uvm_component_utils|driver, monitor, agent, env, test，sequencer|组件在验证环境中固定存在，构成层次结构
临时创建和销毁 <br>（无parent参数）|uvm_object_utils|transaction, sequence, config|对象根据需要动态创建，不参与验证层次
有参数化的类​|uvm_component_param_utils<br>uvm_object_param_utils|driver#(i2c_item)|参数化的组件或对象需要特殊宏
需要字段自动化<br>（调试用）|uvm_component_utils_begin/end<br>uvm_object_utils_begin/end|复杂的config类|自动实现copy、compare、print等方法

**示例：**
- **`uvm_object_utils(i2c_item)**
  - ​将i2c_item注册到UVM工厂，使其可通过工厂创建实例，支持类型重写


### 构造函数
#### 1. 对象构造函数
```bash
class i2c_item extends uvm_sequence_item;
  `uvm_object_utils(i2c_item)
  
    function new(string name = "i2c_item");
    super.new(name);	// 调用父类uvm_sequence的构造函数
  endfunction
```

#### 2. 组件构造函数
```bash
class i2c_sequencer extends uvm_sequencer#(i2c_item);
  `uvm_component_utils(i2c_sequencer)

  function new(string name, uvm_component parent);  //组件必须在构造时知道其父组件，以构建验证层次结构
    super.new(name, parent);
  endfunction
```

**与对象构造函数的区别：**
- 对象：new(`string name = "..."`)
- 组件：new(`string name`, `uvm_component parent`)
- 调用父类构造函数super.new(`name`, `parent`);  ——传递name和parent参数
  - 设置组件名称和父指针
  - 初始化序列器内部状态
  - 建立与其他组件的连接基础
 

### 工厂创建

#### 创建配置（对象）→ 不需要父组件
- **cfg = i2c_cfg::type_id::create("cfg");**
   - 继承自​uvm_component
#### 创建环境（组件）→ 需要父组件
- **env = i2c_env::type_id::create("env", `this`);**
  - 继承自uvm_object



## 虚任务
| 类的特性  |  应使用的工厂注册宏 |  示例  | 理由
|-----|-----|------|-------|



## 符号
 | 符号/操作符  |  名称 |  说明  | 示例
|-----|-----|------|-------|
===​|全等比较符|包括X和Z状态的比较，结果为0/1|x === 1'b0结果为0<br>1'bz === 1'bz结果为1
!==​|不全等比较符|与===相反|1'b0 !== 1'bx结果为1
==?​|通配比较符|右侧的X/Z视为通配符|4'b1x0z ==? 4'b1010结果为1
!=?​|通配不等比较符|右侧的X/Z视为通配符|4'b1010 !=? 4'b1x0x结果为0
<<​|流操作符(左)|左移位打包|{<<{data}}反序
<<<​|算术左移|有符号左移|a <<< 2保留符号位
{}​|拼接操作符|位拼接|{a, b, c}  //
{{}}​|复制操作符|重复拼接|{4{a}} 重复4次
++​|自增操作符|递增1|i++或 ++i
+=​|复合赋值|加赋值|a += b等价于 a = a + b
-=​|复合赋值|减赋值|a -= b等价于 a = a - b
*=​|复合赋值|乘赋值|a *= b等价于 a = a * b
%=​|复合赋值|取模赋值|a %= b等价于 a = a % b
^=​|复合赋值|异或赋值|a ^= b等价于 a = a ^ b
inside​|集合成员操作符|检查是否在集合内|x inside {[1:10], 20, 30} //
::​|作用域解析|访问静态成员|class::static_var
->​|类指针成员访问|通过句柄访问成员|p->data
'1​|一填充符|全1填充|reg [7:0] a = '1
'x​|X填充符|全X填充|reg [7:0] a = 'x
always_comb​|组合逻辑块|自动敏感列表|always_comb begin ... end
always_latch​|锁存逻辑块|锁存器推断|always_latch begin ... end
always_ff​|触发器块|时序逻辑|always_ff @(posedge clk) begin ... end
virtual​|虚方法/接口|多态/接口句柄|virtual function/task<br>virtual interface
typedef​|类型定义|创建类型别名|typedef logic [7:0] byte_t;
$sformatf()​|格式化字符串|返回格式化串|$sformatf("val=%0d", 5)
$random()​|有符号随机|生成有符号随机|val = $random();
$clog2()​|对数函数|计算log2向上取整|int bits = $clog2(size);

## 常用UVM方法
| 方法类别  |  方法名 |  所属类  | 作用
|-----|-----|------|-------|
**对象创建**​|type_id::create()|所有注册类|通过工厂创建对象
| |new()|所有类|直接构造函数
**配置管理**​|uvm_config_db::set()|**uvm_config_db**|设置配置
||uvm_config_db::get()||获取配置
**消息报告**​|uvm_info()|**uvm_report_object**|信息消息
||uvm_warning()||警告消息
||uvm_error()||错误消息
**相位控制**​|build_phase()|**uvm_component**|构建阶段
||connect_phase()||连接阶段
||run_phase()||运行阶段
||main_phase()||主阶段
||raise_objection()|**uvm_phase**|延长phase
||drop_objection()||结束phase
**序列控制**​|start()|**uvm_sequence**|启动序列
||body()||序列主体
||start_item()|**uvm_sequence_base**|开始发送事务
||finish_item()||完成发送事务
**驱动器​**|get_next_item()|**uvm_driver**|获取下一个事务
||item_done()||完成事务处理
||seq_item_port||连接sequencer的端口
**监视器**​|write()|**uvm_monitor**|接收事务
||analysis_port||广播事务的端口
||analysis_export|**uvm_subscriber**|接收事务的端口
**记分板​**|write()|**uvm_scoreboard**|接收事务比较
||compare()|自定义|比较事务
**覆盖率**​|sample()|**covergroup**|采样覆盖率
||get_coverage()||获取覆盖率
**工厂**​|set_type_override()|**uvm_factory**|设置类型重写
**寄存器**​|write()|**uvm_reg**|寄存器写操作
||read()||寄存器读操作
**事务​**|copy()|**uvm_object**|复制对象
||compare()||比较对象
||print()||打印对象
||convert2string()||转换为字符串
**随机化**​|randomize()|所有有rand变量的类|随机化对象
**调试辅助**​|get_name()|uvm_object|获取对象名
||get_full_name()|uvm_component|获取完整路径名
||get_type_name()|所有注册类|获取类型名


### phase机制
#### 1. build_phase(uvm_phase phase)
- 含义:
  - 构建阶段，做“**对象/组件创建 + 配置获取**”。
  - 不应有时间消耗（不写 #、@），故一般用`function`。

- 常见用法:
  - 句柄初始化
  - 组件创建：drv = i2c_driver::type_id::create("drv", this);
  - 配置获取：uvm_config_db#(virtual i2c_if)::get(this, "", "vif", vif)

- 作用：
  - 把组件树搭起来；
  - 让每个组件拿到自己所需句柄/参数。

#### 2. connect_phase(uvm_phase phase)
- 含义:
  - 连接阶段，做组件间 TLM 端口连线。
  - 同样是零时间阶段，一般用`function`。

- 常见用法:
  - port.connect(export/imp)

    - ① drv.seq_item_port.connect(sqr.seq_item_export);
    - ② agent.drv.ap.connect(scb.imp)
  - 建立数据流拓扑

- 作用（建立 TLM 通路）：
  - 前者①建立 sequencer->driver 的事务获取通路；
  - 后者②建立 driver->scoreboard 的分析通路。

- drv.seq_item_port.connect(sqr.seq_item_export);  含义：
  - drv.seq_item_port：driver 侧“取事务端口”
  - sqr.seq_item_export：sequencer 侧“供事务导出端”
  - connect(...)：把两端接起来，形成 sequencer -> driver 事务通路
  - 连接后，driver 才能在 run_phase 里执行：
  - 注：seq_item_port.get_next_item(tr) ，若不连接，这句会拿不到事务（仿真行为异常或报错）。

#### 3. run_phase(uvm_phase phase)
- 含义：运行阶段，真正执行有时间行为的验证逻辑（驱动、采样、等待），存在**等待/延时/循环**，故一般用`task`。
- 常见用法：
  - forever 循环
  - @(...) 事件等待
  - **#... 延时**
  - 协议时序驱动
  - objection 控制（通常在 test 里）

- objection 控制
  - phase.raise_objection(this);
    - 通知UVM框架测试开始工作，防止run_phase提前结束
  - phase.drop_objection(this);
    - 通知UVM框架测试工作完成，允许run_phase结束
  - 常见搭配：
    - 启动 sequence 前 raise
    - sequence 完成后 drop

#### 4. 重写构建阶段
```
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.scl_low_extra = 300;
  endfunction
```
- 首先调用父类的build_phase
- 然后修改配置参数
- 在构建阶段修改配置，确保在环境构建前生效

### UVM报告宏
|   宏   |  默认详细程度    |  行为    |  是否终止仿真 |
| ---- | ---- | ---- | :-----: |
uvm_fatal​|UVM_NONE|打印致命错误，立即终止仿真|是
uvm_error​|UVM_NONE|打印错误，增加错误计数，继续仿真|否
uvm_warning​|UVM_MEDIUM|打印警告，增加警告计数，继续仿真|否
uvm_info​|UVM_MEDIUM|打印信息，继续仿真|否
uvm_hint​|UVM_MEDIUM|打印提示信息，继续仿真|否


### UVM常用端口类型协议

#### Analysis（广播发布/订阅）
- 组件类型：uvm_analysis_port / uvm_analysis_export / uvm_analysis_imp
- 关键回调：write(T t)
- 典型场景：
  - monitor/driver 向 scoreboard、coverage 广播事务
  - 一对多分发（同一事务给多个订阅者）

#### 示例（只提取关键代码）

- driver文件：
```
class i2c_driver extends uvm_driver#(i2c_item);
  `uvm_component_utils(i2c_driver)

  uvm_analysis_port#(i2c_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  ap.write(tr);
```

- scoreboard文件：
```
class i2c_scoreboard extends uvm_component;
  `uvm_component_utils(i2c_scoreboard)

  uvm_analysis_imp#(i2c_item, i2c_scoreboard) imp;
  byte unsigned model_mem [byte unsigned];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    imp = new("imp", this);
  endfunction

  function void write(i2c_item tr);
    ...
  endfunction
endclass

```

- env文件：
```
class i2c_env extends uvm_env;
  `uvm_component_utils(i2c_env)

  i2c_agent      agent;
  i2c_scoreboard scb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = i2c_agent::type_id::create("agent", this);
    scb   = i2c_scoreboard::type_id::create("scb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.drv.ap.connect(scb.imp);
  endfunction
endclass

```

**端口协议语句间的联系：**
- uvm_analysis_port#(i2c_item) ap; 

  - 广播发布端，ap为端名

- ap.write(tr); 

  - 负责在 analysis 通道上发布事务，将tr通过ap发布给对应write函数中

- uvm_analysis_imp#(i2c_item, i2c_scoreboard) imp;

  - analysis 导入端（接收端），imp 是 scoreboard 的一个“订阅入口”，用于接收 i2c_item 事务，接收到后，会调用 i2c_scoreboard 里的 write(i2c_item tr)。

- agent.drv.ap.connect(scb.imp);

  - 负责把发布端和接收端连通

- 此端口协议规定回调函数为write(T)

**事件订阅模型：**
- driver 发布消息（ap.write(tr)）
- scoreboard 订阅消息（imp）
- 框架自动通知订阅者（调用 write(tr)）


#### Sequencer-Driver（序列项握手，UVM专用）

- 组件类型：seq_item_port / seq_item_export
- 关键方法（driver侧常用）：
  - get_next_item(req)
  - item_done([rsp])
  - put_response(rsp)（可选）
- 典型场景：
  - driver 从 sequencer 拉取 sequence_item
  - 完成后通知 sequencer，进入下一个事务

#### 示例（只提取关键代码）
- driver文件
```
  task run_phase(uvm_phase phase);
    i2c_item tr;
    vif.init_bus();

    forever begin
      seq_item_port.get_next_item(tr);  // 关键语句
      `uvm_info("DRV", $sformatf("Drive: %s", tr.convert2string()), UVM_MEDIUM)
      case (tr.op)
        I2C_WRITE: do_write(tr);
        I2C_READ : do_read(tr);
      endcase
      ap.write(tr);
      seq_item_port.item_done();  // 关键语句
    end
  endtask
```
- agent文件
```
class i2c_agent extends uvm_component;
  `uvm_component_utils(i2c_agent)

  i2c_sequencer sqr;
  i2c_driver    drv;
  i2c_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sqr = i2c_sequencer::type_id::create("sqr", this);
    drv = i2c_driver::type_id::create("drv", this);
    mon = i2c_monitor::type_id::create("mon", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(sqr.seq_item_export);  // 关键语句
  endfunction
endclass

```

**关键语句解析：**
- **seq_item_port.get_next_item(tr);**
  - UVM sequencer-driver 握手：阻塞等待下一个事务
  - 取到后，tr 指向该事务对象（将一个真实的事务对象句柄赋给 tr，此后才能安全访问其成员）
- **seq_item_port.item_done();**
  - 告诉 sequencer：当前 item 处理完成，可发下一个
- **drv.seq_item_port.connect(sqr.seq_item_export);**
  - drv.seq_item_port：driver 侧“取事务端口”
  - sqr.seq_item_export：sequencer 侧“供事务导出端”
  - connect(...)：把两端接起来，形成 sequencer -> driver 事务通路
  - 连接后，driver 才能在 run_phase 里执行：
  - 注：seq_item_port.get_next_item(tr) ，若不连接，这句会拿不到事务（仿真行为异常或报错）。



### config_db 机制

#### 存入配置
**uvm_config_db#(i2c_cfg)::set(this, "env.agent`*`", "cfg", cfg);**

- **uvm_config_db#(i2c_cfg)**
  - 配置库里这条记录的数据类型是 i2c_cfg（避免类型乱套）。
- **set(...)：往配置库“存一条配置”。**
  - this：以当前 test 组件为起点/作用域去发布这条配置。
  - "env.agent*"：目标路径筛选：env.agent 及其子层级都能看到这条配置（* 是通配）。
  - "cfg"：配置名（key）。下游会用同名 "cfg" 去 get。
  - cfg：真正要传下去的配置对象（里面有 t_high/t_low/scl_low_extra 等参数）。



#### 读取配置
**uvm_config_db#(virtual i2c_if)::get(this, "", "vif", vif);**

- uvm_config_db：UVM配置数据库类
- **#**(virtual i2c_if)：模板参数，指定获取的类型为虚接口
- ::get()：静态方法，从配置数据库获取值
- 参数：(this, "", "vif", vif)
  - this：当前组件
  - ""：空字符串，表示任意实例名
  - "vif"：配置字段名
  - vif：接收值的变量
- 含义：通过uvm_config_db配置数据库寻找类型为 #(virtual i2c_if) 的接口工具，以this（driver）的身份去取件（::get），"" 不管是谁放的，取标签为 "vif" 的物品放到我定义的工具包中（driver的vif变量）。若找不到则报错 "vif not set"。


#### 作用
可用于在层次树中传参，而不是手工层层端口传递。



### 示例
```bash
  virtual i2c_if vif; //class 里不能直接放 interface 实例，需用 `virtual interface` 句柄。
  i2c_cfg cfg;
  uvm_analysis_port#(i2c_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction
```

- **uvm_analysis_port#(i2c_item) ap;**
  - **uvm_analysis_port**：UVM分析端口类
  - **#(i2c_item)**：参数化，指定端口传输的数据类型
  - **ap**：分析端口实例，用于广播驱动的事务到其他组件（如scoreboard）
  - 分析端口支持一对多通信

- **ap = new("ap", this); —— 分析端口实例化**​
  -  **new("ap", this)**：创建分析端口实例
  - **"ap"**：端口名称
  -  **this**：父组件指针（当前driver实例）
  -  分析端口必须在构造函数中实例


```bash
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual i2c_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "vif not set")
    if (!uvm_config_db#(i2c_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = i2c_cfg::type_id::create("cfg");
      `uvm_warning("NOCFG", "cfg not set, use default")
    end
  endfunction
```
- **build_phase(uvm_phase phase); ​**
  -  build_phase：声明 UVM 的构建阶段，UVM组件生命周期阶段之一
  -  在构建阶段获取配置和虚接口
  -  必须调用`super.build_phase(phase)`保证父类构建完成

- **uvm_config_db#(virtual i2c_if)::get(this, "", "vif", vif)** —— 配置数据库获取虚接口​
  -  **uvm_config_db**：UVM配置数据库类
  -  **#(virtual i2c_if)**：模板参数，指定获取的类型为虚接口
  -  **::get()**：静态方法，从配置数据库获取值
  -  参数：**(this, "", "vif", vif)**
     - this：当前组件
     - ""：空字符串，表示任意实例名
     - "vif"：配置字段名
     - vif：接收值的变量
   - 含义：通过**uvm_config_db**配置数据库寻找类型为 **#(virtual i2c_if)** 的接口工具，以**this（driver）**的身份去取件**（::get）**，**""** 不管是谁放的，取标签为 **"vif"** 的物品放到我定义的工具包中（**driver的vif变量**）。若找不到则报错 **"vif not set"**。

- **`uvm_fatal("NOVIF", "vif not set") —— 致命错误宏​**
  -  如果虚接口未设置，报告致命错误并停止仿真
  - "NOVIF"：错误标识符
  - "vif not set"：错误消息


```bash
  task run_phase(uvm_phase phase);	// 声明 UVM 的运行阶段任务
    i2c_item tr;	// 声明一个 i2c_item 类型句柄 tr
    vif.init_bus();	// 调用 virtual interface 中的任务，初始化 I2C 总线空闲状态

    forever begin	// 无限循环，driver 持续从 sequencer 拉取事务并驱动
      seq_item_port.get_next_item(tr);
      `uvm_info("DRV", $sformatf("Drive: %s", tr.convert2string()), UVM_MEDIUM)
      case (tr.op)
        I2C_WRITE: do_write(tr);	// 把事务转换成 I2C 写时序
        I2C_READ : do_read(tr);
      endcase
      ap.write(tr);		// 通过 analysis port 发布该事务给 scoreboard/其它订阅者
      seq_item_port.item_done();	// 告诉 sequencer：当前 item 处理完成，可发下一个
    end
  endtask
```

- **task run_phase(uvm_phase phase);**
  - 声明 UVM 的运行阶段任务。
  - uvm_phase phase 是阶段对象句柄，用于 objection 等阶段控制。
  
- **i2c_item tr;**
  - 声明一个 i2c_item 类型句柄 tr。
  - 之后通过 seq_item_port.get_next_item(tr) 获取实际事务对象。

- **seq_item_port.get_next_item(tr);**
    - UVM sequencer-driver 握手：阻塞等待下一个事务
    - 取到后，`tr` 指向该事务对象（将一个真实的事务对象句柄赋给 tr，此后才能安全访问其成员）
- **`uvm_info("DRV", $sformatf("Drive: %s", tr.convert2string()), UVM_MEDIUM)**
    - 打印日志
    - `$sformatf` ：格式化字符串并返回结果；`tr.convert2string()` 是 `i2c_item` 的成员函数
    - `UVM_MEDIUM`：中等详细程度（默认）

  此外还有UVM_NONE（关键错误）、UVM_LOW（低详细程度）、UVM_HIGH（高详细程度）、UVM_FULL（最高详细程度）、UVM_DEBUG（调试级别）
-->
