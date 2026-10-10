# Test Cases Specification: Phase 1 (Local PoC)

เอกสารแผนการทดสอบ เกณฑ์การยอมรับ และผลการรันการทดสอบจริง (Execution Results) ในสภาพแวดล้อม **Phase 1: Local PoC**

---

## 1. วัตถุประสงค์การทดสอบ (Test Objectives)
1. ยืนยันความพร้อมของ **In-House Images ทั้ง 4 ตัว** (`postgres`, `dtrack-apiserver`, `dtrack-frontend`, `trivy-scanner`) ว่าสามารถบิลด์และเชื่อมต่อกันได้อย่างถูกต้อง
2. ยืนยันหลักการ **Zero Code Execution** ว่าการสกัด SBOM เกิดจาก Static Layer Inspection ล้วนๆ ไม่มีการรัน Application Container เป้าหมาย
3. ยืนยันการสกัดชื่อ Image ตาม **Naming Convention** และการจัดกลุ่ม **Parent/Child Portfolio** ใน Dependency-Track แบบอัตโนมัติ
4. ยืนยันการประมวลผล **CycloneDX SBOM (OS + App Packages)**, การจับคู่ CVE, และการแสดงผลบน Web Dashboard

---

## 2. รายละเอียดชุดการทดสอบและผลการทดสอบจริง (Test Matrix & Actual Results)

### กลุ่มที่ 1: การ Build และความสมบูรณ์ของ Custom Images (Infrastructure Tests)

| Test Case ID | หัวข้อการทดสอบ | ขั้นตอนการทดสอบ (Steps) | ผลลัพธ์ที่คาดหวัง (Expected Results) | สถานะ |
| :--- | :--- | :--- | :--- | :---: |
| **TC-P1-01** | ตรวจสอบการ Build 3 Services ใน Compose จาก `images/` | 1. เข้าโฟลเดอร์ `phase1-local-poc/`<br>2. รัน `docker compose up -d --build`<br>3. ตรวจสอบสถานะด้วย `docker compose ps` | • Image `custom-postgres`, `custom-dtrack-apiserver`, `custom-dtrack-frontend` บิลด์สำเร็จ<br>• Container ทั้ง 3 สตาร์ทติดและ Healthcheck ผ่าน (`healthy`) | **PASS** [x] |
| **TC-P1-02** | ตรวจสอบการ Build `trivy-scanner` Image | รันคำสั่ง:<br>`docker build -t custom-trivy-scanner:latest ../images/trivy-scanner` | • Image ขนาด 50.9 MB (<100 MB) บิลด์สำเร็จ<br>• มี binary `trivy`, `curl`, `jq` พร้อมใช้งานภายใน Container | **PASS** [x] |
| **TC-P1-03** | ตรวจสอบการเข้าถึง Web UI | 1. เปิด Browser ไปที่ `http://localhost:8080`<br>2. ล็อกอินด้วย `admin` / `admin`<br>3. ตั้งรหัสผ่านใหม่เป็น `Admin12345!` | • หน้า Dashboard ของ Dependency-Track แสดงผลสมบูรณ์<br>• สามารถสร้าง Automation API Key จากเมนู Administration ได้ | **PASS** [x] |

---

### กลุ่มที่ 2: การสร้าง SBOM และความปลอดภัย (Static Layer Extraction Tests)

| Test Case ID | หัวข้อการทดสอบ | ขั้นตอนการทดสอบ (Steps) | ผลลัพธ์ที่คาดหวัง (Expected Results) | สถานะ |
| :--- | :--- | :--- | :--- | :---: |
| **TC-P1-04** | บิลด์ Sample Application Image | รันคำสั่ง:<br>`./build-sample-image.sh` | • ได้ Image `ecommerce-prod/payment-service:v1.0.0` อยู่ใน Local Docker | **PASS** [x] |
| **TC-P1-05** | Zero Code Execution Verification | สั่งสแกนผ่าน Trivy Container โดยสังเกตสถานะของ Container เป้าหมายด้วย `docker ps` | • **ไม่มีการสั่งรัน** `ecommerce-prod/payment-service` ขึ้นมาทำงานในระบบ<br>• Trivy สกัดข้อมูลผ่าน File Layer Extraction ล้วนๆ | **PASS** [x] |
| **TC-P1-06** | CycloneDX Full-Stack SBOM Validation | ตรวจสอบผลลัพธ์ SBOM ชั่วคราวใน Trivy Container | • ได้ไฟล์ CycloneDX JSON (v1.6) ที่มีโครงสร้างถูกต้อง<br>• สกัดครบ 2 ชั้น: **OS Packages** (Alpine 17 pkgs) และ **Application Packages** (NPM packages) | **PASS** [x] |

