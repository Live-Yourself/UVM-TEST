# Optional dont_touch directives
# Use sparingly; only protect intentional sync structures

# Protect the synchronizer flops in scl_sda_filter
set_dont_touch [get_cells -hier -filter {ref_name =~ *scl_sda_filter*}]
