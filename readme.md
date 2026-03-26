# 🚀 Deploy Node Exporter bằng Ansible

## 📌 Mục tiêu

Triển khai Node Exporter lên nhiều VM bằng Ansible để phục vụ monitoring với Prometheus.

* Control node: `172.16.0.2`
* Target nodes:

  * `172.16.0.3`
  * `172.16.0.4`
  * `172.16.0.5`
* User sử dụng: `setup`
* Node Exporter chạy tại:

```
/home/setup/node_exporter
```

---
# KET NOI CAN MO

```bash
archive.ubuntu.com
security.ubuntu.com
https://github.com
https://objects.githubusercontent.com
https://github-releases.githubusercontent.com
port 443,80
```

# 1. Cài đặt Ansible trên Control Node

```bash
sudo apt update
sudo apt install ansible sshpass -y
```

---

# 2. Tạo SSH Key

```bash
ssh-keygen -t ed25519 -C "setup@node-01"
```

---

# 3. Chuẩn bị danh sách VM

```bash
nano ~/ansible-node-exporter/hosts.txt
```

```
172.16.0.3
172.16.0.4
172.16.0.5
```

---

# 4. Enable password login tạm thời (trên tất cả VM)

```bash
sudo sed -i 's/^AuthenticationMethods publickey/#&/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

---

# 5. Copy SSH key hàng loạt

```bash
export SSHPASS='123456'

while read -r ip; do
  echo "=== Copy key to $ip ==="
  sshpass -e ssh-copy-id -o StrictHostKeyChecking=no setup@$ip
done < ~/ansible-node-exporter/hosts.txt

unset SSHPASS
```

---

# 6. Test SSH

```bash
while read -r ip; do
  ssh -o BatchMode=yes setup@$ip "hostname"
done < ~/ansible-node-exporter/hosts.txt
```

---

# 7. Tạo cấu trúc project

```bash
mkdir -p ~/ansible-node-exporter/{files,templates,playbooks,group_vars}
cd ~/ansible-node-exporter
```

---

# 8. Tải Node Exporter

```bash
cd files
wget https://github.com/prometheus/node_exporter/releases/download/v1.10.2/node_exporter-1.10.2.linux-amd64.tar.gz
```

---

# 9. Tạo inventory

```ini
[node_exporters]
172.16.0.3 ansible_user=setup
172.16.0.4 ansible_user=setup
172.16.0.5 ansible_user=setup
```

---

# 10. Tạo ansible.cfg

```ini
[defaults]
inventory = ./inventory.ini
host_key_checking = False
forks = 20
timeout = 30
```

---

# 11. Tạo biến dùng chung

`group_vars/all.yml`

```yaml
node_exporter_version: "1.10.2"
install_root: "/home/setup/node_exporter"
package_dir: "{{ install_root }}/packages"
bin_dir: "{{ install_root }}/bin"
textfile_dir: "{{ install_root }}/textfile_collector"
```

---

# 12. Tạo systemd service template

`templates/node_exporter.service.j2`

```ini
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=setup
ExecStart=/home/setup/node_exporter/bin/node_exporter \
  --web.listen-address=:9100 \
  --collector.textfile.directory=/home/setup/node_exporter/textfile_collector
Restart=always

[Install]
WantedBy=multi-user.target
```

---

# 13. Tạo playbook

`playbooks/install-node-exporter.yml`

```yaml
- name: Install Node Exporter
  hosts: node_exporters
  become: yes

  tasks:
    - name: Install curl
      package:
        name: curl
        state: present

    - name: Create directories
      file:
        path: "{{ item }}"
        state: directory
        owner: setup
        group: setup
      loop:
        - "{{ install_root }}"
        - "{{ package_dir }}"
        - "{{ bin_dir }}"
        - "{{ textfile_dir }}"

    - name: Copy package
      copy:
        src: "../files/node_exporter-1.10.2.linux-amd64.tar.gz"
        dest: "{{ package_dir }}/"

    - name: Extract package
      unarchive:
        src: "{{ package_dir }}/node_exporter-1.10.2.linux-amd64.tar.gz"
        dest: "{{ package_dir }}"
        remote_src: yes

    - name: Copy binary
      copy:
        src: "{{ package_dir }}/node_exporter-1.10.2.linux-amd64/node_exporter"
        dest: "{{ bin_dir }}/node_exporter"
        mode: "0755"
        remote_src: yes

    - name: Create service
      template:
        src: "../templates/node_exporter.service.j2"
        dest: /etc/systemd/system/node_exporter.service

    - name: Reload systemd
      command: systemctl daemon-reload

    - name: Start service
      systemd:
        name: node_exporter
        enabled: yes
        state: started
```

---

# 14. Test kết nối Ansible

```bash
ansible node_exporters -m ping
```

---

# 15. Deploy Node Exporter

```bash
ansible-playbook playbooks/install-node-exporter.yml -K
```

---

# 16. Kiểm tra

```bash
curl http://172.16.0.3:9100/metrics
```

---

# 17. Sau khi deploy xong (bảo mật)

Khuyến nghị bật lại key-only:

```bash
sudo sed -i 's/^#AuthenticationMethods publickey/AuthenticationMethods publickey/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

---

# 📈 Scale lên 80 VM

* Thêm IP vào `hosts.txt`
* Thêm vào `inventory.ini`
* Chạy lại:

```bash
ansible-playbook playbooks/install-node-exporter.yml
```

---

# 🧠 Lưu ý

* Mở port:

  * `22` (SSH)
  * `9100` (Node Exporter)
* Node Exporter không lưu data
* Data được Prometheus lưu tại:

```
/data/prometheus
```

---

# 🎯 Kết quả

* Deploy hàng loạt Node Exporter
* Quản lý tập trung bằng Ansible
* Sẵn sàng tích hợp Prometheus & Grafana

---