---

### กลุ่มที่ 3: การ Mapping Portfolio Hierarchy (Naming Convention Tests)

| Test Case ID | หัวข้อการทดสอบ | ขั้นตอนการทดสอบ (Steps) | ผลลัพธ์ที่คาดหวัง (Expected Results) | สถานะ |
| :--- | :--- | :--- | :--- | :---: |
| **TC-P1-07** | การสกัดชื่อแบบมาตรฐาน (`app/service:tag`) | สั่งสแกน Image:<br>`ecommerce-prod/payment-service:v1.0.0` | • Parent App: `ecommerce-prod`<br>• Parent Version: `main`<br>• Project Name: `payment-service`<br>• Project Version: `v1.0.0` | **PASS** [x] |
| **TC-P1-08** | การสกัดชื่อ Image ที่มี Registry Host นำหน้า | ทดสอบผ่าน Regex Helper ด้วย Image:<br>`image-registry.corp:5000/core-banking/auth-service:v2.0.0` | • สคริปต์ตัด Registry Host ออกอย่างถูกต้อง<br>• Parent App: `core-banking`<br>• Project Name: `auth-service` (Tag: `v2.0.0`) | **PASS** [x] |
| **TC-P1-09** | Fallback กรณี Image ไม่มี Slash (Single Word) | ทดสอบสกัด Image:<br>`standalone-service:1.0` | • Parent App กลายเป็น `default-portfolio`<br>• Project Name: `standalone-service` ไม่พบ Error | **PASS** [x] |

---

### กลุ่มที่ 4: การ Ingest และ Tracking ผ่าน API (API Ingestion Tests)

| Test Case ID | หัวข้อการทดสอบ | ขั้นตอนการทดสอบ (Steps) | ผลลัพธ์ที่คาดหวัง (Expected Results) | สถานะ |
| :--- | :--- | :--- | :--- | :---: |
| **TC-P1-10** | Automated Project Provisioning (`autoCreate=true`) | สั่งสแกน Image ใหม่ที่ยังไม่เคยมีใน Dependency-Track | • API Server ตอบรับ BOM (`HTTP 200/201`) พร้อม Token UUID<br>• สร้าง Parent และ Child Project ให้อัตโนมัติ โดยไม่ต้องสร้างมือก่อน | **PASS** [x] |
| **TC-P1-11** | Ingestion Status Polling (Token Check) | สังเกต Log ตอนสคริปต์สแกนกำลังยิง Token ไปที่ `/api/v1/bom/token/{token}` | • สคริปต์รอจนกว่า `processing: false`<br>• แสดงข้อความยืนยันความสำเร็จ | **PASS** [x] |

---

### กลุ่มที่ 5: การตรวจจับช่องโหว่ (Vulnerability Engine Verification)

| Test Case ID | หัวข้อการทดสอบ | ขั้นตอนการทดสอบ (Steps) | ผลลัพธ์ที่คาดหวัง (Expected Results) | สถานะ |
| :--- | :--- | :--- | :--- | :---: |
| **TC-P1-12** | Component Inventory Check | เข้าไปที่ UI หน้า Project `payment-service (v1.0.0)` | • พบรายการ Components ครบถ้วน (277 components รวม `express`, `lodash`, `axios`) | **PASS** [x] |
| **TC-P1-13** | Known CVE Detection | ตรวจสอบแท็บ **Vulnerabilities** ของโปรเจกต์ `payment-service` | • ตรวจพบช่องโหว่ความปลอดภัยที่ตรงกับเวอร์ชันล้าสมัยของ Sample App พร้อมแสดง CVSS และ Severity | **PASS** [x] |
| **TC-P1-14** | Hierarchical Metrics Roll-up | ตรวจสอบหน้า Parent Project `ecommerce-prod` | • สถิติช่องโหว่และจำนวน Component จาก Child Project (`payment-service`) ถูก Roll-up ขึ้นมาแสดงในระดับ Parent App โดยอัตโนมัติ | **PASS** [x] |

---

### กลุ่มที่ 6: การจัดการข้อผิดพลาด (Negative & Error Handling Tests)

