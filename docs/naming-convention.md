# Image Naming Convention & Dependency-Track Portfolio Mapping

## 1. Overview
เพื่อรองรับ **FR-3.1 (Automated Project Provisioning)** และ **FR-3.2 (Hierarchical Portfolio Mapping)** ระบบจะสกัดโครงสร้างโปรเจกต์ระดับแม่ (Parent Application) และโปรเจกต์ระดับลูก (Child Microservice) จากชื่อ Container Image โดยอัตโนมัติ

---

## 2. Naming Convention Standard

รูปแบบ Image Name ที่รองรับ:

```text
[<REGISTRY_HOST>/]<APP_NAME>/<SERVICE_NAME>:<TAG>
```

### การจับคู่ (Mapping Fields)

| ส่วนประกอบของ Image Name | Field ใน Dependency-Track | ความหมายเชิงธุรกิจ | ตัวอย่าง |
| :--- | :--- | :--- | :--- |
| `<APP_NAME>` | `parentName` | ระบบหรือแอปพลิเคชันหลัก (Portfolio Parent) | `ecommerce-platform`, `core-banking` |
| `DEFAULT_PARENT_VERSION` | `parentVersion` | เวอร์ชันของระบบหลัก (Default: `main` หรือ `latest`) | `main` |
| `<SERVICE_NAME>` | `projectName` | ไมโครเซอร์วิส / โมดูลย่อย (Child Component) | `payment-api`, `user-auth` |
| `<TAG>` | `projectVersion` | เวอร์ชันหรือ Release Tag ของ Microservice | `v1.2.0`, `build-482`, `latest` |

---

## 3. ตัวอย่างการสกัดค่า (Parsing Examples)

### ตัวอย่าง 1: Image จาก OpenShift Internal Registry
* **Image Input:**
  `image-registry.openshift-image-registry.svc:5000/ecommerce-prod/payment-service:v2.1.4`
* **ผลการสกัด:**
  * `REGISTRY`: `image-registry.openshift-image-registry.svc:5000`
  * `PARENT_NAME`: `ecommerce-prod`
  * `PARENT_VERSION`: `main`
  * `PROJECT_NAME`: `payment-service`
  * `PROJECT_VERSION`: `v2.1.4`

### ตัวอย่าง 2: Local Docker Image (PoC)
* **Image Input:**
  `digital-wallet/transfer-worker:1.0.0`
* **ผลการสกัด:**
  * `REGISTRY`: (none / local)
  * `PARENT_NAME`: `digital-wallet`
  * `PARENT_VERSION`: `main`
  * `PROJECT_NAME`: `transfer-worker`
  * `PROJECT_VERSION`: `1.0.0`

### ตัวอย่าง 3: Image เดี่ยว (Fallback หากไม่มี Slash คั่น App)
* **Image Input:**
  `my-standalone-service:3.0.0`
* **ผลการสกัด:**
  * `PARENT_NAME`: `default-portfolio`
  * `PARENT_VERSION`: `main`
  * `PROJECT_NAME`: `my-standalone-service`
  * `PROJECT_VERSION`: `3.0.0`

---

## 4. API Request Payload เข้าสู่ Dependency-Track (`/api/v1/bom`)

สคริปต์สแกนจะส่ง Request ในรูปแบบ `multipart/form-data` หรือ JSON ดังนี้:

```bash
curl -s -X POST "http://${DTRACK_HOST}/api/v1/bom" \
  -H "X-Api-Key: ${DTRACK_API_KEY}" \
  -H "Content-Type: multipart/form-data" \
  -F "autoCreate=true" \
  -F "projectName=${PROJECT_NAME}" \
  -F "projectVersion=${PROJECT_VERSION}" \
  -F "parentName=${PARENT_NAME}" \
  -F "parentVersion=${PARENT_VERSION}" \
  -F "bom=@/tmp/bom.json"
```

หลังจากนั้น Dependency-Track จะ:
1. สร้าง Parent Project (หากยังไม่มี)
2. สร้าง Child Project และผูกเข้าเป็น Sub-project ภายใต้ Parent อัตโนมัติ
3. รวม (Roll-up) สถิติ Vulnerabilities และ Outdated Components ขึ้นสู่ระดับ Parent ให้โดยอัตโนมัติ

## 5. Multi-Version Handling (Latest by Image Creation Date)

When several tags of the same image (same Parent + Child name) are scanned, "latest" is decided by the **image creation date** (`ImageConfig.created`), not by tag name.

| Scenario | Result |
|---|---|
| Same tag re-scanned | BOM of that version is overwritten |
| New tag, image created **later** than existing versions | New version stays **active**; older versions set to **inactive** (kept, not deleted) |
| New tag, image created **earlier** than an existing version | The scanned version is set to **inactive** |
| Existing version without creation-date tag | Treated as oldest |

* The creation time is stored as project tag `image-created:<ISO datetime>` normalised to **UTC+7**, e.g. `image-created:2026-10-10T14:55:13+07:00` (legacy epoch tags are still read). Source timestamps with `Z` or `±hh:mm` offsets are converted correctly; fractional seconds are dropped.
* Inactive projects are excluded from the Dashboard and portfolio metrics but remain viewable (*Show inactive projects*).
* Equal creation dates: the most recently scanned version stays active.
* Avoid using the `latest` tag as a version, since it overwrites itself on every scan.
* Dependency-Track lowercases tags, so the UI shows `image-created:2026-10-10t14:55:13+07:00` (lowercase `t`). The script handles this when reading tags back.

### Known limitation

"Latest" is decided **only by image build date, not by version number**. If an old tag is **rebuilt** (e.g. `0.9.0` rebuilt while `1.2.0` exists) and then scanned, the new build has a newer creation date and becomes **active** instead of `1.2.0`.

Re-scanning an old image **without rebuilding** is safe: its creation date is unchanged, so it stays inactive.

Mitigation (not enforced by this system): make tags immutable in the registry and avoid rebuilding an existing tag.

### Verified test results (Phase 1)

| Step | Result |
|---|---|
| Scan `v1.2.0` (created 16:45:36+07:00, newer) | `v1.2.0` active; `v1.1.0`, `v1.0.0`, `v0.9.0` inactive |
| Re-scan `v0.9.0` (created 14:55:13+07:00, older) | `v0.9.0` inactive; `v1.2.0` stays active |
| Same creation date (retagged image) | Most recently scanned version stays active |
| Source timestamp with `Z` | Converted correctly to UTC+7 |
| Source timestamp with `±hh:mm` offset | Logic implemented, not tested with a real image |
