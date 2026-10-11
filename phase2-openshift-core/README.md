# Phase 2: OpenShift Core Infrastructure

> 📖 **คู่มือฉบับสมบูรณ์:** ดูรายละเอียดสถาปัตยกรรม, Scoped RBAC, และขั้นตอนทั้งหมดได้ที่ **[OpenShift Deployment & Operations Guide](../docs/openshift-guide.md)**

ชุด Manifests สำหรับติดตั้งระบบบริหารจัดการ SBOM (Dependency-Track & PostgreSQL) บน Red Hat OpenShift:

## ส่วนประกอบ Manifests
1. **`namespace.yaml`**: Namespace `secops-sbom` พร้อม Pod Security Admission ระดับ `restricted` และ User Workload Monitoring
2. **`imagestreams/` & `buildconfigs/`**: ImageStreams และ BuildConfigs สำหรับทั้ง 4 Images ภายในคลัสเตอร์
3. **`postgres/`**: Dedicated PostgreSQL Deployment (SCLOrg/RHEL-native), Service, Secret, และ PVC ขนาด 100 GiB
4. **`dtrack-api-all.yaml`**: Dependency-Track API Server Deployment, Service, PVC 50 GiB และ StartupProbe (สูงสุด 10 นาที)
5. **`dtrack-frontend-all.yaml`**: Web UI Deployment (Nginx Non-root, Read-only Rootfs), Service, และ Route TLS พร้อม Lazy DNS Resolution
6. **`configmap-proxy.yaml`**: คอนฟิก Corporate HTTP/HTTPS Proxy (ทั้ง upper และ lowercase) สำหรับการเชื่อมต่อไปยัง NVD feeds
7. **`network-policy.yaml`**: NetworkPolicy แยกราย Workload (Least Privilege) จำกัด DNS 53/5353, DB Ingress เฉพาะ API, Scanner Egress 6443/5000/8080
8. **`local-sim/`**: ชุดเครื่องมือจำลอง OpenShift Restricted SCC บน Docker Local ก่อนขึ้นคลัสเตอร์จริง

---

## 🧪 การทดสอบจำลองบนเครื่อง Local (Pre-Flight Test)
หากยังไม่สามารถเข้าถึงคลัสเตอร์ OpenShift จริง สามารถจำลองสภาพแวดล้อมความปลอดภัย (Restricted SCC) บนเครื่อง Local ได้ด้วย Docker:

```powershell
# รันบน Windows PowerShell:
.\phase2-openshift-core\local-sim\test-local-sim.ps1
```

```bash
# รันบน Linux / macOS / WSL (Bash):
./phase2-openshift-core/local-sim/test-local-sim.sh
```

---

## ลำดับขั้นตอนการติดตั้งบน OpenShift จริง
```bash
# 1. สร้าง Namespace
oc apply -f namespace.yaml

# 2. สร้าง ImageStreams และ BuildConfigs
oc apply -f imagestreams/imagestreams.yaml
oc apply -f buildconfigs/buildconfigs.yaml

# สั่ง Build Images
oc start-build bc-postgres-dtrack -n secops-sbom
oc start-build bc-dtrack-apiserver -n secops-sbom
oc start-build bc-dtrack-frontend -n secops-sbom
oc start-build bc-trivy-scanner -n secops-sbom

# 3. ติดตั้ง Database
oc apply -f postgres/postgres-all.yaml

# 4. ตั้งค่า Proxy และ Deploy Dependency-Track
oc apply -f configmap-proxy.yaml
oc apply -f dtrack-api-all.yaml
oc apply -f dtrack-frontend-all.yaml
oc apply -f network-policy.yaml

# ตรวจสอบ Route URL
oc get route dependency-track -n secops-sbom
```

## 5. การตั้งค่าหลังการติดตั้ง (Post-Deployment Setup)
1. **เข้าสู่ระบบครั้งแรกผ่าน Route:**
   * เปิด URL จาก `oc get route dependency-track -n secops-sbom` (เช่น `https://dependency-track-secops-sbom.apps.cluster.domain`)
   * ล็อกอินด้วย Default credentials: `admin` / `admin`
   * ระบบจะบังคับให้เปลี่ยนรหัสผ่านเป็นรหัสผ่านใหม่ที่ปลอดภัย (เช่น `Admin12345!`)
2. **สร้าง Automation Team & API Key สำหรับ Phase 3:**
   * ไปที่ **Administration -> Access Management -> Teams**
   * กด **Create Team** ตั้งชื่อ `Automation`
   * มอบสิทธิ์ (Permissions):
     * `BOM_UPLOAD`
     * `PROJECT_CREATION_UPLOAD`
     * `PORTFOLIO_MANAGEMENT`
     * `VIEW_PORTFOLIO`
     * `VIEW_VULNERABILITY`
     * `VULNERABILITY_ANALYSIS`
   * กดสร้าง **API Key** แล้วคัดลอกคีย์มาสร้าง Secret สำหรับ Phase 3:
     ```bash
     oc create secret generic dtrack-automation-key \
       --from-literal=API_KEY="<YOUR_COPIED_API_KEY>" \
       -n secops-sbom
     ```