| Test Case ID | หัวข้อการทดสอบ | ขั้นตอนการทดสอบ (Steps) | ผลลัพธ์ที่คาดหวัง (Expected Results) | สถานะ |
| :--- | :--- | :--- | :--- | :---: |
| **TC-P1-15** | สั่งสแกนโดยไม่ระบุ API Key | รัน `./scan-local-image.sh` โดยที่ไม่มี `DTRACK_API_KEY` | • สคริปต์ต้องหยุดทำงานทันที<br>• แสดงคำแนะนำวิธีการเข้าไป Generate API Key จาก UI อย่างชัดเจน | **PASS** [x] |
| **TC-P1-16** | สั่งสแกน Image ที่ไม่มีอยู่จริง | รัน `./scan-local-image.sh non-existent-app/ghost:latest` | • Trivy แจ้ง Error ว่าไม่พบ Image<br>• สคริปต์ Exit gracefully และไม่ส่ง BOM เปล่าเข้า Dependency-Track | **PASS** [x] |

---

### กลุ่มที่ 7: การบริหารจัดการหลายเวอร์ชัน (Multi-Version Lifecycle & Status Reconciliation)

| Test Case ID | หัวข้อการทดสอบ | ขั้นตอนการทดสอบ (Steps) | ผลลัพธ์ที่คาดหวัง (Expected Results) | สถานะ |
| :--- | :--- | :--- | :--- | :---: |
| **TC-P1-17** | การเปรียบเทียบ Image Creation Date และตั้งสถานะ Active/Inactive | 1. สแกน `payment-service:v1.0.0`<br>2. บิลด์เวอร์ชันใหม่ `payment-service:v1.1.0` และสั่งสแกน<br>3. ตรวจสอบสถานะ active และแท็ก `image-created:<ISO+07:00>` ของทั้ง 2 โปรเจกต์ | • ทั้งเวอร์ชัน `v1.0.0` และ `v1.1.0` คงอยู่ในระบบ (Historical Record ไม่หาย)<br>• เวอร์ชันใหม่ล่าสุด `v1.1.0` ได้รับสถานะ `active = true`<br>• เวอร์ชันเก่า `v1.0.0` ถูกปรับเป็น `active = false` อัตโนมัติ<br>• แท็ก `image-created` ถูกบันทึกในรูปแบบ ISO-8601 UTC+7 ชัดเจน | **PASS** [x] |

---

### กลุ่มที่ 8: การส่งออกรายงานระดับองค์กร (Enterprise Reporting & SBOM Inventory Exports)

| Test Case ID | หัวข้อการทดสอบ | ขั้นตอนการทดสอบ (Steps) | ผลลัพธ์ที่คาดหวัง (Expected Results) | สถานะ |
| :--- | :--- | :--- | :--- | :---: |
| **TC-P1-18** | Total Enterprise SBOM & Inventory Export | รันสคริปต์:<br>`python scripts/export-total-sbom.py` | • รวม Component จากทุกโปรเจกต์แบบ Multi-project aggregation<br>• ส่งออกไฟล์ `total-sbom.json`, `components-inventory.csv`, `components-unique.csv`<br>• คัดกรองและนับจำนวน Unique Libraries ได้ถูกต้อง (265 unique libraries) | **PASS** [x] |
| **TC-P1-19** | Enterprise Vulnerability Detail & Unique CVE Export | รันสคริปต์:<br>`python scripts/export-vulnerability-report.py --active-only` | • รวมรายการ Finding ทั้งหมดของ Portfolio ที่ Active (`vulnerabilities-detail.csv`: 162 findings)<br>• จำแนกรายการ Unique CVEs (`vulnerabilities-unique.csv`: 81 unique CVEs)<br>• สรุปสถิติความรุนแรงตามโปรเจกต์ (`vulnerabilities-summary.csv`: 42 High, 33 Med, 6 Low) | **PASS** [x] |

---

## 3. สรุปปัญหาที่พบในขั้นตอนการทดสอบและการแก้ไข (Issues Found & Resolutions)

### Issue 1: PostgreSQL Permission Denied บน Directory `/var/lib/postgresql/data`
* **สาเหตุ:** ใน `images/postgres/Dockerfile` มีการระบุ `USER 1001` ทำให้ entrypoint ของ `postgres:15-alpine` ไม่สามารถรัน `chmod 700` บน Docker volume ได้
* **การแก้ไข:** นำ `USER 1001` ออกจาก Dockerfile เพื่อให้ entrypoint จัดการ permissions ในช่วงบูต และสลับไปใช้ user `postgres` อัตโนมัติ พร้อมตั้ง `ENV PGDATA=/var/lib/postgresql/data/pgdata`

