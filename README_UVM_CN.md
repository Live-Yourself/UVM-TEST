# I2C UVM 学习与实践（基于当前工程）

本文目标：帮助你从“会跑仿真”进阶到“会设计验证流程”。

## 1) UVM 核心机制（结合本工程）

### phase（分阶段执行）
- `build_phase`：创建组件，读取配置。
- `connect_phase`：连接端口（TLM）。
- `run_phase`：驱动事务、采样、检查。

工程映射：
- test 里创建 `env`、配置 `cfg`。
- agent 里连接 `driver <-> sequencer`。
- run 时 sequence 发 item，driver 驱动 I2C 引脚。

### factory（可替换创建）
通过 `type_id::create()` 创建组件/对象，而不是 `new` 硬编码。
优点：后续可 override（同接口换实现，不改原代码）。

### config_db（跨层传参）
用于把配置从高层传到低层：
- top 传 `virtual interface` 到 agent/driver。
- test 传 `i2c_cfg` 到 driver。

### sequence / sequencer / driver
- `sequence`：定义“做什么事务”（读/写/非法地址）。
- `sequencer`：调度事务。
- `driver`：把事务变成 pin 级时序（start/stop/bit/byte）。

---

## 2) 各文件用途

- [sim/uvm/if/i2c_if.sv](sim/uvm/if/i2c_if.sv)：I2C 接口与开漏总线模型。
- [sim/uvm/test/i2c_cfg.sv](sim/uvm/test/i2c_cfg.sv)：时序配置对象。
- [sim/uvm/item/i2c_item.sv](sim/uvm/item/i2c_item.sv)：事务字段定义。
- [sim/uvm/seq/i2c_seqs.sv](sim/uvm/seq/i2c_seqs.sv)：激励序列（smoke/illegal/stretch）。
- [sim/uvm/agent/i2c_driver.sv](sim/uvm/agent/i2c_driver.sv)：I2C 驱动器。
- [sim/uvm/agent/i2c_monitor.sv](sim/uvm/agent/i2c_monitor.sv)：基础监控（START/STOP）。
- [sim/uvm/seq/i2c_sequencer.sv](sim/uvm/seq/i2c_sequencer.sv)：事务调度器。
- [sim/uvm/agent/i2c_agent.sv](sim/uvm/agent/i2c_agent.sv)：封装 sequencer/driver/monitor。
- [sim/uvm/env/i2c_scoreboard.sv](sim/uvm/env/i2c_scoreboard.sv)：结果检查。
- [sim/uvm/env/i2c_env.sv](sim/uvm/env/i2c_env.sv)：环境集成。
- [sim/uvm/test/i2c_tests.sv](sim/uvm/test/i2c_tests.sv)：测试类定义。
- [sim/uvm/pkg/i2c_pkg.sv](sim/uvm/pkg/i2c_pkg.sv)：统一打包 include。
- [sim/tb/tb_uvm_top.sv](sim/tb/tb_uvm_top.sv)：仿真顶层。

### 2.1 各 UVM 文件之间的关联（重点）

#### A. 编译与包含关系
- [sim/tb/tb_uvm_top.sv](sim/tb/tb_uvm_top.sv) import [sim/uvm/pkg/i2c_pkg.sv](sim/uvm/pkg/i2c_pkg.sv)。
- [sim/uvm/pkg/i2c_pkg.sv](sim/uvm/pkg/i2c_pkg.sv) 通过 `include` 组织其余 class 文件（cfg/item/sequencer/seqs/driver/monitor/agent/scoreboard/env/tests）。
- [sim/uvm/if/i2c_if.sv](sim/uvm/if/i2c_if.sv) 在 top 中实例化为 `i2c_vif`，供 driver/monitor 访问。

#### B. 配置下发关系（config_db）
- 在 [sim/tb/tb_uvm_top.sv](sim/tb/tb_uvm_top.sv) 中，`virtual i2c_if` 通过 `uvm_config_db` 下发到 `uvm_test_top.env.agent*`。
- 在 [sim/uvm/test/i2c_tests.sv](sim/uvm/test/i2c_tests.sv) 中，test 创建 `i2c_cfg`，再下发到 `env.agent*`。
- 在 [sim/uvm/agent/i2c_driver.sv](sim/uvm/agent/i2c_driver.sv) 与 [sim/uvm/agent/i2c_monitor.sv](sim/uvm/agent/i2c_monitor.sv) 中分别 `get()` 到 `vif`；driver 还会 `get()` 到 `cfg`。

