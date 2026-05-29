# I2C_Slave 设计规格说明书

## 1. 模块概述
I2C_Slave 为一个寄存器映射型 I2C 从设备实现，顶层模块为 `i2c_slave_top`。设计目标如下：
- 实现 7-bit 设备地址识别与 ACK 响应。
- 支持寄存器地址指针写入。
- 支持寄存器连续写与连续读（地址自动递增）。
- 使用开漏模式控制 SDA 输出，仅在需要输出 0 时驱动总线。
- 采用模块化架构（同步、协议控制、移位、存储解耦）。

支持的基本事务：
- 写事务：`START -> DEV_ADDR+W -> REG_ADDR -> DATA... -> STOP`
- 读事务：`START/Repeated START -> DEV_ADDR+R -> DATA... -> NACK -> STOP`

## 2. 顶层模块接口

### 2.1 输入端口列表（名称、位宽、方向、功能说明）
顶层模块：`i2c_slave_top`

| 名称 | 位宽 | 方向 | 功能说明 |
|---|---:|---|---|
| `clk` | 1 | 输入 | 系统时钟，所有时序逻辑工作时钟 |
| `rst_n` | 1 | 输入 | 低有效异步复位 |
| `scl` | 1 | 输入 | I2C 串行时钟输入 |
| `sda_in` | 1 | 输入 | I2C 串行数据输入（采样值） |

### 2.2 输出端口列表

| 名称 | 位宽 | 方向 | 功能说明 |
|---|---:|---|---|
| `sda_oe` | 1 | 输出 | SDA 开漏输出使能，高电平表示驱动低电平，低电平表示释放总线 |

### 2.3 参数定义

| 参数名 | 位宽 | 默认值 | 说明 |
|---|---:|---|---|
| `DEV_ADDR` | 7 | `7'h42` | I2C 从设备地址 |

## 3. 顶层功能行为

### 3.1 操作模式及切换条件
顶层通过 `i2c_rx_fsm` 实现协议模式切换，核心模式如下：
- `IDLE`：等待 `START`。
- `ADDR`：接收地址 + R/W。
- `REG`：接收寄存器地址指针。
- `WRITE`：接收写数据并写入寄存器。
- `READ`：发送寄存器数据给主机。

切换关键条件：
- 检测到 `start_cond`：进入地址接收模式。
- 地址匹配且 `R/W=0`：进入寄存器地址/写模式。
- 地址匹配且 `R/W=1`：进入读模式。
- 检测到 `stop_cond`：返回 `IDLE`。
- 读模式下主机 `NACK`：结束读传输并回到 `IDLE`。

### 3.2 输入输出映射关系
- 输入采样链路：`scl/sda_in -> scl_sda_filter -> scl_sync/sda_sync`
- 控制链路：`scl_sync/sda_sync/edge_detect -> i2c_rx_fsm`
- 接收数据链路：`sda_sync -> i2c_shift_reg(data_out) -> i2c_rx_fsm(rx_byte)`
- 写寄存器链路：`i2c_rx_fsm(reg_we/reg_waddr/reg_wdata) -> reg_file`
- 读寄存器链路：`reg_file(rdata) -> i2c_rx_fsm(tx_load_data) -> i2c_shift_reg(shift_out)`
- 输出使能链路：`ack_drive + tx_drive_en + shift_out -> sda_oe`

开漏输出公式：
$$
	exttt{sda\_oe} = \texttt{ack\_drive} \lor (\texttt{tx\_drive\_en} \land \neg \texttt{shift\_out})
$$

### 3.3 时序要求（建立时间、保持时间、延迟周期数）
本 RTL 未显式参数化 setup/hold 数值，约束应由 SoC 顶层时序约束文件定义。基于实现可归纳以下要求：

1. I2C 协议采样边沿
  - 接收数据在 `scl_rise` 时采样（由状态机控制 `rx_shift_en`）。
  - 发送数据在 `scl_fall` 推进（`tx_shift_en = scl_fall`）。

2. ACK 时序
  - ACK 驱动在 `scl_fall` 预置，在 ACK 位期间通过 `sda_oe` 生效。