### Issue 2: Docker Socket Permission บน Docker Desktop
* **สาเหตุ:** Container `trivy-scanner` รันด้วย non-root user `10001` ทำให้ไม่สามารถอ่าน `/var/run/docker.sock` บนโฮสต์ของ Docker Desktop ได้
* **การแก้ไข:** เพิ่ม flag `--user 0` ใน `phase1-local-poc/scan-local-image.sh` เฉพาะตอนรันในโฮสต์ Local PoC (หมายเหตุ: ใน OpenShift Phase 3 จะไม่ต้องใช้ flag นี้เนื่องจาก Trivy ดึง layer ผ่าน OpenShift Internal Registry API แทน)

### Issue 3: Parent Project 404 Not Found เมื่ออัปโหลด BOM ครั้งแรก
* **สาเหตุ:** Endpoint `/api/v1/bom` ของ Dependency-Track แม้จะระบุ `autoCreate=true` จะสร้างเฉพาะ Child Project ให้ แต่หาก `parentName` ยังไม่มีในระบบ จะตอบกลับเป็น `HTTP 404: The parent component could not be found`
* **การแก้ไข:** อัปเดต `images/trivy-scanner/scan-and-upload.sh` ให้ทำการ Auto-Create/Ensure Parent Project ผ่าน `PUT /api/v1/project` ล่วงหน้า พร้อมดึง `parentUUID` ส่งแนบไปใน Request ทำให้ Parent/Child ผูกกันแบบ 100% Deterministic

### Issue 4: คำสั่ง Trivy convert ทำให้ได้เฉพาะ Root Component (Components = 1)
* **สาเหตุ:** เดิมใช้คำสั่ง `trivy image --format json --scanners vuln | trivy convert --format cyclonedx` ซึ่ง `trivy convert` ทำการแปลงเฉพาะโครงสร้างผลลัพธ์การสแกนช่องโหว่ ไม่ได้สกัด Component Inventory ฉบับเต็ม ทำให้ Dependency-Track แสดง Component เพียง 1 ตัว
* **การแก้ไข:** ปรับปรุง `scan-and-upload.sh` ให้สั่งสแกนและสกัด CycloneDX SBOM โดยตรง: `trivy image --format cyclonedx --output "$BOM_OUTPUT_FILE" "$TARGET_IMAGE"` ทำให้ได้ Inventory ครบถ้วน 277 components (17 Alpine OS packages + 260 NPM application packages) ภายในเวลาเพียง 3-5 วินาที

### Issue 5: Dependency-Track Normalize Tag ตัวพิมพ์เล็กทำให้ Date Parsing ล้มเหลว
* **สาเหตุ:** ค่าแท็ก `image-created:2026-10-10T18:07:06+07:00` ถูก Dependency-Track บังคับแปลงเป็นตัวพิมพ์เล็กในฐานข้อมูล (`...t18:07:06+07:00`) ทำให้ฟังก์ชัน `strptime` ใน jq ที่คาดหวังตัวอักษร `T` ทำงานผิดพลาดและส่งกลับ epoch 0
* **การแก้ไข:** ปรับปรุงฟังก์ชัน `epoch_from_tag` ใน `scan-and-upload.sh` ให้ใช้ `ascii_upcase` ก่อนส่งเข้า `strptime` เพื่อรองรับทั้งตัวพิมพ์เล็กและตัวพิมพ์ใหญ่ ทำให้เปรียบเทียบเวลา Image Creation ได้ถูกต้อง 100%

### Issue 6: Sonatype OSS Index คืนสถานะ HTTP 401 Unauthorized
* **สาเหตุ:** Sonatype OSS Index เริ่มบังคับจำกัดการใช้งาน Anonymous API Request ทำให้ Dependency-Track Background Task มี Error 401 ใน Log
* **การแก้ไข:** ระบบใช้ Internal Vulnerability Analyzer ร่วมกับ Google OSV Mirror (`npm`, `Alpine`) ซึ่งดาวน์โหลดฐานข้อมูลมาประมวลผลภายในเครื่อง ทำให้สามารถตรวจพบช่องโหว่ได้ครบถ้วน (81 ช่องโหว่) อย่างเสถียรและเป็นอิสระ โดยไม่จำเป็นต้องพึ่งพา Sonatype Anonymous API

---

## 4. สิ่งที่ต้องตั้งค่าเพิ่มเติม (Configuration Setup)
1. **Admin Credentials:** รหัสผ่านเริ่มต้นถูกเปลี่ยนเป็น:
   * **Username:** `admin`
   * **Password:** `Admin12345!`
2. **Automation Team Permissions:** ใน Dependency-Track ได้ทำการมอบสิทธิ์ให้กับทีม `Automation`:
   * `BOM_UPLOAD`
   * `PROJECT_CREATION_UPLOAD`
   * `PORTFOLIO_MANAGEMENT`
   * `VIEW_PORTFOLIO`
   * `VIEW_VULNERABILITY`
   * `VULNERABILITY_ANALYSIS`
