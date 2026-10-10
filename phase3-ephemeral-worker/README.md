# Phase 3: Ephemeral Worker Job on OpenShift

ระบบสแกน SBOM ระดับ Production บน Red Hat OpenShift โดยใช้ **Ephemeral Kubernetes Job** ร่วมกับ Container Image `trivy-scanner`

---

## 🔒 มาตรฐานความปลอดภัย (Security Controls)

1. **Restricted SCC 100%:**
   * รันด้วยสิทธิ์ Non-root (`runAsNonRoot: true`)
   * ปิดการยกระดับสิทธิ์ (`allowPrivilegeEscalation: false`)
   * ตัด Capabilities ทั้งหมด (`capabilities.drop: ["ALL"]`)
   * บังคับ Read-only Root Filesystem (`readOnlyRootFilesystem: true`) โดย Mount `emptyDir` ที่ `/tmp`
2. **Least Privilege ServiceAccount:**
   * Pod ผูกกับ ServiceAccount `sbom-scanner-sa` ใน `secops-sbom`
   * ได้รับสิทธิ์เฉพาะ `system:image-puller` ไปยัง Namespace ที่ต้องการสแกน
3. **Zero Code Execution:**
   * Trivy อ่านเฉพาะ File Layers ของ Image เท่านั้น ไม่มีการรัน Container เป้าหมาย

---

## 🚀 ขั้นตอนการทดสอบรัน Job บน OpenShift

### 1. ติดตั้ง ServiceAccount และสิทธิ์ Pull Image
```bash
# สร้าง ServiceAccount ใน Namespace secops-sbom
oc apply -f rbac/serviceaccount.yaml

# ให้สิทธิ์ ServiceAccount ดึง Image จาก Namespace แอปพลิเคชันเป้าหมาย (เช่น ecommerce-prod)
oc apply -f rbac/rolebinding-image-puller.yaml -n ecommerce-prod
```

### 2. สร้าง Secret สำหรับ Dependency-Track API Key
```bash
oc create secret generic dtrack-automation-key \
  --from-literal=API_KEY="<YOUR_DTRACK_API_KEY>" \
  -n secops-sbom
```

### 3. สั่งสแกน Image ข้าม Namespace
```bash
./test-job-run.sh image-registry.openshift-image-registry.svc:5000/ecommerce-prod/payment-service:v1.0.0 main
```
Job จะทำงานจนจบ (สแกน -> ส่ง CycloneDX -> Poll Token) แล้วสิ้นสุดตัวเองลงภายใน 60–90 วินาที
