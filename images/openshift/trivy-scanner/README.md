# Trivy Scanner Image (Hardened for OpenShift)

Container Image สำหรับรัน Ephemeral SBOM Scanner & Ingestion Worker บน Red Hat OpenShift:

## จุดเด่น
1. **Base Image:** พัฒนาบนฐาน **Red Hat Universal Base Image 9 (`registry.access.redhat.com/ubi9/ubi-minimal:latest`)**
2. **License & Cost:** **ฟรี 100% ไม่มีค่าใช้จ่ายและไม่ต้องมี Red Hat Subscription** ภายใต้สัญญาอนุญาต *Red Hat UBI EULA* สามารถนำไปใช้งาน พัฒนา และแจกจ่ายต่อได้ทั้งในเชิงพาณิชย์และทั่วไป
3. **Roadmap & Lifecycle:** ซัพพอร์ตระยะยาวถึง **ปี 2032 (10-Year Lifecycle)** พร้อมรับการแพตช์ช่องโหว่ความปลอดภัย (CVE patches) อย่างต่อเนื่องจาก Red Hat
4. **Native glibc Compatibility:** บรรจุ `oc` CLI จาก `quay.io/openshift/origin-cli:4.14` และไบนารี `trivy:0.59.1` รันบน native glibc อย่างมีเสถียรภาพ (แก้ปัญหา crash บน Alpine/gcompat)
5. **Restricted SCC Compliant:** กำหนดสิทธิ์ Group 0 บน `/tmp` และรองรับ `readOnlyRootFilesystem: true`
6. **Build-time Smoke Test:** ตรวจสอบความพร้อมของ `trivy`, `oc`, `jq`, `curl` ตั้งแต่ขั้นตอน Build
7. **Entrypoint Script (`scan-openshift.sh`):**
   * รองรับทั้งโหมด Targeted Scan (CI/CD) และ Scoped Auto-Discovery (`ALL`)
   * รองรับ OpenShift Service CA Certificate Bundle (`service-ca.crt`)
   * ดึง Creation Date จาก ImageStream และ Reconcile Version Active/Inactive ใน Dependency-Track อัตโนมัติ

## การ Build และทดสอบในเครื่อง
```bash
docker build -t ocp-sim-trivy-scanner:latest .
docker run --rm --user 1000680000:0 --cap-drop ALL --read-only --tmpfs /tmp ocp-sim-trivy-scanner:latest trivy --version
```
