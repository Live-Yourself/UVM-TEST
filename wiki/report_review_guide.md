DC 综合报告查看指南（i2c_slave_top）

目的
- 快速判断是否存在时序/约束/结构类违例
- 明确每类报告应关注的关键字段

1) summary/check_design_*.rpt
- 含义：设计结构与连接合法性检查报告（lint/结构一致性）。
- 作用：第一时间暴露连线、端口、模块实例等基础结构问题。
- 关注点：是否有 ERROR/WARNING
- 常见问题：未连接端口、未定义模块、锁存器推断
- 判定：出现 ERROR 必须修复；WARNING 视影响程度决定

参数含义（summary/check_design_*.rpt 常见字段）：
- Inputs/Outputs：端口总数统计。
- Unconnected ports (LINT-28)：未连接端口数量。
- Nets connected to multiple pins on same cell (LINT-33)：同一单元多个引脚被同一网线连接的情况。

示例解析（summary/check_design_*.rpt）：
- LINT-28：i2c_rx_fsm 的 dev_addr 与 rx_byte[7] 未连接，说明顶层连接或常量绑定不完整。
- LINT-33：u_fsm 的 dev_addr 多位连到同一常量网（n_logic1_/n_logic0_），表明该端口被固定为常量，若非预期需修连接。
- LINT-33：u_regfile 的 waddr 与 raddr 绑定到同一 net（reg_addr[*]），这是设计选择（读写同一地址），一般可接受。

2) summary/check_timing_*.rpt
- 含义：时序前置检查报告（约束完整性与时序环境一致性）。
- 作用：确认是否存在未约束路径、缺失输入延时、环路等基础时序风险。
- 关注点：是否有 “violations” 或 “unconstrained paths”
- 判定：存在未约束路径需要补约束；有负 slack 需优化

参数含义（summary/check_timing_*.rpt 常见检查项）：
- generated_clocks：派生时钟检查。
- loops：时钟或组合环路检查。
- no_input_delay：是否存在未设置输入延时的端口。
- unconstrained_endpoints：是否存在未约束端点。
- pulse_clock_cell_type：脉冲时钟单元检查。
- no_driving_cell：输入端口驱动单元检查。
- partial_input_delay：是否仅部分输入设置延时。

示例解析（summary/check_timing_*.rpt）：
- 仅出现 “Checking …” 信息且无 Warning/Error，表示检查通过。
- 建议后续用 constraint 报告确认是否存在真正的约束违例。

3) summary/qor_*.rpt
- 含义：综合质量总览报告（QoR: timing/area/power/drc）。
- 作用：用于一页判断当前综合结果是否达标及优化方向。
- 关注点：WNS、TNS、NUM paths、面积、功耗
- 判定：WNS<0 或 TNS<0 代表时序违例

参数含义（summary/qor_*.rpt 常见字段）：
- Levels of Logic：逻辑级数（组合级数）。
- Critical Path Length：关键路径延时总和。
- Critical Path Slack：关键路径裕量（负值=违例）。
- Critical Path Clk Period：参考时钟周期。
- Worst Negative Slack（WNS）：最差负时序裕量（最差路径的slack）。
- Total Negative Slack (TNS)：所有负 slack 之和。
- No. of Violating Paths：违例路径数量。
- Worst/Total Hold Violation：保持时间最坏/总违例（负值=违例）。
- Cell/Design Area：单元面积/总设计面积。
- Max Trans/Cap/Fanout Violations：转换/电容/扇出约束违例数量。

示例解析（summary/qor_*.rpt）：
- IN2REG/REG2OUT/clk：WNS/TNS=0，且 slack 为正，说明 setup 无违例。
- REG2REG：Worst Hold Violation = -0.13，Total Hold Violation = -0.44，Hold Violations = 5，说明存在保持时间违例（需修复）。
- Design WNS/TNS=0（setup OK），Design Hold WNS=0.13 但仍有 5 条 hold 违例，需在约束或实现阶段修复。
- Design Rules：Max Trans/Fanout Violations 非 0，说明约束或优化不足，需检查 max_transition/max_fanout 设置与修复策略。

