# Phase 3: Ephemeral Worker Job on OpenShift

> 📖 **คู่มือฉบับสมบูรณ์:** ดูรายละเอียดสถาปัตยกรรม, Scoped RBAC, และขั้นตอนทั้งหมดได้ที่ **[OpenShift Deployment & Operations Guide](../docs/openshift-guide.md)**

ระบบสแกน SBOM ระดับ Production บน Red Hat OpenShift โดยใช้ **Ephemeral Kubernetes Job** ร่วมกับ Container Image `trivy-scanner` ที่ติดตั้ง `trivy` + `oc` CLI ในตัว

---

## 🔒 มาตรฐานความปลอดภัย (Security Controls)

1. **Restricted SCC 100%:**
   * รันด้วยสิทธิ์ Non-root (`runAsNonRoot: true`)
   * ปิดการยกระดับสิทธิ์ (`allowPrivilegeEscalation: false`)
   * ตัด Capabilities ทั้งหมด (`capabilities.drop: ["ALL"]`)
   * บังคับ Read-only Root Filesystem (`readOnlyRootFilesystem: true`) โดย Mount `emptyDir` ที่ `/tmp`
2. **Scoped RBAC (Option 1 - ไม่ต้องใช้ ClusterRole):**
   * Pod ผูกกับ ServiceAccount `sbom-scanner-sa` ใน `secops-sbom`
   * ได้รับสิทธิ์เฉพาะใน Namespace ที่ Onboard ผ่าน Built-in Roles:
     * `system:image-puller`: ดึง Image Layers จาก OpenShift Internal Registry (Port 5000)
     * `view`: อ่าน Metadata ของ ImageStream เพื่อดึง Creation Timestamp และค้นหา Images
3. **Zero Code Execution:**
   * Trivy อ่านเฉพาะ File Layers ของ Image เท่านั้น ไม่มีการรัน Application Container เป้าหมาย

---

## 🚀 ขั้นตอนการติดตั้งและทดสอบรัน Job บน OpenShift

### 1. ติดตั้ง ServiceAccount ประจำระบบ SecOps
```bash
# สร้าง ServiceAccount ใน Namespace secops-sbom
oc apply -f rbac/serviceaccount.yaml
```

### 2. Onboard Namespace แอปพลิเคชันเป้าหมาย (ทำทีละ Namespace ที่อนุญาต)
ใช้สิทธิ์ระดับ Project Admin ของ Namespace นั้นๆ สั่ง Apply:
```bash
# ตัวอย่าง: Onboard namespace ecommerce-prod
oc apply -f rbac/onboard-namespace-rbac.yaml -n ecommerce-prod

# ตัวอย่าง: Onboard namespace core-banking
oc apply -f rbac/onboard-namespace-rbac.yaml -n core-banking
```
*(หรือใช้คำสั่ง CLI: `oc policy add-role-to-user system:image-puller system:serviceaccount:secops-sbom:sbom-scanner-sa -n ecommerce-prod` และ `oc policy add-role-to-user view system:serviceaccount:secops-sbom:sbom-scanner-sa -n ecommerce-prod`)*

### 3. สร้าง Secret สำหรับ Dependency-Track API Key
```bash
oc create secret generic dtrack-automation-key \
  --from-literal=API_KEY="<YOUR_DTRACK_API_KEY>" \
  -n secops-sbom
```

---

## 🎯 รูปแบบการสั่งรัน 2 โหมด

### โหมดที่ 1: Targeted Mode (สำหรับ CI/CD Pipeline ระบุ Image เฉพาะเจาะจง)
เมื่อ Pipeline ทำการ Build Image ใหม่เสร็จ สามารถสั่ง Trigger สแกน Image นั้นทันที:
```bash
./test-job-run.sh image-registry.openshift-image-registry.svc:5000/ecommerce-prod/payment-service:v1.2.0 main
```
* สคริปต์ใน Pod จะใช้ `oc get is` ดึง Creation Date จาก ImageStream `payment-service` ใน `ecommerce-prod`
* ทำการ Ingest CycloneDX SBOM เข้า Dependency-Track และ Reconcile Version อัตโนมัติ จบใน 30–60 วินาที

### โหมดที่ 2: Scoped Auto-Discovery Mode (สำหรับ Weekly Audit / All-Projects Scan)
สั่งสแกนทุก Image ในทุก Namespace ที่ ServiceAccount ได้รับสิทธิ์ โดยไม่ต้องพิมพ์ชื่อ Image:
```bash
./test-job-run.sh ALL
# หรือสั่งสั้นๆ
./test-job-run.sh
```
* สคริปต์ใน Pod จะรัน `oc get projects` ค้นหา Namespace ที่มีสิทธิ์ทั้งหมด (ข้าม namespace ระบบ เช่น `openshift-*`, `kube-*`)
* วนลูปอ่าน ImageStream และสแกนครบทุกตัวในคลัสเตอร์อย่างปลอดภัย
