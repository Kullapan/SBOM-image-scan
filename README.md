# SBOM & Image Vulnerability Management System

ระบบบริหารจัดการ Software Bill of Materials (SBOM), ช่องโหว่ความปลอดภัย (CVE), และ Outdated Dependencies ส่วนกลางด้วย **Container Image-Centric Approach** สำหรับ OpenShift และ Docker

---

## 📁 โครงสร้างโปรเจกต์ (Project Structure)

* **`docs/`**: เอกสารสถาปัตยกรรม แผนงาน (`plan-and-tasks.md`), Naming Convention และ [คู่มือรายงาน (`reports.md`)](docs/reports.md)
* **`images/`**: Dockerfiles สำหรับบิลด์ Image ทั้ง 4 ตัวเข้า Internal Registry
  * `postgres/`: Hardened PostgreSQL สำหรับ OpenShift Arbitrary UID
  * `dtrack-apiserver/`: Dependency-Track API Server
  * `dtrack-frontend/`: Dependency-Track Web UI (Unprivileged Nginx Port 8080)
  * `trivy-scanner/`: Ephemeral Scanner Image (Trivy + curl + jq + scan script)
* **`phase1-local-poc/`**: สภาพแวดล้อมทดสอบ Local PoC ด้วย Docker Compose และสคริปต์สแกน
* **`phase2-openshift-core/`**: Manifests ติดตั้งบน OpenShift (`secops-sbom`)
* **`phase3-ephemeral-worker/`**: K8s Job และ RBAC สำหรับรัน Ephemeral Trivy Scanner
* **`phase4-automation/`**: เทมเพลต CronJob และแนวทางการต่อขยายอัตโนมัติ
* **`scripts/`**: Shared POSIX Bash utilities สำหรับสกัดชื่อ Image และเชื่อมต่อ D-Track API

---

## 🚀 การเริ่มต้นใช้งาน Local PoC (Phase 1 Quickstart)

1. เข้าไปยังโฟลเดอร์ PoC:
   ```bash
   cd phase1-local-poc
   ```
2. คัดลอกและตั้งค่า Environment Variables:
   ```bash
   cp .env.example .env
   ```
3. สตาร์ท Stack (Database, API Server, Frontend):
   ```bash
   docker compose up -d --build
   ```
4. รอจนกระทั่ง Dependency-Track สตาร์ทเสร็จสิ้น เข้าสู่ UI ที่ `http://localhost:8080`
   * เข้าสู่ระบบด้วย `admin` / `admin` (ระบบจะให้เปลี่ยนรหัสผ่านในครั้งแรก)
   * ไปที่ **Administration -> Access Management -> Teams -> Automation** แล้วคัดลอก **API Key** มาใส่ใน `.env`
5. สั่งสแกน Image ในเครื่อง:
   ```bash
   ./scan-local-image.sh --sample
   ```
6. ดูและ Export Total SBOM รวมทุกโปรเจกต์:
   ```bash
   python ../scripts/export-total-sbom.py
   ```
7. Export รายงานช่องโหว่ (Vulnerability) ทั้งหมดของทุกโปรเจกต์:
   ```bash
   python ../scripts/export-vulnerability-report.py                # รวม version ที่ inactive
   python ../scripts/export-vulnerability-report.py --active-only  # เฉพาะ version ล่าสุด (active)
   ```
   ได้ไฟล์ใน `reports/`:
   * `vulnerabilities-detail.csv` — 1 แถวต่อ finding (project × component × CVE) พร้อม Severity, CVSS, CWE, สถานะ analysis, suppressed
   * `vulnerabilities-unique.csv` — 1 แถวต่อ CVE พร้อมจำนวน project/component ที่ได้รับผลกระทบ
   * `vulnerabilities-summary.csv` — สรุปจำนวนตาม Severity ต่อ project

   ถ้ายังไม่มี finding (ฐานข้อมูลช่องโหว่ยัง sync ไม่เสร็จ) จะได้ไฟล์ที่มีเฉพาะหัวคอลัมน์

---

## 🕒 การจัดการหลาย Version (Latest ตามวันที่สร้าง Image)

`scan-and-upload.sh` ใช้ **วันที่สร้าง image (`ImageConfig.created`)** ตัดสินว่า version ไหนล่าสุด ไม่ใช้ชื่อ tag

| กรณี | ผลลัพธ์ |
|---|---|
| tag เดิม สแกนซ้ำ | ทับ BOM เดิมของ version นั้น |
| tag ใหม่ และ image **สร้างใหม่กว่า** | version นี้ **active** และ version เก่าของ project เดียวกันถูกตั้งเป็น **inactive** (ไม่ลบ) |
| tag ใหม่ แต่ image **เก่ากว่า** ที่มีอยู่ | version ที่สแกนถูกตั้งเป็น **inactive** |
| version เก่าที่ยังไม่มี tag วันที่ | นับเป็นเก่าสุด |

