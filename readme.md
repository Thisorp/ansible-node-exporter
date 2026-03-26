# 🚀 Deploy Node Exporter bằng Ansible (Production Style)

---

# 📌 Mục tiêu

Triển khai Node Exporter lên nhiều VM theo chuẩn production:

* Binary cài tại:

```
/usr/local/bin/node_exporter
```

* Chạy bằng user:

```
node_exporter
```

* Chỉ tải bộ cài tại node-1
* Các VM đích **không cần internet**
* Sử dụng `sshpass` để bootstrap SSH key
* Quản lý bằng Ansible + systemd

---

# 🧱 Kiến trúc

```text
Node-1 (172.16.0.2)
 ├── Ansible
 ├── Node Exporter binary
 └── Prometheus

        │ SSH (22)
        ▼
Target Nodes
 ├── node_exporter (systemd)
 └── expose :9100

        ▲
        │ scrape
Prometheus (:9090)
```

---

# 🔁 Luồng triển khai

```text
1. Node-1 tải node_exporter từ GitHub
2. Node-1 giải nén và lấy binary
3. Copy binary vào thư mục files/ của Ansible
4. sshpass push SSH key sang các VM
5. Ansible deploy:
   - tạo user node_exporter
   - copy binary → /usr/local/bin
   - tạo systemd service
   - enable + start service
6. Node Exporter expose port 9100
7. Prometheus scrape metrics
```

---

# 🌐 Network Requirements

## Inbound

| Port | Purpose                 |
| ---- | ----------------------- |
| 22   | SSH (Ansible + sshpass) |
| 9100 | Node Exporter           |
| 9090 | Prometheus              |

---

## Outbound (chỉ node-1)

### GitHub (download binary)

* github.com
* github-releases.githubusercontent.com
* objects.githubusercontent.com

### APT (cài sshpass)

* archive.ubuntu.com
* security.ubuntu.com

Port:

```
TCP 443
TCP 80
```

---

# ⚙️ 1. Chuẩn bị trên Node-1

## Tải và giải nén Node Exporter

```bash
cd /home/setup

wget https://github.com/prometheus/node_exporter/releases/download/v1.10.2/node_exporter-1.10.2.linux-amd64.tar.gz
tar -xvf node_exporter-1.10.2.linux-amd64.tar.gz
```

## Copy binary vào project

```bash
cp node_exporter-1.10.2.linux-amd64/node_exporter ~/ansible-node-exporter/files/
chmod +x ~/ansible-node-exporter/files/node_exporter
```

---

# 🔐 2. Bootstrap SSH (sshpass)

## Tạo SSH key

```bash
ssh-keygen -t ed25519 -C "setup@node-01"
```

## Push key hàng loạt

```bash
export SSHPASS='your_password'

while read -r ip; do
  sshpass -e ssh-copy-id -o StrictHostKeyChecking=no setup@$ip
done < ~/ansible-node-exporter/hosts.txt

unset SSHPASS
```

👉 Sau bước này:

* SSH không cần password
* Ansible hoạt động ổn định

---

# 📦 3. Deploy bằng Ansible

## Test kết nối

```bash
ansible node_exporters -m ping
```

## Cài đặt

```bash
ansible-playbook playbooks/install-node-exporter.yml -K
```

---

# 🔍 4. Verify

## Trên node đích

```bash
systemctl status node_exporter
```

```bash
ss -lntp | grep 9100
```

```bash
curl http://localhost:9100/metrics
```

---

## Trên Prometheus

Truy cập:

```
http://<prometheus-ip>:9090
```

Kiểm tra:

```
Status → Targets
```

Query:

```
up
```

---

# 🔁 5. Scale lên nhiều VM

* Thêm IP vào `hosts.txt`
* Thêm vào `inventory.ini`

Chạy lại:

```bash
ansible-playbook playbooks/install-node-exporter.yml
```

---

# 🔐 6. Lưu ý bảo mật

* `sshpass` chỉ dùng cho bootstrap ban đầu
* Sau khi push key → không cần dùng lại
* Không mở port 9100 ra public
* Chỉ allow Prometheus server truy cập

---

# 🎯 Kết quả

* Node Exporter chạy bằng systemd
* Chạy user riêng (secure)
* Không phụ thuộc internet trên VM
* Deploy hàng loạt bằng Ansible
* Sẵn sàng tích hợp Prometheus / Grafana

---

# 🔥 Best Practice

* Deploy theo batch (serial)
* Verify sau mỗi lần rollout
* Dùng SSH key thay vì password
* Hạn chế expose port 9100

---
