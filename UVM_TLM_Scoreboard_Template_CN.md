# UVM 学习总结 + “Scoreboard 双通道 + 事务队列配对”最小模板

本文把我们前面讨论的关键点做集中总结，并给出可直接参考的最小模板。

---

## 1. 关键概念速记（结合你当前工程）

## 1.1 句柄与对象
- `i2c_item tr;` 只是声明句柄（类型已知，但对象可能还没分配）。
- 运行时要先拿到有效对象（例如 `get_next_item(tr)` 或 `type_id::create`），再安全访问成员。
- 编译期“可写 `tr.xxx`”是因为类型已知；运行期“能否访问成功”取决于是否为 `null`。

## 1.2 Factory 机制
- 作用：创建解耦、便于 override。
- 三步：
  1) `uvm_*_utils` 注册
  2) `type_id::create` 创建
  3) test 层可做 override
- 你工程里：`agent` 用 `type_id::create` 创建 `sqr/drv/mon`。

## 1.3 三个 phase（常见职责）
- `build_phase(uvm_phase phase)`：创建组件、取 config（零时间，`function`）。
- `connect_phase(uvm_phase phase)`：连接 TLM 端口（零时间，`function`）。
- `run_phase(uvm_phase phase)`：时序行为（有等待/延时，`task`）。

## 1.4 Analysis 通道
- 发布端：`uvm_analysis_port#(T)`，调用 `write(T t)` 发布。
- 接收端：`uvm_analysis_imp#(T, IMP)`，必须在 `IMP` 里实现 `function void write(T t)`。
- `connect` 后由 UVM 框架自动分发并回调接收端 `write`。
- 不是 driver “直接调用” scoreboard 的 `write`，而是经 TLM 广播机制转发。

## 1.5 “一次只能处理一个事务吗？”
- 单次回调 `write(T t)` 是一个事务对象。
- 但系统可高吞吐：多次回调、多个订阅者、内部队列缓存、异步配对比对。

---

## 2. 最小模板：Scoreboard 双通道 + 事务队列配对

下面模板演示：
- 通道 A：期望事务（expected）
- 通道 B：实际事务（actual）
- 各自进队列
- 在 `run_phase` 按序配对比较

> 说明：为便于学习，模板用两个 `analysis_imp`（通过后缀宏区分两个 `write` 回调）。

```systemverilog
`uvm_analysis_imp_decl(_exp)
`uvm_analysis_imp_decl(_act)

class my_item extends uvm_sequence_item;
  `uvm_object_utils(my_item)

  rand bit [7:0] id;
  rand bit [7:0] data;

  function new(string name = "my_item");
    super.new(name);
  endfunction
endclass

class my_scoreboard extends uvm_component;
  `uvm_component_utils(my_scoreboard)

  // 双通道接收端
  uvm_analysis_imp_exp#(my_item, my_scoreboard) exp_imp;
  uvm_analysis_imp_act#(my_item, my_scoreboard) act_imp;

  // 双队列缓存
  my_item exp_q[$];
  my_item act_q[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    exp_imp = new("exp_imp", this);
    act_imp = new("act_imp", this);
  endfunction

  // 通道A回调：接收期望事务
  function void write_exp(my_item t);
    exp_q.push_back(t);
    `uvm_info("SCB", $sformatf("EXP in: id=%0d data=0x%02h", t.id, t.data), UVM_LOW)
  endfunction

  // 通道B回调：接收实际事务
  function void write_act(my_item t);
    act_q.push_back(t);
    `uvm_info("SCB", $sformatf("ACT in: id=%0d data=0x%02h", t.id, t.data), UVM_LOW)
  endfunction

  // 异步配对线程
  task run_phase(uvm_phase phase);
    my_item exp_t, act_t;

    forever begin
      wait (exp_q.size() > 0 && act_q.size() > 0);

      exp_t = exp_q.pop_front();
      act_t = act_q.pop_front();

      // 你可以改成按 id 匹配，这里先做最小顺序匹配
      if (act_t.id !== exp_t.id || act_t.data !== exp_t.data) begin
        `uvm_error("SCB", $sformatf(
          "MISMATCH exp(id=%0d,data=0x%02h) act(id=%0d,data=0x%02h)",
          exp_t.id, exp_t.data, act_t.id, act_t.data))
      end
      else begin
        `uvm_info("SCB", $sformatf(
          "MATCH id=%0d data=0x%02h", act_t.id, act_t.data), UVM_MEDIUM)
      end
    end
  endtask
endclass
```

