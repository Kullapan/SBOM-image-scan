# Project Plan and Work Tasks: SBOM & Vulnerability Management System

## 1. Project Overview & Objectives
ระบบบริหารจัดการ Software Bill of Materials (SBOM), ช่องโหว่ความปลอดภัย (CVE), และ Outdated Dependencies ส่วนกลาง โดยเปลี่ยนผ่านจากวิธี Git Clone มาใช้ **Container Image-Centric Approach** ดึง Image จาก OpenShift Internal Registry (และ Docker Socket ในช่วง PoC) สแกนด้วย **Trivy** เพื่อสร้าง CycloneDX JSON และนำเข้าสู่ **OWASP Dependency-Track** พร้อมจัดกลุ่ม Hierarchical Portfolio แบบอัตโนมัติ

---

## 2. Work Breakdown Structure (WBS) & Milestones

```
SBOM-image-scan/
├── Phase 1: Local PoC (Docker Desktop / Docker Compose)
├── Phase 2: OpenShift Core Deployment (Dependency-Track & Database)
├── Phase 3: Ephemeral Worker Job (Trivy Scanner on OpenShift)
└── Phase 4: Automation & Reconciliation (Reserved)
```

### Milestone Summary
- [x] **M0: Architecture & Requirement Alignment** - ตกผลึกสถาปัตยกรรม, กฎ Naming Convention, นโยบายการแยก 4 Dockerfile
- [ ] **M1: Core Images & Local PoC (Phase 1)** - Dockerfile สำหรับ 4 Images, Docker Compose, Scan Script, Sample Testing
- [ ] **M2: OpenShift Manifests & RBAC (Phase 2 & 3)** - OpenShift BuildConfigs, ImageStreams, Deployments, Routes, K8s Scanner Job
- [ ] **M3: End-to-End Verification** - ทดสอบสแกนข้าม Namespace และแสดงผลบน Portfolio View

---

## 3. Detailed Task Checklist

### Phase 1: Custom Images & Local PoC
- [x] **Task 1.1:** จัดทำเอกสารสถาปัตยกรรม แผนงาน และกติกาการตั้งชื่อ Image ใน `docs/`
- [x] **Task 1.2:** สร้าง Shared Scripts (`scripts/parse-image.sh`, `scripts/dtrack-client.sh`)
- [x] **Task 1.3:** สร้าง Dockerfiles ทั้ง 4 ตัวใน `images/`:
  - `images/postgres/` (Hardened PostgreSQL 15, OpenShift GID 0, Custom config & Init SQL)
  - `images/dtrack-apiserver/` (Dependency-Track API Server, Corporate Proxy & CA support)
  - `images/dtrack-frontend/` (Nginx unprivileged Port 8080)
  - `images/trivy-scanner/` (Trivy + curl + jq + `scan-and-upload.sh` entrypoint)
- [x] **Task 1.4:** สร้าง `phase1-local-poc/docker-compose.yml` และ `.env.example`
- [x] **Task 1.5:** สร้างสคริปต์ `phase1-local-poc/scan-local-image.sh` และ `phase1-local-poc/build-sample-image.sh` (รองรับ Flag `--sample`)
- [x] **Task 1.6:** จัดเตรียม `phase1-local-poc/test-samples/` สำหรับจำลอง Image ทดสอบ (Node.js App พร้อมช่องโหว่ CVE)
- [x] **Task 1.7:** ทดสอบการบิลด์และรัน Local PoC ตรวจสอบการ Ingest เข้า Dependency-Track (ผ่านการทดสอบ 16/16 Test Cases)

### Phase 2: OpenShift Core Infrastructure
- [ ] **Task 2.1:** จัดเตรียม OpenShift BuildConfigs & ImageStreams สำหรับทั้ง 4 Images ใน Namespace `secops-sbom`
- [ ] **Task 2.2:** สร้าง PersistentVolumeClaim (PVC 50-100 GiB) และ Deployment สำหรับ PostgreSQL
- [ ] **Task 2.3:** สร้าง ConfigMap / Secret สำหรับ Database Credentials และ Corporate Proxy
- [ ] **Task 2.4:** สร้าง Deployment & Service สำหรับ Dependency-Track API Server
- [ ] **Task 2.5:** สร้าง Deployment, Service และ OpenShift Route (TLS) สำหรับ Frontend Web UI
- [ ] **Task 2.6:** กำหนด NetworkPolicy สำหรับจำกัด Traffic ให้เฉพาะ Services ภายใน

### Phase 3: OpenShift Ephemeral Worker Job
- [ ] **Task 3.1:** สร้าง ServiceAccount (`sbom-scanner-sa`) และ RoleBinding สิทธิ์ `system:image-puller` ข้าม Namespace
- [ ] **Task 3.2:** สร้าง Kubernetes Job Template สำหรับ Trivy Scanner ภายใต้ Restricted SCC (`runAsNonRoot`, `readOnlyRootFilesystem`, `capabilities.drop: ALL`)
- [ ] **Task 3.3:** ทดสอบการดึง Image ข้าม Namespace จาก OpenShift Internal Registry ผ่าน SA Token
- [ ] **Task 3.4:** สคริปต์ Trigger Job บน OpenShift ด้วย `oc create -f`

### Phase 4: Automation & Scheduled Audit (Future Scope)
- [ ] **Task 4.1:** ออกแบบ CronJob Template (`cronjob-weekly-audit.yaml`) สำหรับ Re-scan Image ย้อนหลัง
- [ ] **Task 4.2:** รวบรวมข้อกำหนดสำหรับ Event Receiver Service สำหรับดักจับ `ImageStreamTag` Events

---

## 4. Acceptance Criteria & Definition of Done (DoD)
1. **Zero Code Execution:** การสกัด SBOM กระทำผ่าน Static File Layer Inspection เท่านั้น ไม่รัน Application Container
2. **Container-Centric:** ทุกกระบวนการ (Trivy, D-Track API, Frontend, Postgres) ทำงานภายใน Container ทั้งหมด
3. **No External Dependencies on Host:** การทดสอบในเครื่องต้องการเพียง Docker Engine เท่านั้น
4. **Restricted SCC Compliant:** Container ทุกตัวไม่ใช้สิทธิ์ Root และพร้อมทำงานบน OpenShift
5. **Portfolio Hierarchy Mapping:** ระบบสามารถแปลง `[registry/]<appName>/<serviceName>:<tag>` ไปเป็น Parent App และ Child Microservice ใน Dependency-Track ได้อย่างถูกต้อง
