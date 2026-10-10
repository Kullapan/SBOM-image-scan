# Architecture: Container-Centric SBOM & Vulnerability Management

## 1. System Overview
ระบบนี้ถูกออกแบบขึ้นเพื่อเปลี่ยนผ่านจากการสแกน Source Code (Git Clone Approach) มาใช้ **Container Image-Centric Approach** เพื่อให้ได้ Software Bill of Materials (SBOM) ตรงตามความจริงของ Production (As-Built Artifacts) โดยตัดความเสี่ยงจากการรัน Build Scripts หรือ Code แปลกปลอมภายใน Infrastructure

```
┌────────────────────────────────────────────────────────────────────────┐
│ OpenShift ImageStream / Internal Registry (or Local Docker Daemon)     │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    │ Inspect Layers (Read-Only)
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Ephemeral Trivy Scanner Pod / Container                                │
│ - Pure Container-based scanning (aquasec/trivy)                        │
│ - Restricted SCC compliant (Non-root, read-only root FS)               │
│ - Generates CycloneDX JSON (v1.5) with full PURL                       │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    │ Ingest CycloneDX via REST API
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ OWASP Dependency-Track                                                 │
│                                                                        │
│   ┌───────────────────────────┐      ┌─────────────────────────────┐   │
│   │    Portfolio Hierarchy    │      │    Vulnerability Engine     │   │
│   │  - Parent: Application    │      │  - NVD, GHSA, OSV, EPSS     │   │
│   │  - Child: Microservices   │      │  - Continuous re-evaluation │   │
│   └───────────────────────────┘      └──────────────┬──────────────┘   │
│                                                     │                  │
│                                                     ▼                  │
│                                      ┌─────────────────────────────┐   │
│                                      │     Repository Analyzer     │   │
│                                      │  - Outdated components      │   │
│                                      │  - Maven, NPM versions      │   │
│                                      └─────────────────────────────┘   │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Dedicated PostgreSQL Database (Tuned for indexing & SBOM components)   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Core Security & Isolation Principles (NFR-1)

1. **Zero Code Execution (NFR-1.1):**
   * การสกัด SBOM ทำงานโดยการ Unpack Image Layer Filesystem แบบ Static เท่านั้น
   * ไม่มีการสั่ง `docker run` หรือรัน Process ใดๆ ของเป้าหมาย
2. **Least Privilege RBAC (NFR-1.2):**
   * Worker Pod บน OpenShift ใช้ ServiceAccount ที่ผูกบทบาท `system:image-puller` ไปยัง Namespace ที่ต้องการสแกนเท่านั้น
3. **OpenShift Restricted SCC Compliance (NFR-1.3):**
   * ทุก Container Image (รวมทั้ง Database, API, Frontend, Trivy Scanner) ออกแบบให้รองรับ OpenShift Arbitrary UID
   * SecurityContext บังคับ:
     * `runAsNonRoot: true`
     * `readOnlyRootFilesystem: true`
     * `allowPrivilegeEscalation: false`
     * `capabilities.drop: ["ALL"]`
     * Mount `emptyDir` ที่ `/tmp` และ Cache Directories
4. **Network Segmentation & Proxy (NFR-1.4):**
   * Pod ติดต่อเฉพาะ Internal Registry และ Dependency-Track API เท่านั้น
   * Dependency-Track รองรับ Corporate HTTP/HTTPS Proxy ในการเข้าถึง NVD / EPSS และ Package Registry

---

## 3. Four Custom In-House Images (`images/`)

เพื่อตอบรับนโยบาย Private Image Registry และ Air-Gap ขององค์กร ทุก Component จะถูกสร้างขึ้นจาก Dockerfile ภายในองค์กร:

| Component | Directory | หน้าที่หลัก | การปรับแต่งสำหรับ OpenShift |
| :--- | :--- | :--- | :--- |
| **PostgreSQL** | `images/postgres/` | ฐานข้อมูลกลางสำหรับ Dependency-Track | สิทธิ์ GID 0 (`chgrp -R 0 ...`), ปรับแต่ง memory สำหรับงาน SBOM |
| **D-Track API** | `images/dtrack-apiserver/` | API Server, Vulnerability matching & Analysis | ปรับสิทธิ์ Non-root, รองรับ Corporate Proxy & Internal CA |
| **D-Track Frontend** | `images/dtrack-frontend/` | Web Dashboard / Management UI | Nginx Unprivileged รันบน Port 8080 |
| **Trivy Scanner** | `images/trivy-scanner/` | Ephemeral Worker สำหรับสแกนและส่งผล | Trivy + `curl` + `jq` + `scan-and-upload.sh` ใน Container เดียว |