---

## 3. 如何连接双通道（env 示例）

```systemverilog
class my_env extends uvm_env;
  `uvm_component_utils(my_env)

  my_scoreboard scb;
  // 假设：exp_mon 发布期望，act_mon 发布实际
  my_monitor exp_mon;
  my_monitor act_mon;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    scb     = my_scoreboard::type_id::create("scb", this);
    exp_mon = my_monitor::type_id::create("exp_mon", this);
    act_mon = my_monitor::type_id::create("act_mon", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    exp_mon.ap.connect(scb.exp_imp); // 期望流 -> exp_imp
    act_mon.ap.connect(scb.act_imp); // 实际流 -> act_imp
  endfunction
endclass
```

---

## 4. 模板扩展建议（从“能跑”到“可回归”）

1) 匹配策略
- 当前是 FIFO 顺序匹配。
- 实战常改为按 `id/tag/addr` 关联匹配（乱序容忍）。

2) 超时与积压检查
- 增加 watchdog；若 `exp_q`/`act_q` 长期不平衡，报错提示卡死或丢包。

3) 事务复制
- 若上游对象可能被后续修改，建议在 `write_*` 里 clone 后再入队。

4) 覆盖率与统计
- 在比对通过处做 coverage sample，统计匹配率、场景分布。

5) 结束时检查
- 在 `check_phase` 或 `final_phase` 检查队列是否清空，避免“未比对残留事务”。

---

## 5. 与你当前 I2C 工程对应关系

- 你当前 [uvm/i2c_scoreboard.sv](uvm/i2c_scoreboard.sv) 是“单通道 + 内部参考模型”模式。
- 若升级到双通道模式，可让：
  - 一路来自“期望模型/参考监视器”
  - 一路来自“DUT实际监视器”
- 再在 scoreboard 内完成队列配对，避免自测自证。

这样会更接近可回归签核的验证架构。

---

## 6. 结合当前工程代码的 UVM 核心机制详解

下面按“机制 -> 工程中的语句 -> 作用”三段式说明。

### 6.1 Phase 机制（UVM 生命周期骨架）

UVM 把验证过程分成多个 phase。你当前工程最常用的是：
- `build_phase`
- `connect_phase`
- `run_phase`

#### A) build_phase：创建与配置获取（零时间）

工程语句示例：
- agent 内创建组件：
  - `sqr = i2c_sequencer::type_id::create("sqr", this);`
  - `drv = i2c_driver::type_id::create("drv", this);`
  - `mon = i2c_monitor::type_id::create("mon", this);`
- driver 内取配置：
  - `uvm_config_db#(virtual i2c_if)::get(this, "", "vif", vif)`
  - `uvm_config_db#(i2c_cfg)::get(this, "", "cfg", cfg)`

作用：
- 把组件树搭起来；
- 让每个组件拿到自己所需句柄/参数。

为什么是 `function void build_phase(uvm_phase phase)`：
- build 是零时间阶段，不应包含 `#delay`、`@event`、`wait` 等阻塞操作。

#### B) connect_phase：建立 TLM 通路（零时间）

工程语句示例：
- `drv.seq_item_port.connect(sqr.seq_item_export);`
- `agent.drv.ap.connect(scb.imp);`

作用：
- 前者建立 sequencer->driver 的事务获取通路；
- 后者建立 driver->scoreboard 的分析通路。

为什么是 `function void connect_phase(uvm_phase phase)`：
- 本质是“连线”，也是零时间动作。

#### C) run_phase：执行时序行为（耗时）

工程语句示例：
- driver：
  - `forever begin`
  - `seq_item_port.get_next_item(tr);`
  - `case (tr.op) ...`
  - `ap.write(tr);`
  - `seq_item_port.item_done();`
- monitor：`@(vif.sda or vif.scl)` 监听总线变化。
- test：`phase.raise_objection(this); ... phase.drop_objection(this);`

作用：
- 真正驱动 DUT、采样 DUT、完成检查闭环。

为什么是 `task run_phase(uvm_phase phase)`：
- run 里需要等待、延时、循环，必须是 `task`。

---

### 6.2 Factory 机制（创建解耦与可替换）

Factory 的核心：
- 不写死 `new 某具体类`；
- 统一 `type_id::create`；
- 未来可通过 override 替换实现。

工程语句示例：
- 注册：
  - `` `uvm_component_utils(i2c_agent) ``
  - `` `uvm_component_utils(i2c_driver) ``
  - `` `uvm_object_utils(i2c_item) ``
- 创建：
  - `i2c_driver::type_id::create("drv", this)`
  - `i2c_item::type_id::create("wr")`

作用：
- 你可在不改 agent 的前提下，把 `i2c_driver` 替换为 `i2c_driver_dbg`。

---

### 6.3 config_db 机制（跨层配置下发）

`uvm_config_db` 用于在层次树中传参，而不是手工层层端口传递。

工程链路：
1. top 下发 `vif`
   - `uvm_config_db#(virtual i2c_if)::set(null, "uvm_test_top.env.agent*", "vif", i2c_vif);`
2. test 下发 `cfg`
   - `uvm_config_db#(i2c_cfg)::set(this, "env.agent*", "cfg", cfg);`
3. driver/monitor 在 build_phase 获取
   - `get(..., "vif", vif)`
   - `get(..., "cfg", cfg)`

作用：
- 解耦组件依赖；
- 提升复用性；
- 支持 test 层动态控制时序参数。

---

### 6.4 Sequence / Sequencer / Driver 事务握手机制

工程语句示例：
- sequence 产生 item：
  - `start_item(wr); ... finish_item(wr);`
- driver 消费 item：
  - `seq_item_port.get_next_item(tr);`
  - `seq_item_port.item_done();`

含义：
- sequence 定义“要做什么”；
- driver实现“怎么在引脚上做”；
- sequencer 负责中间调度仲裁。

---

### 6.5 Objection 机制（仿真结束控制）

工程语句示例（test 的 run_phase）：
- `phase.raise_objection(this);`
- `... seq.start(env.agent.sqr); ...`
- `phase.drop_objection(this);`

作用：
- 防止 run_phase 过早结束；
- 使仿真生命周期与测试激励一致。

---

### 6.6 Monitor / Scoreboard / Reference Model 机制

你当前工程里：
- driver 通过 `ap.write(tr)` 发布事务；
- scoreboard 通过 `imp` 接收事务并在 `write(i2c_item tr)` 内比对；
- `model_mem` 作为参考模型存储写入值，读事务时查表比对。

作用：
- 把“驱动”和“检查”分离；
- 检查逻辑集中在 scoreboard，可统一统计报错。

---

## 7. TLM 的含义与作用（重点）

### 7.1 TLM 是什么

TLM = Transaction-Level Modeling（事务级建模/通信）。

不是按位线网级“每拍连线”，而是按“事务对象”在组件间传递信息。

例如：
- 不是传 `scl/sda` 每一拍细节给 scoreboard；
- 而是传一个 `i2c_item`（包含地址、方向、数据、ACK等）。

### 7.2 TLM 在本工程中的价值

1) 解耦
- driver 不需要知道 scoreboard 内部细节。

