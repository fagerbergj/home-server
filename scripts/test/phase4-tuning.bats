#!/usr/bin/env bats
# Tests for scripts/setup/phase4-tuning.sh.
#
# Mocks /sys writes, sysctl, update-initramfs, /proc reads. Safe to run
# anywhere.

load 'test_helper.bash'

SRC_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../setup" && pwd)/phase4-tuning.sh"

setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    stub_bin_init
    make_sudo_stub

    # Sandbox the /sys, /proc, /etc paths the script writes to.
    mkdir -p "$TEST_DIR/sys/module/zfs/parameters"
    mkdir -p "$TEST_DIR/proc/sys/vm"
    mkdir -p "$TEST_DIR/proc/spl/kstat/zfs"
    mkdir -p "$TEST_DIR/etc/modprobe.d"
    mkdir -p "$TEST_DIR/etc/sysctl.d"

    # Pre-populate as if ARC were maxed out at the default ~24 GB so the
    # script's awk readout has something to print.
    cat > "$TEST_DIR/proc/spl/kstat/zfs/arcstats" <<'EOF'
6 1 0x01 89 24208 13123456789 36123456789
name                            type data
hits                            4    100
c_max                           4    25232930816
size                            4    24800000000
EOF

    echo 60 > "$TEST_DIR/proc/sys/vm/swappiness"

    make_stub "update-initramfs"
    make_stub "sysctl" 'echo "vm.swappiness = 10"'

    SCRIPT="$TEST_DIR/phase4-tuning.sh"
    cp "$SRC_SCRIPT" "$SCRIPT"
    # Redirect every absolute path the script touches into the sandbox.
    sed -i "s|/sys/module/zfs/parameters/zfs_arc_max|$TEST_DIR/sys/module/zfs/parameters/zfs_arc_max|g" "$SCRIPT"
    sed -i "s|/proc/sys/vm/drop_caches|$TEST_DIR/proc/sys/vm/drop_caches|g" "$SCRIPT"
    sed -i "s|/proc/sys/vm/swappiness|$TEST_DIR/proc/sys/vm/swappiness|g" "$SCRIPT"
    sed -i "s|/proc/spl/kstat/zfs/arcstats|$TEST_DIR/proc/spl/kstat/zfs/arcstats|g" "$SCRIPT"
    sed -i "s|/etc/modprobe.d/zfs.conf|$TEST_DIR/etc/modprobe.d/zfs.conf|g" "$SCRIPT"
    sed -i "s|/etc/sysctl.d/99-swappiness.conf|$TEST_DIR/etc/sysctl.d/99-swappiness.conf|g" "$SCRIPT"
    chmod +x "$SCRIPT"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "writes ARC max to /sys/module/zfs/parameters/zfs_arc_max" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_DIR/sys/module/zfs/parameters/zfs_arc_max")" = "17179869184" ]   # 16 GB in bytes
}

@test "persists ARC cap in /etc/modprobe.d/zfs.conf" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q "options zfs zfs_arc_max=17179869184" "$TEST_DIR/etc/modprobe.d/zfs.conf"
}

@test "calls update-initramfs after writing modprobe config" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/update-initramfs.calls" ]
    grep -q "u" "$TEST_DIR/update-initramfs.calls"
}

@test "sets vm.swappiness=10 in sysctl.d" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q "vm.swappiness=10" "$TEST_DIR/etc/sysctl.d/99-swappiness.conf"
}

@test "drops caches to force ARC shrink" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_DIR/proc/sys/vm/drop_caches")" = "3" ]
}

@test "summary reports ARC max and current size" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARC max:"* ]]
    [[ "$output" == *"ARC now:"* ]]
    [[ "$output" == *"swappiness"* ]]
}
