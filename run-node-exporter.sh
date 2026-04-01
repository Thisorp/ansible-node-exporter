#!/usr/bin/env bash
set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_CFG="$BASE_DIR/ansible.cfg"
INVENTORY_FILE="$BASE_DIR/inventory.ini"
HOSTS_FILE="$BASE_DIR/hosts.txt"
INSTALL_PLAYBOOK="$BASE_DIR/playbooks/install-node-exporter.yml"
UNINSTALL_PLAYBOOK="$BASE_DIR/playbooks/uninstall-node-exporter.yml"
BINARY_FILE="$BASE_DIR/files/node_exporter"

SSH_USER="${SSH_USER:-setup}"
SSH_PASSWORD="${SSH_PASSWORD:-}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_line() {
  echo "============================================================"
}

info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

ok() {
  echo -e "${GREEN}[ OK ]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

err() {
  echo -e "${RED}[ERR ]${NC} $1"
}

pause_enter() {
  echo
  read -rp "Nhấn Enter để quay lại menu..."
}

check_required_files() {
  local missing=0

  [[ -f "$ANSIBLE_CFG" ]] || { err "Thiếu file: ansible.cfg"; missing=1; }
  [[ -f "$INVENTORY_FILE" ]] || { err "Thiếu file: inventory.ini"; missing=1; }
  [[ -f "$HOSTS_FILE" ]] || { err "Thiếu file: hosts.txt"; missing=1; }
  [[ -f "$INSTALL_PLAYBOOK" ]] || { err "Thiếu file: playbooks/install-node-exporter.yml"; missing=1; }
  [[ -f "$UNINSTALL_PLAYBOOK" ]] || { err "Thiếu file: playbooks/uninstall-node-exporter.yml"; missing=1; }
  [[ -f "$BINARY_FILE" ]] || { err "Thiếu file: files/node_exporter"; missing=1; }

  if [[ $missing -ne 0 ]]; then
    return 1
  fi
  return 0
}

run_in_repo() {
  (
    cd "$BASE_DIR" || exit 1
    export ANSIBLE_CONFIG="$ANSIBLE_CFG"
    "$@"
  )
}

count_hosts() {
  if [[ -f "$HOSTS_FILE" ]]; then
    grep -Ev '^\s*#|^\s*$' "$HOSTS_FILE" | wc -l | tr -d ' '
  else
    echo "0"
  fi
}

prepare_local() {
  print_line
  info "Kiểm tra môi trường local"

  check_required_files || return 1

  if command -v ansible >/dev/null 2>&1; then
    ok "Ansible: $(ansible --version | head -n 1)"
  else
    err "Chưa cài ansible"
  fi

  if command -v sshpass >/dev/null 2>&1; then
    ok "sshpass đã có"
  else
    warn "Chưa có sshpass, bootstrap SSH sẽ không chạy được"
  fi

  if [[ -f "$SSH_KEY" ]]; then
    ok "SSH private key tồn tại: $SSH_KEY"
  else
    warn "Chưa có SSH key: $SSH_KEY"
  fi

  if [[ -f "${SSH_KEY}.pub" ]]; then
    ok "SSH public key tồn tại: ${SSH_KEY}.pub"
  else
    warn "Chưa có SSH public key: ${SSH_KEY}.pub"
  fi

  if [[ -x "$BINARY_FILE" ]]; then
    ok "Binary node_exporter đã sẵn sàng"
    "$BINARY_FILE" --version | head -n 1 || true
  else
    warn "Binary có tồn tại nhưng chưa executable, sẽ tự chmod +x"
    chmod +x "$BINARY_FILE" 2>/dev/null || true
    [[ -x "$BINARY_FILE" ]] && ok "Đã cấp quyền execute cho files/node_exporter"
  fi

  ok "Số host trong hosts.txt: $(count_hosts)"
}

bootstrap_ssh() {
  print_line
  info "Bootstrap SSH key tới các host trong hosts.txt"

  check_required_files || return 1

  if ! command -v sshpass >/dev/null 2>&1; then
    err "Thiếu sshpass"
    return 1
  fi

  # 👉 Nếu chưa có password thì hỏi (ẩn input)
  if [[ -z "${SSH_PASSWORD:-}" ]]; then
    read -rsp "Nhập password SSH cho user ${SSH_USER}: " SSH_PASSWORD
    echo
    read -rsp "Nhập lại password: " confirm_password
    echo

    if [[ "$SSH_PASSWORD" != "$confirm_password" ]]; then
      err "Password không khớp"
      return 1
    fi
  fi

  # 👉 Tạo SSH key nếu chưa có
  if [[ ! -f "$SSH_KEY" ]]; then
    info "Chưa có SSH key, tiến hành tạo mới"
    ssh-keygen -t ed25519 -C "${SSH_USER}@$(hostname)" -f "$SSH_KEY" -N "" || {
      err "Tạo SSH key thất bại"
      return 1
    }
    ok "Đã tạo SSH key: $SSH_KEY"
  fi

  export SSHPASS="$SSH_PASSWORD"

  local total=0
  local success=0
  local failed=0

  while IFS= read -r host; do
    [[ -z "$host" ]] && continue
    [[ "$host" =~ ^[[:space:]]*# ]] && continue

    total=$((total + 1))
    info "Đẩy key tới ${SSH_USER}@${host}"

    if sshpass -e ssh-copy-id -i "${SSH_KEY}.pub" -o StrictHostKeyChecking=no "${SSH_USER}@${host}"; then
      ok "${host}: thành công"
      success=$((success + 1))
    else
      err "${host}: thất bại"
      failed=$((failed + 1))
    fi
    echo
  done < "$HOSTS_FILE"

  unset SSHPASS

  print_line
  echo "KẾT QUẢ BOOTSTRAP"
  echo "Tổng host   : $total"
  echo "Thành công  : $success"
  echo "Thất bại    : $failed"

  [[ $failed -eq 0 ]]
}

test_connectivity() {
  print_line
  info "Kiểm tra inventory và kết nối Ansible"

  check_required_files || return 1

  echo
  info "1) Graph inventory"
  run_in_repo ansible-inventory --graph || return 1

  echo
  info "2) Ping host"
  run_in_repo ansible node_exporters -m ping -K || return 1

  ok "Kết nối Ansible bình thường"
}

deploy_node_exporter() {
  print_line
  info "Deploy node_exporter"

  check_required_files || return 1

  if [[ ! -x "$BINARY_FILE" ]]; then
    chmod +x "$BINARY_FILE" 2>/dev/null || true
  fi

  run_in_repo ansible-playbook "$INSTALL_PLAYBOOK" -K
}

verify_node_exporter() {
  print_line
  info "Kiểm tra trạng thái node_exporter trên các host"

  check_required_files || return 1

  echo
  info "1) Service status"
  run_in_repo ansible node_exporters -e 'ansible_become=false' -m shell -a 'systemctl is-active node_exporter || true'

  echo
  info "2) Service enabled"
  run_in_repo ansible node_exporters -e 'ansible_become=false' -m shell -a 'systemctl is-enabled node_exporter || true'

  echo
  info "3) Port listen"
  run_in_repo ansible node_exporters -e 'ansible_become=false' -m shell -a 'ss -lntp | grep 9100 || netstat -lntp 2>/dev/null | grep 9100 || true'

  echo
  info "4) Metrics head"
  run_in_repo ansible node_exporters -e 'ansible_become=false' -m shell -a "curl -fsS http://127.0.0.1:9100/metrics | sed -n '1,5p'"
}

uninstall_node_exporter() {
  print_line
  info "Gỡ node_exporter"

  check_required_files || return 1

  run_in_repo ansible-playbook "$UNINSTALL_PLAYBOOK" -K
}

status_summary() {
  print_line
  info "Tổng hợp trạng thái"

  check_required_files || return 1

  echo "Repo root              : $BASE_DIR"
  echo "Ansible config         : $ANSIBLE_CFG"
  echo "Inventory              : $INVENTORY_FILE"
  echo "Hosts file             : $HOSTS_FILE"
  echo "Install playbook       : $INSTALL_PLAYBOOK"
  echo "Uninstall playbook     : $UNINSTALL_PLAYBOOK"
  echo "Binary                 : $BINARY_FILE"
  echo "SSH user               : $SSH_USER"
  echo "Số host                : $(count_hosts)"
  echo

  command -v ansible >/dev/null 2>&1 && ok "ansible đã cài" || err "ansible chưa cài"
  command -v sshpass >/dev/null 2>&1 && ok "sshpass đã cài" || warn "sshpass chưa cài"
  [[ -f "$SSH_KEY" ]] && ok "Có SSH private key" || warn "Chưa có SSH private key"
  [[ -f "${SSH_KEY}.pub" ]] && ok "Có SSH public key" || warn "Chưa có SSH public key"
  [[ -x "$BINARY_FILE" ]] && ok "Binary executable" || warn "Binary chưa executable"

  echo
  info "Inventory graph"
  run_in_repo ansible-inventory --graph 2>/dev/null || true

  echo
  info "Service node_exporter trên remote"

  local output status

  if [[ ! -f "$HOSTS_FILE" ]]; then
    err "Không thấy file hosts: $HOSTS_FILE"
    return 1
  fi

  while IFS= read -r host; do
    [[ -z "$host" ]] && continue
    [[ "$host" =~ ^[[:space:]]*# ]] && continue

    printf "%-15s => " "$host"

    output=$(run_in_repo ansible "$host" -e 'ansible_become=false' -m shell -a 'systemctl is-active node_exporter 2>/dev/null || true' 2>&1)

    if echo "$output" | grep -qi "UNREACHABLE"; then
      echo -e "${RED}UNREACHABLE${NC}"
      continue
    fi

    status=$(echo "$output" | awk 'NF{last=$0} END{gsub(/^[ \t]+|[ \t]+$/, "", last); print last}')

    case "$status" in
      active)
        echo -e "${GREEN}ACTIVE${NC}"
        ;;
      inactive)
        echo -e "${YELLOW}INACTIVE${NC}"
        ;;
      failed)
        echo -e "${RED}FAILED${NC}"
        ;;
      activating)
        echo -e "${YELLOW}ACTIVATING${NC}"
        ;;
      deactivating)
        echo -e "${YELLOW}DEACTIVATING${NC}"
        ;;
      *)
        echo -e "${YELLOW}UNKNOWN${NC} (${status:-no-output})"
        echo "$output" | sed 's/^/   /'
        ;;
    esac
  done < "$HOSTS_FILE"
}