3. **API Key:** คีย์ของทีม Automation ถูกตั้งค่าลงใน `phase1-local-poc/.env`:
   `DTRACK_API_KEY=odt_SHFUe9d8eUqjIUf4GXf84tUTknzoB6lc`

---

## 5. ตารางสรุปผลการทดสอบภาพรวม (Overall Execution Summary)

| ID | หัวข้อการทดสอบ | ขอบเขต (Scope) | ผลการทดสอบจริง | สถานะ |
| :--- | :--- | :--- | :--- | :---: |
| **TC-P1-01** | Build Compose Services (In-House) | Postgres, API Server, Frontend | Container ทั้ง 3 สตาร์ทติดและ Healthcheck ผ่าน | **PASS** [x] |
| **TC-P1-02** | Build Custom Trivy Scanner Image | Minimal Image (<100MB) | ขนาด 50.9 MB พร้อมเครื่องมือ Trivy, Curl, JQ ครบ | **PASS** [x] |
| **TC-P1-03** | Web UI & Administration Setup | Dependency-Track Frontend | เข้าใช้งาน UI ได้ที่พอร์ต 8080, สร้าง API Key สำเร็จ | **PASS** [x] |
| **TC-P1-04** | Build Sample Application Image | Payment Service (Alpine+Node) | บิลด์ `ecommerce-prod/payment-service:v1.0.0` สำเร็จ | **PASS** [x] |
| **TC-P1-05** | Zero Code Execution Verification | Security & Isolation | ไม่มี Container เป้าหมายถูกรัน, Trivy สกัดผ่าน Layer | **PASS** [x] |
| **TC-P1-06** | CycloneDX Full-Stack SBOM Validation | BOM Format & Completeness | ได้ CycloneDX 1.6 ครบทั้ง Alpine OS และ NPM packages | **PASS** [x] |
| **TC-P1-07** | Standard Image Naming Extraction | Portfolio Mapping | แยก Parent `ecommerce-prod`, Child `payment-service` | **PASS** [x] |
| **TC-P1-08** | Registry Host Prefix Stripping | Host Clean-up Regex | ตัด Host ออกถูกต้อง, Parent `core-banking`, Child `auth-service` | **PASS** [x] |
| **TC-P1-09** | Fallback Single-Word Image Name | Resilience Handling | ใช้ `default-portfolio` เป็น Parent ไม่พัง | **PASS** [x] |
| **TC-P1-10** | Automated Project Provisioning | Ingestion API | สร้าง Parent และ Child แบบอัตโนมัติบนระบบ | **PASS** [x] |
| **TC-P1-11** | Ingestion Status Polling (Token Check)| Asynchronous Ingestion | รอจน `processing: false` และแจ้งผลลัพธ์ชัดเจน | **PASS** [x] |
| **TC-P1-12** | Component Inventory Validation | Software Inventory | พบ 277 components ครบถ้วน (Express, Lodash, Axios ฯลฯ) | **PASS** [x] |
| **TC-P1-13** | Known CVE Vulnerability Detection | Vulnerability Engine | ตรวจพบ 81 ช่องโหว่ (42 High, 33 Medium, 6 Low) | **PASS** [x] |
| **TC-P1-14** | Hierarchical Metrics Roll-up | Portfolio Dashboard | ตัวชี้วัดรวมจาก Child สะท้อนขึ้นระดับ Parent App ถูกต้อง | **PASS** [x] |
| **TC-P1-15** | Missing API Key Handling | Negative Test | สคริปต์หยุดทำงานทันทีและแจ้งเตือนอย่างถูกต้อง | **PASS** [x] |
| **TC-P1-16** | Non-existent Image Handling | Negative Test | Trivy แจ้ง Error, สคริปต์ Exit โดยไม่ส่ง BOM เปล่า | **PASS** [x] |
| **TC-P1-17** | Multi-Version Latest Reconciliation | Lifecycle Management | เวอร์ชันใหม่ `v1.1.0` active, เวอร์ชันเก่า `v1.0.0` inactive | **PASS** [x] |
| **TC-P1-18** | Total Enterprise SBOM & Inventory Export| Enterprise Reporting | ส่งออก 819 instances / 265 unique libraries ครบถ้วน | **PASS** [x] |
| **TC-P1-19** | Enterprise Vulnerability Detail & Unique CVE| Security Reporting | ส่งออก 162 active findings / 81 unique CVEs ครบถ้วน | **PASS** [x] |

