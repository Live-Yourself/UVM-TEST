# Path grouping to help reports

# Group main register-to-register paths
group_path -name REG2REG -from [all_registers] -to [all_registers]

# Group input paths
group_path -name IN2REG  -from [all_inputs]  -to [all_registers]

# Group output paths
group_path -name REG2OUT -from [all_registers] -to [all_outputs]
