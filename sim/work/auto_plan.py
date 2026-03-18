#!/usr/bin/env python
"""
auto_plan.py (Python 2.7 compatible)

Generate a coverage/regression-driven next-run plan for this I2C UVM project.

Inputs (if present):
    - sim/sim_result/regression_runs.csv
    - sim/sim_result/failure_events.csv
    - sim/sim_result/coverage_buckets.csv

Outputs:
    - sim/sim_result/auto_plan.csv
    - sim/sim_result/auto_plan.md
    - sim/sim_result/auto_plan.sh
"""

from __future__ import print_function

import argparse
import csv
import os
import random
from collections import defaultdict
from datetime import datetime


CORE_TESTS = [
    "i2c_smoke_test",
    "i2c_cov_closure_test",
    "i2c_illegal_addr_test",
    "i2c_illegal_read_test",
    "i2c_stretch_test",
    "i2c_rand_burst_test",
]

SCENARIO_MAP = {
    "i2c_smoke_test": "basic read/write loop",
    "i2c_cov_closure_test": "functional coverage closure matrix",
    "i2c_illegal_addr_test": "illegal address NACK",
    "i2c_illegal_read_test": "illegal address READ path",
    "i2c_stretch_test": "clock low stretch timing",
    "i2c_rand_burst_test": "random burst read/write",
}

GATE_TESTS = [
    "i2c_smoke_test",
    "i2c_illegal_addr_test",
    "i2c_illegal_read_test",
    "i2c_stretch_test",
]

COVERAGE_TESTS = [
    "i2c_cov_closure_test",
    "i2c_rand_burst_test",
]


class TestStat:
    def __init__(self):
        self.runs = 0
        self.passed = 0
        self.failed = 0
        self.cov_sum = 0.0
        self.cov_cnt = 0
        self.latest_cov = None

    def pass_rate(self):
        return (self.passed / self.runs) if self.runs else 0.0

    def avg_cov(self):
        if self.cov_cnt == 0:
            return None
        return self.cov_sum / self.cov_cnt


class PlanItem:
    def __init__(self, priority, test, seed, extra_args, reason):
        self.priority = priority
        self.test = test
        self.seed = seed
        self.extra_args = extra_args
        self.reason = reason


class BucketStat:
    def __init__(self):
        self.addr_low = 0
        self.addr_mid = 0
        self.addr_high = 0
        self.len_single = 0
        self.len_short = 0
        self.len_burst = 0
        self.illegal_read = 0

    def merge_row(self, row):
        self.addr_low += int(row.get("addr_low", "0") or 0)
        self.addr_mid += int(row.get("addr_mid", "0") or 0)
        self.addr_high += int(row.get("addr_high", "0") or 0)
        self.len_single += int(row.get("len_single", "0") or 0)
        self.len_short += int(row.get("len_short", "0") or 0)
        self.len_burst += int(row.get("len_burst", "0") or 0)
        self.illegal_read += int(row.get("illegal_read", "0") or 0)


class Bucket2Stat:
    def __init__(self):
        self.legal_wr = 0
        self.legal_rd = 0
        self.illegal_wr = 0
        self.illegal_rd = 0
        self.ack_all = 0
        self.ack_nack = 0
        self.rd_match = 0

    def merge_row(self, row):
        self.legal_wr += int(row.get("legal_wr", "0") or 0)
        self.legal_rd += int(row.get("legal_rd", "0") or 0)
        self.illegal_wr += int(row.get("illegal_wr", "0") or 0)
        self.illegal_rd += int(row.get("illegal_rd", "0") or 0)
        self.ack_all += int(row.get("ack_all", "0") or 0)
        self.ack_nack += int(row.get("ack_nack", "0") or 0)
        self.rd_match += int(row.get("rd_match", "0") or 0)


def parse_args():
    p = argparse.ArgumentParser(description="Generate next regression plan from history.")
    p.add_argument("--result-base", default=None, help="Path to sim/sim_result (optional)")
    p.add_argument("--target-pass-rate", type=float, default=0.90, help="Desired per-test pass rate")
    p.add_argument("--target-fcov", type=float, default=80.0, help="Desired average functional coverage(%%)")
    p.add_argument("--min-runs-per-test", type=int, default=3, help="Desired minimum historical runs per test")
    p.add_argument("--gate-min-runs", type=int, default=1, help="Minimum planned runs for gate tests when healthy")
    p.add_argument("--coverage-budget", type=int, default=12, help="Nominal planned items budget for coverage-oriented tests")
    p.add_argument("--max-plan-items", type=int, default=20, help="Maximum recommended run items")
    return p.parse_args()