#### C. 组件层级关系（build）
- test（[sim/uvm/test/i2c_tests.sv](sim/uvm/test/i2c_tests.sv)）创建 env（[sim/uvm/env/i2c_env.sv](sim/uvm/env/i2c_env.sv)）。
- env 创建 agent 与 scoreboard（[sim/uvm/agent/i2c_agent.sv](sim/uvm/agent/i2c_agent.sv)、[sim/uvm/env/i2c_scoreboard.sv](sim/uvm/env/i2c_scoreboard.sv)）。
- agent 创建 sequencer/driver/monitor（[sim/uvm/seq/i2c_sequencer.sv](sim/uvm/seq/i2c_sequencer.sv)、[sim/uvm/agent/i2c_driver.sv](sim/uvm/agent/i2c_driver.sv)、[sim/uvm/agent/i2c_monitor.sv](sim/uvm/agent/i2c_monitor.sv)）。

#### D. 事务流关系（run）
1. sequence 定义在 [sim/uvm/seq/i2c_seqs.sv](sim/uvm/seq/i2c_seqs.sv)，产生 `i2c_item`（定义在 [sim/uvm/item/i2c_item.sv](sim/uvm/item/i2c_item.sv)）。
2. test 启动 sequence：`seq.start(env.agent.sqr)`（见 [sim/uvm/test/i2c_tests.sv](sim/uvm/test/i2c_tests.sv)）。
3. sequencer 把 item 发给 driver（连接发生在 [sim/uvm/agent/i2c_agent.sv](sim/uvm/agent/i2c_agent.sv)）。
4. driver 在 [sim/uvm/agent/i2c_driver.sv](sim/uvm/agent/i2c_driver.sv) 中将 item 转成 I2C 引脚时序（通过 `vif` 操作 SCL/SDA）。
5. driver 通过 analysis port 把事务写给 scoreboard（连接在 [sim/uvm/env/i2c_env.sv](sim/uvm/env/i2c_env.sv)）。
6. scoreboard 在 [sim/uvm/env/i2c_scoreboard.sv](sim/uvm/env/i2c_scoreboard.sv) 中做参考模型比对并报错/通过。

#### E. 一句话理解整套关系
可以把当前工程理解成：
`tests -> seqs -> sequencer -> driver -> DUT`（激励链）
与
`driver -> scoreboard`（检查链）
再由
`tb_top/config_db`（配置链）
把 interface 与参数串起来。

---

## 3) UVM 验证流程（你要掌握的主线）

1. 顶层初始化
- 实例化 DUT + interface
- 时钟复位
- 用 `config_db` 下发 `vif`
- `run_test()` 启动 UVM

2. 测试构建
- base test 创建 `env`
- 创建 `cfg` 并下发给 agent/driver

3. 激励执行
- test 在 `run_phase` 启动某个 sequence
- sequence 产生 `i2c_item`
- driver 执行 I2C 引脚时序

4. 检查
- scoreboard 接收事务并和参考模型比对
- 观察 `UVM_ERROR/UVM_FATAL`

5. 结束
- objection 归零，仿真退出

---

## 4) 三个现成测试的学习意义

- `i2c_smoke_test`：最小闭环（写后读）。
- `i2c_illegal_addr_test`：无效地址行为检查。
- `i2c_stretch_test`：拉长低电平，验证时序鲁棒性。

建议顺序：先 smoke，再 illegal，再 stretch。

---

## 5) 运行方法

```bash
cd sim/work
bash run_uvm.sh i2c_smoke_test
bash run_uvm.sh i2c_illegal_addr_test
bash run_uvm.sh i2c_stretch_test
```

---

## 6) 下一步如何进阶（非常重要）

### A. 提升 monitor
现在 monitor 只识别 START/STOP。下一步应升级为“字节流解码 monitor”。