3. 同步延迟
  - `scl/sda` 经双触发同步后再参与边沿判断，存在同步管线延迟（典型 1~2 个 `clk` 周期量级）。

4. 设计使用前提
  - 需保证系统 `clk` 足够高，以可靠捕获 I2C `scl/sda` 变化并完成边沿/起止条件识别。

### 3.4 复位行为
- 所有时序模块均采用 `negedge rst_n` 异步复位。
- 复位后行为：
  - FSM 回到 `ST_IDLE`。
  - 地址指针 `reg_addr` 清零。
  - `reg_file` 全部 256 字节清零。
  - `ack_drive/tx_drive` 关闭，SDA 默认释放。

## 4. 子模块架构

### 4.1 子模块清单及职责划分
- `scl_sda_filter`：输入同步模块，对 `scl/sda` 做双触发同步，降低亚稳态传播风险。
- `i2c_rx_fsm`：协议核心控制模块，完成状态机跳转、ACK 决策、读写控制。
- `i2c_shift_reg`：8-bit 移位寄存器，完成串并/并串转换。
- `reg_file`：256x8 存储阵列，提供同步写、异步读寄存器访问。

### 4.2 子模块间连接关系
1. Top -> `scl_sda_filter`
  - 输入：`clk`, `rst_n`, `scl`, `sda_in`
  - 输出：`scl_sync`, `sda_sync`

2. Top -> `i2c_rx_fsm`
  - 控制输入：`start_cond`, `stop_cond`, `scl_sync`, `scl_rise`, `scl_fall`, `sda_sync`
  - 数据输入：`rx_byte[7:0]`（来自移位寄存器），`reg_rdata[7:0]`（来自寄存器文件）
  - 参数输入：`dev_addr[6:0]`
  - 控制输出：`rx_shift_en`, `tx_shift_en`, `tx_load_en`, `ack_drive`, `tx_drive_en`, `reg_we`
  - 数据输出：`tx_load_data[7:0]`, `reg_waddr[7:0]`, `reg_wdata[7:0]`, `reg_addr[7:0]`

3. Top -> `i2c_shift_reg`
  - `shift_en = rx_shift_en | tx_shift_en`
  - `shift_in = rx_shift_en ? sda_sync : 1'b1`
  - `load_en = tx_load_en`
  - `load_data = tx_load_data`
  - 输出：`shift_out`（发往开漏逻辑）、`data_out`（回送 FSM）

4. Top -> `reg_file`
  - 写接口：`we`, `waddr`, `wdata`
  - 读接口：`raddr`, `rdata`

5. 子模块输出汇聚到 Top
  - `ack_drive` 与 `tx_drive_en/shift_out` 汇聚为最终 `sda_oe`。

### 4.3 数据流路径图（文字描述）
- 写路径：
  - 输入 `sda_in` → [`scl_sda_filter` 同步] → [`i2c_shift_reg` 接收移位] → [`i2c_rx_fsm` 字节解释/地址判定] → [`reg_file` 写入]
- 读路径：
  - [`reg_file` 读出] → [`i2c_rx_fsm` 组织待发送字节] → [`i2c_shift_reg` 串行输出] → Top 开漏控制 → `sda_oe`

## 5. 各子模块详细规格

### 5.1 `scl_sda_filter` 详细行为
- 内部采用 2-bit 移位打拍寄存器 `scl_ff/sda_ff`。
- 每个 `clk` 周期更新一次：`{old[0], input}`。
- 输出取第二级：`scl_sync = scl_ff[1]`, `sda_sync = sda_ff[1]`。
- 边界说明：该模块为同步器，不是严格的毛刺滤波器。

### 5.2 `i2c_shift_reg` 详细行为
- 内部寄存器 `shreg[7:0]`。
- 优先级：`load_en` 高于 `shift_en`。
- `shift_en=1` 时执行 `shreg <= {shreg[6:0], shift_in}`。
- `shift_out = shreg[7]`，满足 MSB-first 发送。
- 边界条件：复位后 `shreg=8'h00`。

