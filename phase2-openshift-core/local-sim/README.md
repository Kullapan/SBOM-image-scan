# OpenShift Restricted SCC Local Simulation Suite

ชุดเครื่องมือจำลองสภาพแวดล้อมความปลอดภัยของ **Red Hat OpenShift (Restricted SCC)** บน Docker ในเครื่อง Local เพื่อทดสอบ Container Images, Scoped RBAC, Trivy CycloneDX SBOM generation, และ Version Lifecycle Reconciliation ก่อน Deploy บนคลัสเตอร์ OpenShift จริง

---

## 🎯 วัตถุประสงค์ (Why Local Simulation?)
1. **ทดสอบมาตรฐาน Restricted SCC:** บังคับใช้ Random UID (`1000680000:0`), `readOnlyRootFilesystem: true`, `cap_drop: [ALL]`, และ `no-new-privileges: true` เสมือน Pod บน OpenShift 100%
2. **ทดสอบ Zero Dependency-Collision:** รันบนพอร์ตเฉพาะ `18080` (Frontend) และ `18081` (API Server) ไม่ชนกับ Phase 1 PoC (พอร์ต 8080/8081)
3. **จำลอง In-Cluster API & ImageStreams:** ใช้ `mock-oc.sh` และ JSON Fixtures จำลองการเรียก `oc get projects` และ `oc get is` สำหรับ Scoped Auto-Discovery
4. **End-to-End Validation:** ตรวจสอบกระบวนการ Ingest SBOM, Token Polling, และ Version Reconciliation (สลับสถานะ Active/Inactive ตาม `image-created` timestamp) ได้แบบสมบูรณ์

---

## 📁 โครงสร้างไฟล์ในชุดจำลอง

```text
phase2-openshift-core/local-sim/
├── docker-compose.ocp-sim.yml  # Compose file ที่คอนฟิกความปลอดภัยระดับ Restricted SCC
├── mock-oc.sh                  # Shell script จำลองคำสั่ง oc CLI ใน OpenShift
├── fixtures/                   # ข้อมูลจำลองสำหรับ mock oc
│   ├── projects.json           # รายชื่อ Namespace ที่ ServiceAccount มีสิทธิ์ (ecommerce-prod, core-banking)
│   ├── is-ecommerce-prod.json  # ImageStream payment-service (v1.0.0, v1.1.0)
│   └── is-core-banking.json    # ImageStream auth-service (v2.0.0)
├── test-local-sim.ps1          # สคริปต์รันการทดสอบอัตโนมัติบน Windows PowerShell
└── test-local-sim.sh           # สคริปต์รันการทดสอบอัตโนมัติบน Linux / macOS / WSL
```

---

## 🚀 วิธีการรันการทดสอบ (How to Run)

### บน Windows PowerShell:
```powershell
# รันการทดสอบแบบ End-to-End:
powershell.exe -ExecutionPolicy Bypass -File .\phase2-openshift-core\local-sim\test-local-sim.ps1

# หากบิลด์อิมเมจไว้แล้วและต้องการรันซ้ำแบบเร็ว:
powershell.exe -ExecutionPolicy Bypass -File .\phase2-openshift-core\local-sim\test-local-sim.ps1 -SkipBuild

# ลบและทำความสะอาดคอนเทนเนอร์จำลองหลังทดสอบเสร็จ:
powershell.exe -ExecutionPolicy Bypass -File .\phase2-openshift-core\local-sim\test-local-sim.ps1 -Cleanup
```

### บน Linux / macOS / WSL (Bash):
```bash
# ให้สิทธิ์ Execute:
chmod +x ./phase2-openshift-core/local-sim/test-local-sim.sh

# รันการทดสอบ:
./phase2-openshift-core/local-sim/test-local-sim.sh
```

---

## 📊 การตรวจสอบผลลัพธ์ผ่าน Dependency-Track Web UI

เมื่อรันสำเร็จ สามารถเข้าชม Dashboard ของชุดจำลองได้ที่:
* **Web UI URL:** [http://localhost:18080](http://localhost:18080)
* **API Server:** [http://localhost:18081](http://localhost:18081)
* **Username:** `admin`
* **Password:** `Admin12345!`

### สิ่งที่ควรเห็นในระบบ:
1. **Portfolio Hierarchy:**
   * Parent Project: `default-portfolio (main)`
2. **Projects & Version Reconciliation:**
   * `custom-sample-auth-service` (`v2.0.0`) -> **Active: True**
   * `custom-sample-payment-service` (`v1.1.0`) (สร้าง Jan 15) -> **Active: True**
   * `custom-sample-payment-service` (`v1.0.0`) (สร้าง Jan 1) -> **Active: False** (ถูก Reconcile เป็น Inactive อัตโนมัติเนื่องจากมีเวอร์ชันที่ใหม่กว่า)
