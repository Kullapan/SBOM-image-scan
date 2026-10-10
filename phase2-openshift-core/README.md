# Phase 2: OpenShift Core Infrastructure

ชุด Manifests สำหรับติดตั้งระบบบริหารจัดการ SBOM (Dependency-Track & PostgreSQL) บน Red Hat OpenShift:

## ส่วนประกอบ Manifests
1. **`namespace.yaml`**: Namespace `secops-sbom` พร้อม Pod Security Admission ระดับ `restricted`
2. **`imagestreams/` & `buildconfigs/`**: ImageStreams และ BuildConfigs สำหรับทั้ง 4 Images ภายในคลัสเตอร์
3. **`postgres/`**: Dedicated PostgreSQL Deployment, Service, Secret, และ PVC ขนาด 100 GiB
4. **`dtrack-api-all.yaml`**: Dependency-Track API Server Deployment, Service, และ PVC 50 GiB สำหรับ Index
5. **`dtrack-frontend-all.yaml`**: Web UI Deployment (Nginx Non-root), Service, และ Route TLS
6. **`configmap-proxy.yaml`**: คอนฟิก Corporate HTTP/HTTPS Proxy สำหรับการเชื่อมต่อไปยัง NVD feeds
7. **`network-policy.yaml`**: NetworkPolicy จำกัด Ingress/Egress เฉพาะทราฟฟิกที่จำเป็น

## ลำดับขั้นตอนการติดตั้งบน OpenShift
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