### 5.3 `reg_file` 详细行为
- 存储规模 `256 x 8`。
- 复位时通过 `for` 循环清零所有地址。
- 写入在 `posedge clk` 且 `we=1` 时进行。
- 读口为组合读：`rdata = mem[raddr]`。
- 边界条件：地址自然回绕（8-bit）。

### 5.4 `i2c_rx_fsm` 详细行为
1. 状态机
  - `ST_IDLE`, `ST_ADDR`, `ST_ADDR_ACK`, `ST_REG`, `ST_REG_ACK`, `ST_WRITE`, `ST_WRITE_ACK`, `ST_READ`, `ST_READ_ACK`。

2. 地址与方向解析
  - 在地址接收完成后比较 `addr_byte[7:1] == dev_addr`。
  - `rw_dir = addr_byte[0]`，决定转入读或写流程。

3. 写事务
  - `ST_REG` 接收寄存器地址到 `reg_addr`。
  - `ST_WRITE` 每收满 8 bit 产生：
    - `reg_waddr <= reg_addr`
    - `reg_wdata <= rx_byte_new`
    - `reg_we <= 1'b1`
  - `ST_WRITE_ACK` 后 `reg_addr <= reg_addr + 1`。

4. 读事务
  - 地址阶段若读方向：`tx_load_data <= reg_rdata`，进入 `ST_READ`。
  - 在 `ST_READ` 的字节起始时机触发 `tx_load_en` 装载数据。
  - 每发送 1 字节后 `reg_addr` 自增并进入 `ST_READ_ACK`。
  - `ST_READ_ACK` 检测主机应答：
    - `sda_sync=1`（NACK）结束；
    - `sda_sync=0`（ACK）继续下一字节。

5. ACK 策略
  - 地址 ACK：仅地址匹配时拉低 SDA。
  - 寄存器地址 ACK、写数据 ACK：固定应答。
  - 读阶段 ACK 由主机提供。

6. 边界与重入
  - 任意状态遇 `stop_cond` 立即回 `ST_IDLE`。
  - 任意状态遇 `start_cond` 作为重复起始，重新进入地址阶段。

## 6. 异常与边界处理
1. 地址不匹配
  - 在 `ST_ADDR_ACK` 不驱动 ACK，并回到 `IDLE`，不产生寄存器写入。

2. 主机提前终止
  - 检测到 `stop_cond` 时清除 ACK 驱动并退出当前事务。

3. 读事务结束条件
  - 主机 NACK 作为正常结束信号，不视为错误。

4. 跨子模块传播行为
  - `i2c_rx_fsm` 为唯一事务控制源，统一控制 `i2c_shift_reg` 与 `reg_file` 的读写节奏，避免写使能扩散。

5. 地址边界
  - `reg_addr` 为 8-bit，自增越界按模 256 回绕。

6. 已知限制（非错误）
  - 无 Clock Stretching。
  - `scl_sda_filter` 不做多采样抗毛刺判决。

## 7. 配置参数与默认值

### 7.1 顶层参数
| 参数名 | 类型/位宽 | 默认值 | 生效模块 | 说明 |
|---|---|---|---|---|
| `DEV_ADDR` | `parameter [6:0]` | `7'h42` | `i2c_slave_top`/`i2c_rx_fsm` | 从机地址匹配值 |

### 7.2 固化设计常量（RTL 内部）
| 常量 | 默认值 | 说明 |
|---|---|---|
| 寄存器深度 | 256 | `reg_file` 地址空间 |
| 寄存器位宽 | 8 | `reg_file` 单地址数据宽度 |
| 地址宽度 | 7 | I2C 设备地址宽度 |
| 字节宽度 | 8 | 协议与移位寄存器字节宽度 |

### 7.3 约束建议
- 建议在项目约束中补充：I2C 目标速率、`clk` 最低频率、SCL/SDA 输入时序预算。
- 若需增强鲁棒性，可将 `scl_sda_filter` 升级为计数式毛刺滤波器并在规格中新增可配置阈值。