2) 广播
- analysis 端口可一对多连接，后续可同时接 coverage collector。

3) 可扩展
- 可以替换 scoreboard、增加中间 FIFO、增加双通道比对，而不改 driver 主逻辑。

4) 可维护
- 事务对象可打印、统计、存档，调试效率高。

### 7.3 本工程已使用的 TLM 形态

- Analysis TLM：
  - 发布端：`uvm_analysis_port#(i2c_item) ap`
  - 接收端：`uvm_analysis_imp#(i2c_item, i2c_scoreboard) imp`
  - 连接：`agent.drv.ap.connect(scb.imp)`
  - 回调：`function void write(i2c_item tr)`

### 7.4 你可继续扩展的 TLM 方向

1) 单通道 -> 双通道
- 一个通道传 expected，一个通道传 actual，在 scoreboard 用队列配对。

2) 增加 FIFO 解耦
- monitor 与 scoreboard 中间加 `uvm_tlm_fifo`。

3) 一对多广播
- driver/monitor 同时连 scoreboard 与 coverage collector。

---

## 8. 把这些机制串成一条完整执行链

1. `tb_uvm_top` 下发 `vif`，`run_test()` 启动。
2. test 在 build 中创建 env/cfg 并下发 cfg。
3. env/agent 在 build 中创建组件，在 connect 中连接事务通道。
4. run 时 sequence 产出 item，driver 获取并驱动 I2C。
5. driver 通过 analysis 端口发布事务，scoreboard 自动回调 `write` 比对。
6. test 通过 objection 控制测试结束。

这就是当前工程完整的 UVM 验证闭环。