4) summary/constraint_*.rpt
- 含义：约束违例摘要报告（max_delay/fanout/cap 等）。
- 作用：快速判断“约束是否被满足”，并锁定违例类别。
- 关注点：max_delay / max_fanout / max_capacitance / multiport_net
- 判定：列出违例即需处理（修约束或优化结构）

参数含义（summary/constraint_*.rpt 常见字段）：
- Required/Actual：约束要求值与实际值。
- Slack：Actual-Required（负值=违例）。
- (VIOLATED)：表示该网线违反对应约束。

示例解析（summary/constraint_*.rpt）：
- 本报告仅出现 max_fanout 违例，说明扇出约束未满足。
- reg_addr[*] 与 u_regfile 内部网出现高扇出，需插缓冲或放宽 fanout 约束。
- rst_n 有轻微 fanout 违例，常见于全局复位，可通过约束豁免或专用复位缓冲解决。

5) summary/timing_violate_*.rpt
- 含义：负 slack 违例路径摘要报告。
- 作用：集中查看需优先修复的时序失败路径。
- 关注点：slack < 0 的路径细节
- 判定：每条路径都需确认是否可接受或必须优化

参数含义（summary/timing_violate_*.rpt 常见字段）：
- Operating Conditions/Library：时序分析所用工艺角与库。
- Wire Load Model Mode：线负载模型模式（未布局时的估算）。
- No paths：表示无满足“slack < 0”的违例路径。

示例解析（summary/timing_violate_*.rpt）：
- 报告显示 “No paths.”，说明在 max/setup 角下无负 slack 路径。
- 结论：setup 时序无违例；若仍有 hold 违例需转看 hold 报告或 analysis/timing_max。

6) analysis/timing_max_*.rpt
- 含义：最大延时（setup）路径详细时序报告。
- 作用：定位关键慢路径，指导逻辑重构、约束与实现优化。
- 关注点：最长路径排名与结构
- 判定：用于定位瓶颈路径，指导优化

analysis/timing_min_*.rpt（hold）补充：
- 含义：最小延时（hold）路径详细时序报告。
- 作用：定位过快路径，指导 hold 修复（插延时/缓冲/约束调整）。
- 用途：查看最短路径与 hold 违例。
- 关注点：Path Type=min 的 slack、Start/End、data arrival/required。

参数含义（analysis/timing_min_*.rpt 常见字段）：
- Path Type: min：保持时间路径。
- data arrival time：数据到达时间（越早越危险）。
- data required time：保持要求时间。
- slack (VIOLATED)：arrival - required（负值=hold 违例）。

示例解析（analysis/timing_min_*.rpt）：
- 起点 u_filter/sda_ff_reg_1_ 到终点 u_fsm/reg_wdata_reg_0_，arrival=0.00、required=0.13，slack=-0.13。
- 这是典型“过快路径”，需要插入延时或让工具做 hold 修复。

7) analysis/area_*.rpt
- 含义：面积分析报告（总面积与层级面积分布）。
- 作用：识别面积热点模块，支撑面积优化与资源权衡。
- 关注点：层级面积分布、是否异常膨胀
- 判定：某模块面积异常需核查 RTL 或约束

8) analysis/power_*.rpt
- 含义：功耗分析报告（动态/静态及分项）。
- 作用：识别功耗热点并评估优化收益。
- 关注点：总功耗、动态/静态占比
- 判定：无切换活动时仅参考趋势

9) analysis/constraint_*.rpt
- 含义：约束检查详细报告（对象级明细）。
- 作用：精确定位每条违例网线/端点，作为修复依据。
- 关注点：比 summary 更详细
- 判定：用于精确定位违例对象

示例解析（analysis/constraint_*.rpt）：
- 所有违例均为 max_fanout，且集中在 reg_addr[*] 与 u_regfile 内部网。
- 说明寄存器地址总线扇出过大，需插入缓冲/分段驱动，或放宽 fanout 约束。
- rst_n 也有轻微 fanout 违例，可考虑复位缓冲或在约束中豁免。