def seed_gen():
    return random.randint(1, 2147483646)


def load_stats(run_db):
    stats = defaultdict(TestStat)
    if not os.path.exists(run_db):
        return stats

    with open(run_db, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            t = row.get("test", "").strip()
            if not t:
                continue
            s = stats[t]
            s.runs += 1
            status = row.get("status", "").strip().upper()
            if status == "PASS":
                s.passed += 1
            elif status == "FAIL":
                s.failed += 1

            fc = row.get("func_cov", "").strip()
            try:
                v = float(fc)
                s.cov_sum += v
                s.cov_cnt += 1
                s.latest_cov = v
            except Exception:
                pass
    return stats


def load_failure_top(fail_db, topn=5):
    if not os.path.exists(fail_db):
        return []
    cnt = defaultdict(int)
    with open(fail_db, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            fid = row.get("id", "").strip()
            try:
                c = int(row.get("count", "0"))
            except Exception:
                c = 0
            if fid:
                cnt[fid] += c
    tops = sorted(cnt.items(), key=lambda x: x[1], reverse=True)[:topn]
    out = []
    for k, v in tops:
        out.append("{}:{}".format(k, v))
    return out


def load_bucket_stats(bucket_db):
    b = BucketStat()
    if not os.path.exists(bucket_db):
        return b

    with open(bucket_db, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            b.merge_row(row)
    return b


def load_bucket2_stats(bucket2_db):
    b = Bucket2Stat()
    if not os.path.exists(bucket2_db):
        return b

    with open(bucket2_db, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            b.merge_row(row)
    return b


def build_plan(stats, bucket, bucket2, args):
    plan = []

    # 1) Gate-minimized strategy:
    #    Keep essential tests alive with minimum repetitions unless instability is detected.
    for t in GATE_TESTS:
        s = stats.get(t, TestStat())
        if s.passed == 0:
            plan.append(PlanItem(100, t, seed_gen(), "", "gate test has no PASS history"))
            plan.append(PlanItem(95, t, seed_gen(), "", "gate test has no PASS history (confirm)"))
            continue

        # Healthy gate test: only minimal keep-alive runs
        for _ in range(args.gate_min_runs):
            plan.append(PlanItem(55, t, seed_gen(), "", "gate keep-alive run"))

        # Unstable gate test: add retries
        if s.runs > 0 and s.pass_rate() < args.target_pass_rate:
            reason = "gate unstable: pass_rate {:.2f}% < target {:.2f}%".format(s.pass_rate() * 100.0, args.target_pass_rate * 100.0)
            plan.append(PlanItem(90, t, seed_gen(), "", reason))
            plan.append(PlanItem(85, t, seed_gen(), "", reason))

    # 2) Coverage-priority strategy:
    #    Prefer closure and matrix tests; use rand_burst with directed constraints.
    rb = stats.get("i2c_rand_burst_test", TestStat())
    cl = stats.get("i2c_cov_closure_test", TestStat())

    rb_avg = rb.avg_cov()
    cl_avg = cl.avg_cov()
    rb_cov = rb_avg if rb_avg is not None else 0.0
    cl_cov = cl_avg if cl_avg is not None else 0.0

    rb_flat = False
    if rb.runs >= 8 and rb.latest_cov is not None and rb_avg is not None:
        if abs(rb.latest_cov - rb_avg) < 0.05:
            rb_flat = True

    # Ensure closure test is always in the plan when fcov target is not met
    if cl_cov < args.target_fcov:
        plan.append(PlanItem(92, "i2c_cov_closure_test", seed_gen(), "", "coverage priority: closure test below target"))
        plan.append(PlanItem(90, "i2c_cov_closure_test", seed_gen(), "", "coverage priority: closure reinforcement"))

    # If rand_burst is plateaued, reduce blind retries and shift to directed matrix + closure
    if rb_flat:
        plan.append(PlanItem(89, "i2c_cov_closure_test", seed_gen(), "", "rand_burst plateau detected; shift budget to closure"))
    else:
        plan.append(PlanItem(72, "i2c_rand_burst_test", seed_gen(), "", "coverage sampling run"))

    # 3) Bucket-driven targeted constraints from coverage report
    if bucket.addr_high == 0:
        for _ in range(3):
            plan.append(PlanItem(95, "i2c_rand_burst_test", seed_gen(), "+ADDR_BUCKET=HIGH +BURST_LEN=5", "unhit bucket: high address region"))
    if bucket.addr_mid == 0:
        for _ in range(2):
            plan.append(PlanItem(85, "i2c_rand_burst_test", seed_gen(), "+ADDR_BUCKET=MID +BURST_LEN=4", "unhit bucket: mid address region"))
    if bucket.len_single == 0:
        for _ in range(2):
            plan.append(PlanItem(90, "i2c_rand_burst_test", seed_gen(), "+BURST_LEN=1", "unhit bucket: single-length burst"))
    if bucket.len_short == 0:
        for _ in range(2):
            plan.append(PlanItem(90, "i2c_rand_burst_test", seed_gen(), "+BURST_LEN=3", "unhit bucket: short burst(2..4)"))
    if bucket.len_burst == 0:
        for _ in range(2):
            plan.append(PlanItem(90, "i2c_rand_burst_test", seed_gen(), "+BURST_LEN=8", "unhit bucket: burst length(>=5)"))
    if bucket.illegal_read == 0:
        for _ in range(3):
            plan.append(PlanItem(98, "i2c_illegal_read_test", seed_gen(), "", "unhit bucket: illegal address read path"))

    # v2 bucket-driven closures
    if bucket2.legal_wr == 0:
        for _ in range(2):
            plan.append(PlanItem(96, "i2c_smoke_test", seed_gen(), "", "unhit bucket: legal write path"))
    if bucket2.legal_rd == 0:
        for _ in range(2):
            plan.append(PlanItem(96, "i2c_smoke_test", seed_gen(), "", "unhit bucket: legal read path"))
    if bucket2.illegal_wr == 0:
        for _ in range(2):
            plan.append(PlanItem(96, "i2c_illegal_addr_test", seed_gen(), "", "unhit bucket: illegal write path"))
    if bucket2.illegal_rd == 0:
        for _ in range(2):
            plan.append(PlanItem(96, "i2c_illegal_read_test", seed_gen(), "", "unhit bucket: illegal read path"))
    if bucket2.ack_nack == 0:
        for _ in range(2):
            plan.append(PlanItem(94, "i2c_illegal_addr_test", seed_gen(), "", "unhit bucket: NACK path"))
    if bucket2.rd_match == 0:
        for _ in range(2):
            plan.append(PlanItem(94, "i2c_rand_burst_test", seed_gen(), "+BURST_LEN=3", "unhit bucket: read data match path"))

    # 4) Deterministic matrix: avoid blind same-pattern retries
    #    Cover address(low/mid/high) x len(1/3/8) by construction.
    matrix = [
        ("LOW", 1), ("LOW", 3), ("LOW", 8),
        ("MID", 1), ("MID", 3), ("MID", 8),
        ("HIGH", 1), ("HIGH", 3), ("HIGH", 8),
    ]
    matrix_runs = 9
    if rb_flat:
        matrix_runs = 9
    else:
        matrix_runs = 6

    c = 0
    for addr, blen in matrix:
        if c >= matrix_runs:
            break
        reason = "targeted matrix run: addr={} len={}".format(addr, blen)
        plan.append(PlanItem(88, "i2c_rand_burst_test", seed_gen(), "+ADDR_BUCKET={} +BURST_LEN={}".format(addr, blen), reason))
        c += 1

    # 5) Coverage budget filler: prioritize closure over gate tests
    #    (fill only when under target and there is budget)
    if cl_cov < args.target_fcov:
        for _ in range(max(0, args.coverage_budget // 4)):
            plan.append(PlanItem(78, "i2c_cov_closure_test", seed_gen(), "", "coverage budget filler: closure"))

    # De-duplicate and cap
    dedup = {}
    for p in plan:
        key = (p.test, p.extra_args, p.reason)
        if key not in dedup or p.priority > dedup[key].priority:
            dedup[key] = p
    plan = sorted(dedup.values(), key=lambda x: (x.priority, x.test), reverse=True)
    return plan[:args.max_plan_items]


def write_outputs(result_base, work_dir, plan, stats, fail_top, bucket):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    csv_file = os.path.join(result_base, "auto_plan.csv")
    md_file = os.path.join(result_base, "auto_plan.md")
    sh_file = os.path.join(work_dir, "auto_plan.sh")

    with open(csv_file, "w") as f:
        w = csv.writer(f)
        w.writerow(["priority", "test", "seed", "extra_args", "reason"])
        for p in plan:
            w.writerow([p.priority, p.test, p.seed, p.extra_args, p.reason])

    with open(sh_file, "w") as f:
        f.write("#!/bin/bash\nset -uo pipefail\n\n")
        f.write("# Auto-generated regression execution plan\n")
        f.write("SCRIPT_DIR=$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\n")
        f.write("RESULT_BASE=\"${SCRIPT_DIR}/../sim_result\"\n")
        f.write("TMP_DIR=\"${SCRIPT_DIR}/.auto_plan_tmp\"\n")
        f.write("FAIL_ROOT=\"${RESULT_BASE}/fail_regression_logs/auto_plan\"\n")
        f.write("mkdir -p \"${TMP_DIR}\" \"${FAIL_ROOT}\"\n")
        f.write("SUMMARY=\"${TMP_DIR}/auto_plan_summary_$(date +%Y%m%d_%H%M%S).csv\"\n")
        f.write("echo \"case_id,test,seed,extra,status,runner_log,start_ts,end_ts\" > \"${SUMMARY}\"\n")
        f.write("case_id=0\n\n")
        f.write("run_one() {\n")
        f.write("  local test_name=\"$1\"\n")
        f.write("  local seed_val=\"$2\"\n")
        f.write("  local extra_args=\"$3\"\n")
        f.write("  local status=\"PASS\"\n")
        f.write("  local start_ts end_ts case_log rc fail_dir sim_log latest_log\n")
        f.write("  case_id=$((case_id + 1))\n")
        f.write("  case_log=\"${TMP_DIR}/case_${case_id}_${test_name}.log\"\n")
        f.write("  start_ts=$(date '+%F %T')\n")
        f.write("  echo \"[AUTO_PLAN][CASE ${case_id}] START test=${test_name} seed=${seed_val} extra='${extra_args}'\"\n")
        f.write("\n")
        f.write("  if [[ -n \"${extra_args}\" ]]; then\n")
        f.write("    bash \"${SCRIPT_DIR}/run_uvm.sh\" \"${test_name}\" \"${seed_val}\" \"${extra_args}\" >\"${case_log}\" 2>&1\n")
        f.write("  else\n")
        f.write("    bash \"${SCRIPT_DIR}/run_uvm.sh\" \"${test_name}\" \"${seed_val}\" >\"${case_log}\" 2>&1\n")
        f.write("  fi\n")
        f.write("  rc=$?\n")
        f.write("  if [[ \"${rc}\" -ne 0 ]]; then\n")
        f.write("    status=\"FAIL\"\n")
        f.write("  fi\n")
        f.write("\n")
        f.write("  end_ts=$(date '+%F %T')\n")
        f.write("  if [[ \"${status}\" == \"FAIL\" ]]; then\n")
        f.write("    fail_dir=\"${FAIL_ROOT}/case_${case_id}_${test_name}_$(date +%Y%m%d_%H%M%S)\"\n")
        f.write("    mkdir -p \"${fail_dir}\"\n")
        f.write("    cp \"${case_log}\" \"${fail_dir}/runner.log\" || true\n")
        f.write("    sim_log=$(grep '^       log :' \"${case_log}\" | tail -n 1 | sed -E 's/^.*log : //')\n")
        f.write("    if [[ -n \"${sim_log}\" ]] && [[ -f \"${sim_log}\" ]]; then\n")
        f.write("      cp \"${sim_log}\" \"${fail_dir}/sim.log\" || true\n")
        f.write("    fi\n")
        f.write("    latest_log=$(grep '^       log_latest:' \"${case_log}\" | tail -n 1 | sed -E 's/^.*log_latest: //')\n")
        f.write("    if [[ -n \"${latest_log}\" ]] && [[ -f \"${latest_log}\" ]]; then\n")
        f.write("      cp \"${latest_log}\" \"${fail_dir}/latest.log\" || true\n")
        f.write("    fi\n")
        f.write("    echo \"[AUTO_PLAN][CASE ${case_id}] FAIL, archived: ${fail_dir}\"\n")
        f.write("  else\n")
        f.write("    echo \"[AUTO_PLAN][CASE ${case_id}] PASS\"\n")
        f.write("  fi\n")
        f.write("\n")
        f.write("  echo \"${case_id},${test_name},${seed_val},${extra_args},${status},${case_log},${start_ts},${end_ts}\" >> \"${SUMMARY}\"\n")
        f.write("}\n\n")

        for p in plan:
            extra = p.extra_args.replace('"', '\\"') if p.extra_args else ""
            f.write("run_one \"{}\" \"{}\" \"{}\"\n".format(p.test, p.seed, extra))

        f.write("\nTOTAL=$(awk -F, 'NR>1{c++} END{print c+0}' \"${SUMMARY}\")\n")
        f.write("PASS=$(awk -F, 'NR>1&&$5==\"PASS\"{c++} END{print c+0}' \"${SUMMARY}\")\n")
        f.write("FAIL=$((TOTAL - PASS))\n")
        f.write("RATE=\"0.00\"\n")
        f.write("if [[ \"${TOTAL}\" -gt 0 ]]; then\n")
        f.write("  RATE=$(awk -v p=\"${PASS}\" -v t=\"${TOTAL}\" 'BEGIN{printf \"%.2f\", (p*100.0)/t}')\n")
        f.write("fi\n")
        f.write("echo \"[AUTO_PLAN] Done: Total=${TOTAL} Pass=${PASS} Fail=${FAIL} PassRate=${RATE}%\"\n")
        f.write("echo \"[AUTO_PLAN] Summary: ${SUMMARY}\"\n")
        f.write("echo \"[AUTO_PLAN] Fail logs: ${FAIL_ROOT}\"\n")
        f.write("if [[ \"${FAIL}\" -gt 0 ]]; then\n")
        f.write("  exit 1\n")
        f.write("fi\n")

    with open(md_file, "w") as f:
        f.write("# Auto Regression Plan\n\n")
        f.write("Generated at: {}\n\n".format(ts))

        f.write("## Current test health\n\n")
        f.write("| test | runs | pass | fail | pass_rate | avg_func_cov(%) |\n")
        f.write("|---|---:|---:|---:|---:|---:|\n")
        for t in CORE_TESTS:
            s = stats.get(t, TestStat())
            avg_cov_val = s.avg_cov()
            avg_cov = "{:.2f}".format(avg_cov_val) if avg_cov_val is not None else "N/A"
            f.write("| {} | {} | {} | {} | {:.2f}% | {} |\n".format(t, s.runs, s.passed, s.failed, s.pass_rate() * 100.0, avg_cov))

        f.write("\n## Missing core scenarios (no PASS yet)\n\n")
        missing = [t for t in CORE_TESTS if stats.get(t, TestStat()).passed == 0]
        if not missing:
            f.write("All core scenarios have at least one PASS.\n")
        else:
            for t in missing:
                f.write("- {} ({})\n".format(SCENARIO_MAP[t], t))

        f.write("\n## Top failure IDs\n\n")
        if fail_top:
            for x in fail_top:
                f.write("- {}\n".format(x))
        else:
            f.write("No failure IDs collected yet.\n")

        f.write("\n## Coverage bucket status (from coverage_buckets.csv)\n\n")
        f.write("| bucket | hit_count | status |\n")
        f.write("|---|---:|---|\n")
        bucket_items = [
            ("addr_low", bucket.addr_low),
            ("addr_mid", bucket.addr_mid),
            ("addr_high", bucket.addr_high),
            ("len_single", bucket.len_single),
            ("len_short", bucket.len_short),
            ("len_burst", bucket.len_burst),
            ("illegal_read", bucket.illegal_read),
        ]
        for k, v in bucket_items:
            st = "covered" if v > 0 else "missing"
            f.write("| {} | {} | {} |\n".format(k, v, st))

        f.write("\n## Recommended next runs\n\n")
        f.write("| priority | test | seed | extra_args | reason |\n")
        f.write("|---:|---|---:|---|---|\n")
        for p in plan:
            f.write("| {} | {} | {} | {} | {} |\n".format(p.priority, p.test, p.seed, p.extra_args, p.reason))

        f.write("\n## One-click execution\n\n")
        f.write("Run: `bash sim/work/auto_plan.sh`\n")

    try:
        os.chmod(sh_file, 0o755)
    except Exception:
        pass



def main():
    args = parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    if args.result_base:
        result_base = os.path.abspath(args.result_base)
    else:
        result_base = os.path.abspath(os.path.join(script_dir, "..", "sim_result"))
    if not os.path.exists(result_base):
        os.makedirs(result_base)

    run_db = os.path.join(result_base, "regression_runs.csv")
    fail_db = os.path.join(result_base, "failure_events.csv")
    bucket_db = os.path.join(result_base, "coverage_buckets.csv")
    bucket2_db = os.path.join(result_base, "coverage_buckets_v2.csv")

    stats = load_stats(run_db)
    fail_top = load_failure_top(fail_db)
    bucket = load_bucket_stats(bucket_db)
    bucket2 = load_bucket2_stats(bucket2_db)
    plan = build_plan(stats, bucket, bucket2, args)
    write_outputs(result_base, script_dir, plan, stats, fail_top, bucket)

    print("[AUTO_PLAN] generated:")
    print("  - {}".format(os.path.join(result_base, 'auto_plan.csv')))
    print("  - {}".format(os.path.join(result_base, 'auto_plan.md')))
    print("  - {}".format(os.path.join(script_dir, 'auto_plan.sh')))


if __name__ == "__main__":
    main()