* วันที่สร้างเก็บเป็น project tag แบบ ISO datetime เขตเวลา **UTC+7** เช่น `image-created:2026-10-10T14:55:13+07:00` (ดูได้ใน UI ที่ project → Tags; ยังอ่าน tag แบบ epoch รุ่นเก่าได้)
* Project ที่ inactive **ไม่ถูกนับ** ใน Dashboard / portfolio metrics แต่ยังเปิดดูย้อนหลังได้ (เลือก *Show inactive projects*)
* การเทียบทำเฉพาะ project ชื่อเดียวกันภายใต้ Parent เดียวกัน
* ถ้า image สองตัวมีวันที่สร้างเท่ากัน ตัวที่สแกนล่าสุดจะเป็น active
* ไม่ควรใช้ tag `latest` เป็น version เพราะจะทับตัวเองทุกครั้ง
* Dependency-Track แปลง tag เป็นตัวพิมพ์เล็ก ใน UI จึงเห็นเป็น `image-created:2026-10-10t14:55:13+07:00` (ตัว `t` เล็ก) สคริปต์รองรับแล้ว

> [!WARNING]
> **ข้อจำกัดที่ทราบ:** เกณฑ์ "ล่าสุด" ดูจาก **วันที่ build image เท่านั้น ไม่ดูเลข version** ถ้ามีการ build tag เก่าซ้ำ (เช่น rebuild `0.9.0` ทั้งที่มี `1.2.0` อยู่แล้ว) แล้วสแกน image ที่ได้จะมีวันที่สร้างใหม่กว่าและถูกมองเป็น **active** แทน `1.2.0`
> การสแกน image เก่าซ้ำโดย **ไม่ build ใหม่** ไม่เป็นปัญหา เพราะวันที่สร้างไม่เปลี่ยน ตัวเก่าจะเป็น inactive ตามเดิม
> แนวทางป้องกัน (ไม่ได้บังคับในระบบนี้): ตั้ง tag เป็น immutable ที่ registry และไม่ build tag เดิมซ้ำ

---

## 🛡️ ตั้งค่า Vulnerability DB และสั่ง Analyze

> Dependency-Track ใหม่จะ **ไม่มีข้อมูล CVE** จนกว่าจะ mirror ฐานข้อมูลช่องโหว่ ทำให้ Dashboard แสดง `0 Vulnerabilities` แม้มี component แล้ว

### 1. เปิด Vulnerability Sources (Administration → Vulnerability Sources)

| Source | การตั้งค่า |
|---|---|
| **National Vulnerability Database** | เปิดสวิตช์ *Enable NVD mirroring* **และ** *Enable mirroring via API* ใส่ **API key** (ขอฟรีที่ NVD) endpoint `https://services.nvd.nist.gov/rest/json/cve/2.0` ปล่อย *Additionally download feeds* ปิด (feed 1.1 เดิมถูก deprecate ทำให้ connection pool timeout) |
| **Google OSV** | เลือก ecosystem ที่ใช้ เช่น `npm;Alpine` (เลือก Maven เฉพาะเมื่อมี Java เพราะ sync นาน) |
| **GitHub Advisories** | เปิด และใส่ Personal Access Token (ถ้ามี) |

### 2. เปิด Analyzers (Administration → Analyzers)
* **Internal Analyzer**: เปิด (จำเป็น ใช้ match กับ CVE ที่ mirror มา)
* **OSS Index**: เปิดและใส่ token (ไม่บังคับ แต่เห็นผลเร็วเพราะไม่ต้องรอ mirror)

### 3. Restart และรอ mirror
```bash
docker restart dtrack-apiserver
docker logs -f dtrack-apiserver 2>&1 | grep -E "NvdMirror|OsvDownload"
```
ครั้งแรก NVD/OSV ใช้เวลาหลักสิบนาที ตรวจจำนวนที่ดึงมาแล้วได้จาก header `X-Total-Count` ของ `GET /api/v1/vulnerability`

### 4. สั่ง Analyze และรีเฟรช Dashboard
หลัง mirror เสร็จ ให้ Reanalyze ทุก project (UI: เลือก project → **Reanalyze**) หรือผ่าน API:
```bash
curl -X POST -H "X-Api-Key: $API_KEY" http://localhost:8081/api/v1/finding/project/<project-uuid>/analyze
curl -H "X-Api-Key: $API_KEY" http://localhost:8081/api/v1/metrics/portfolio/refresh
```
จากนั้นดูผลที่ project → แท็บ **Audit Vulnerabilities** และหน้า **Dashboard**

### ข้อควรทราบ
* Dashboard เป็น snapshot ตามรอบ metrics ถ้ายังเป็น 0 ให้เรียก `portfolio/refresh`
* การตั้งค่า config ผ่าน API ต้องใช้ API key ที่มีสิทธิ์ `SYSTEM_CONFIGURATION`
* อย่า commit API key (NVD, OSS Index, GitHub) ลง git ให้เก็บใน `.env` หรือ Secret

ดูรายละเอียดเพิ่มเติมได้ที่ [docs/plan-and-tasks.md](docs/plan-and-tasks.md) และ [docs/architecture.md](docs/architecture.md)