10) analysis/zero_interconnect_*（零互连）
- 含义：理想互连（忽略布线寄生）条件下的时序分析报告。
- 作用：区分“逻辑本身问题”与“互连负载导致问题”。
- 关注点：理想连线下时序
- 判定：若零互连仍违例，多半是逻辑结构问题

11) debug/high_fanout_nets_*.rpt
- 含义：高扇出网络调试报告。
- 作用：定位高负载网络，指导缓冲插入与网络重构。
- 关注点：扇出过高的 nets
- 判定：可能导致时序问题，需插 buffer/重构

参数含义（debug/high_fanout_nets_*.rpt 常见字段）：
- threshold：报告门槛（fanout ≥ 阈值才列出）。
- Fanout：该 net 的负载数量。
- Attributes：net 属性（如 d=don’t_touch，dr=drc disabled）。
- Capacitance：该 net 总电容。
- Driver：驱动该 net 的单元/端口。

示例解析（debug/high_fanout_nets_*.rpt）：
- clk fanout=270，属于全局时钟网，高扇出正常，但需依赖时钟树优化。
- u_regfile/n_logic0_ fanout=256，说明常量网或译码网扇出过高，建议插缓冲或优化译码结构。

12) debug/clock_gating_*.rpt
- 含义：时钟门控结构与覆盖率报告。
- 作用：检查门控是否生效、是否满足低功耗与时序安全要求。
- 关注点：门控时钟覆盖率
- 判定：若使用门控，需确认门控策略与安全性

13) debug/latches_*.rpt
- 含义：锁存器推断报告。
- 作用：发现非预期 latch，避免功能/时序风险。
- 关注点：是否有 latch
- 判定：本工程不应有 latch，若出现需修 RTL

14) debug/clock_tree_*.rpt
- 含义：时钟网络结构概览报告（综合阶段视图）。
- 作用：辅助理解时钟分发形态与潜在时钟风险点。
- 关注点：时钟结构概览
- 判定：DC 阶段仅作参考，非 CTS 结果

15) debug/port_*.rpt
- 含义：端口属性与约束状态报告。
- 作用：核验 IO 方向、驱动、负载与时序约束是否一致。
- 关注点：端口属性（方向/时序/驱动）
- 判定：用于核对 IO 约束是否生效

16) debug/hierarchy_*.rpt / resources_*.rpt
- 含义：层级结构与资源使用调试报告。
- 作用：排查模块层级异常、资源映射偏差与综合异常膨胀。
- 关注点：模块层级与资源使用
- 判定：定位结构异常或综合映射问题

17) config/design_*.rpt
- 含义：设计与综合环境配置摘要报告。
- 作用：确认库、工艺角、全局设置与设计上下文正确。
- 关注点：综合环境摘要（库/设置）
- 判定：确认库与设置正确

18) config/clocks_*.rpt
- 含义：时钟定义与属性报告（周期/不确定度等）。
- 作用：确认时钟约束是否正确加载并生效。
- 关注点：时钟定义、频率、uncertainty
- 判定：确认 clk 约束正确生效

19) config/compile_options_*.rpt
- 含义：综合编译选项记录报告。
- 作用：用于结果复盘与可重复性追踪（确认本次使用的优化开关）。
- 关注点：编译选项是否符合预期

20) config/isolate_ports_*.rpt
- 含义：端口隔离策略配置报告。
- 作用：确认隔离策略是否按预期启用，避免接口级异常。
- 关注点：端口隔离情况
- 判定：一般应为空或符合预期

快速判定规则
- WNS/TNS < 0：时序违例
- constraint 报告中出现违例条目：约束不满足
- latches 报告非空：RTL 需修
- unconstrained paths：补约束

建议流程
1) 先看 summary/qor 与 check_timing
2) 再看 constraint 与 timing_violate
3) 最后看 area/power/debug

备注
- 报告路径由 rpt.tcl 生成，目录为 ../report/summary、analysis、debug、config
- 若任何报告为空或缺失，检查脚本是否执行完整
