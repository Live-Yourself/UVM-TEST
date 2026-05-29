# I2C Slave UVM 验证计划（VPlan）

## 1. 验证对象与范围
- DUT 顶层：`i2c_slave_top`
- 子模块：`i2c_rx_fsm`、`i2c_shift_reg`、`reg_file`、`scl_sda_filter`
- 协议范围：I2C 7-bit 地址模式、单主机、从设备寄存器读写

## 2. 需求分解（Feature -> Requirement）
- R1：合法地址写（`dev_addr==0x42`）应 ACK，并写入寄存器
- R2：合法地址读应 ACK，并返回寄存器数据
- R3：非法地址写/读应 NACK 或不进入有效数据路径
- R4：连续写地址自增、连续读地址自增正确
- R5：重复起始（Repeated START）读流程正确
- R6：STOP 后状态机回到 IDLE
- R7：SCL 拉低延长（clock stretch 环境）下时序稳定
- R8：寄存器复位值为 0

## 3. 当前测试与映射
- `i2c_smoke_test`：R1/R2 基础路径
- `i2c_illegal_addr_test`：R3 非法写/NACK
- `i2c_illegal_read_test`：R3 非法读/NACK
- `i2c_stretch_test`：R7
- `i2c_rand_burst_test`：R1/R2/R4（随机地址+长度）
- `i2c_cov_closure_test`：R1~R4 的矩阵化高密度回归

## 4. 覆盖率策略
### 4.1 功能覆盖（scoreboard）
- V1（刺激空间）：地址桶、长度桶、illegal_read
- V2（行为桶）：legal/illegal 读写、ACK/NACK、rd_match

### 4.2 代码覆盖（URG）
- line/cond/fsm/tgl/branch，按 nightly 合并

## 5. 回归分层策略
- Gate层（最小守门）：`smoke`、`illegal_addr`、`illegal_read`、`stretch`
- Coverage层（覆盖拉升）：`cov_closure` + `rand_burst`矩阵
- Nightly：Gate全量 + Coverage主预算

## 6. 当前工程评估
### 6.1 已完成较好
- UVM 基础架构齐全（agent/env/scoreboard/tests）
- V2 bucket 已能稳定统计并显示
- 并行数据库损坏问题已通过 run 独立工作目录修复

### 6.2 仍有缺口
- Monitor 已支持总线 transaction 重建与统计，但尚未切换为 scoreboard 主数据源
- 缺少 protocol assertions（如 START/STOP 合法性、ACK 位时序）
- 缺少异常场景：复位中断事务、地址回卷（0xFF->0x00）、随机 STOP 注入
- 缺少 coverage exclusion 文档（哪些 bin/cross 设计上不需要）

## 7. 下一阶段执行清单（按优先级）
1) 将 monitor 的重建 transaction 接入 scoreboard（与 driver 路径做一致性对照）
2) 新增 SVA：关键协议时序断言（至少 6 条）
3) 新增 stress 场景：随机 reset/stop 注入
4) 扩展 `i2c_rand_burst_seq`：可控非法比例 + 轮次
5) 建立 closure 签核门槛（见第8节）

## 8. 签核建议（可执行）
- 功能覆盖：V2 全绿，且连续 3 轮 nightly 保持
- 覆盖拉升：`i2c_cov_closure_test` 最新 fcov >= 90%
- 代码覆盖：FSM/branch >= 95%，line >= 90%
- 稳定性：nightly 连续 5 次 pass rate >= 98%

## 9. 说明：为什么 `rand_burst` 可能长期不涨
- 当前覆盖模型更关注路径类型和桶命中，不关注数据值本身
- 仅改变 seed 往往只是“换数据”，不是“换路径”
- 因此需要“可控非法比例/轮次/矩阵约束”来强制走新路径