full_flow() {
  print_line
  info "Chạy full flow"

  prepare_local || { err "Lỗi bước prepare"; return 1; }
  bootstrap_ssh || { err "Lỗi bước bootstrap SSH"; return 1; }
  test_connectivity || { err "Lỗi bước test connectivity"; return 1; }
  deploy_node_exporter || { err "Lỗi bước deploy"; return 1; }
  verify_node_exporter || { err "Lỗi bước verify"; return 1; }

  ok "Hoàn tất full flow"
}

show_menu() {
  clear
  echo "================ NODE EXPORTER MANAGER ================"
  echo "Repo: $BASE_DIR"
  echo "-------------------------------------------------------"
  echo "1) Kiểm tra môi trường local"
  echo "2) Bootstrap SSH key từ hosts.txt"
  echo "3) Test inventory / ping Ansible"
  echo "4) Deploy node_exporter"
  echo "5) Verify node_exporter"
  echo "6) Uninstall node_exporter"
  echo "7) Status tổng hợp"
  echo "8) Chạy full flow"
  echo "0) Thoát"
  echo "======================================================="
}

main() {
  while true; do
    show_menu
    read -rp "Chọn chức năng: " choice

    case "$choice" in
      1)
        prepare_local
        pause_enter
        ;;
      2)
        bootstrap_ssh
        pause_enter
        ;;
      3)
        test_connectivity
        pause_enter
        ;;
      4)
        deploy_node_exporter
        pause_enter
        ;;
      5)
        verify_node_exporter
        pause_enter
        ;;
      6)
        uninstall_node_exporter
        pause_enter
        ;;
      7)
        status_summary
        pause_enter
        ;;
      8)
        full_flow
        pause_enter
        ;;
      0)
        echo "Thoát."
        exit 0
        ;;
      *)
        warn "Lựa chọn không hợp lệ"
        pause_enter
        ;;
    esac
  done
}

main