### B. 提升 scoreboard
目前 scoreboard 用 driver 回传事务检查。进阶应改为“基于 monitor 解码流检查”，避免自测自证。

### C. 覆盖率
增加 covergroup：
- 地址覆盖
- 读写方向覆盖
- ACK/NACK 覆盖
- 重复起始覆盖
- 交叉覆盖（地址 × 方向 × ACK）

### D. 协议断言（SVA）
例如：
- SCL 高电平期间 SDA 不应随意变化（除 START/STOP）
- ACK 采样窗口合法
- START/STOP 触发条件合法

完成以上四步后，你就进入“可用于项目回归”的 UVM 验证框架阶段。

---

## 7) 与原有 rtl/sim 框架对齐后的 UVM 目录与流程

你原先的流程是：
- [rtl](rtl)：DUT RTL。
- [sim/tb](sim/tb)：仿真顶层。
- [sim/tc](sim/tc)：激励文件。
- [sim/work](sim/work)：编译脚本与 filelist。
- [sim/sim_result](sim/sim_result)：波形、覆盖率、日志。

引入 UVM 后，建议保持原框架不变，只在 [sim](sim) 下新增 UVM 分层目录：

- [sim/uvm](sim/uvm)：UVM 总目录。
	- [sim/uvm/if](sim/uvm/if)：接口与时钟复位绑定（放 `i2c_if.sv`）。
	- [sim/uvm/item](sim/uvm/item)：事务对象（放 `i2c_item.sv`）。
	- [sim/uvm/seq](sim/uvm/seq)：sequence 与 virtual sequence（放 `i2c_seqs.sv`）。
	- [sim/uvm/agent](sim/uvm/agent)：`i2c_driver.sv`、`i2c_monitor.sv`、`i2c_sequencer.sv`、`i2c_agent.sv`。
	- [sim/uvm/env](sim/uvm/env)：`i2c_scoreboard.sv`、`i2c_env.sv`。
	- [sim/uvm/test](sim/uvm/test)：`i2c_cfg.sv`、`i2c_tests.sv`。
	- [sim/uvm/pkg](sim/uvm/pkg)：`i2c_pkg.sv`（统一 `include/import`）。
- [sim/tb](sim/tb)：保留顶层，但建议新增 UVM 顶层（放 `tb_uvm_top.sv`）。
- [sim/work](sim/work)：新增 UVM filelist 与 run 脚本（例如 `uvm_filelist.f`、`run_uvm.sh` 或 `run_uvm.bat`）。
- [sim/sim_result](sim/sim_result)：按 test 名分子目录保存结果。
	- [sim/sim_result/i2c_smoke_test](sim/sim_result/i2c_smoke_test)
	- [sim/sim_result/i2c_illegal_addr_test](sim/sim_result/i2c_illegal_addr_test)
	- [sim/sim_result/i2c_stretch_test](sim/sim_result/i2c_stretch_test)

### 7.1 与原 tc 目录的关系
- 传统 [sim/tc](sim/tc) 的“激励文件”在 UVM 中由 `sequence`/`test` 替代。
- 建议：
	- 过渡期保留 [sim/tc](sim/tc)（便于与旧用例对比）。
	- 新增场景统一写入 [sim/uvm/seq](sim/uvm/seq) 与 [sim/uvm/test](sim/uvm/test)。

### 7.2 UVM 仿真流程（对齐你的原 work 驱动方式）
1. 在 [sim/work](sim/work) 执行 UVM 编译脚本。
2. 脚本读取 UVM filelist（含 RTL + UVM + tb_uvm_top）。
3. 通过 `+UVM_TESTNAME=<test_name>` 选择测试。
4. 运行后将日志、FSDB、coverage 输出到 [sim/sim_result](sim/sim_result) 对应 test 子目录。
5. 用同一脚本循环不同 test，形成回归。

### 7.3 当前工程状态
当前工程已完成迁移：UVM 相关源码位于 [sim/uvm](sim/uvm)，
顶层位于 [sim/tb](sim/tb)，编译运行脚本位于 [sim/work](sim/work)。
