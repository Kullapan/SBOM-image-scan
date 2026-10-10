# Phase 1: Local PoC (Proof of Concept)

สภาพแวดล้อมสำหรับทดสอบการทำงานของระบบบริหารจัดการ SBOM และช่องโหว่ความปลอดภัยบนเครื่องคอมพิวเตอร์ ด้วย Docker Compose และ Containerized Trivy Scanner

---

## 🏗️ โครงสร้าง Services ใน Phase 1

1. **`dtrack-db`**: PostgreSQL 15 Container (Build จาก `../images/postgres`)
2. **`dtrack-apiserver`**: Dependency-Track API Server Container (Build จาก `../images/dtrack-apiserver`)
3. **`dtrack-frontend`**: Dependency-Track Web UI Container (Build จาก `../images/dtrack-frontend`)
4. **`trivy-scanner`**: Ephemeral Worker Container (Build จาก `../images/trivy-scanner`) ถูกรันเมื่อสั่ง `./scan-local-image.sh`

---

## 🛠️ ขั้นตอนการรันและการทดสอบ

### ขั้นตอนที่ 1: เตรียมไฟล์คอนฟิก
```bash
cp .env.example .env
```

### ขั้นตอนที่ 2: สตาร์ท Dependency-Track Stack
```bash
docker compose up -d --build
```
ตรวจสอบสถานะ Container ด้วย:
```bash
docker compose ps
```

### ขั้นตอนที่ 3: ตั้งค่า API Key ใน Dependency-Track
1. เปิด Web Browser ไปที่: `http://localhost:8080`
2. เข้าสู่ระบบด้วย:
   * **Username:** `admin`
   * **Password:** `admin`
   *(ระบบจะบังคับให้เปลี่ยนรหัสผ่านในครั้งแรก ให้ตั้งรหัสผ่านใหม่)*
3. ไปที่เมนู **Administration** (ไอคอนฟันเฟือง) -> **Access Management** -> **Teams**
4. คลิกที่ทีม **Automation**
5. ในแท็บ **API Keys** ให้คลิกไอคอนเครื่องหมายบวกเพื่อสร้าง API Key
6. คัดลอก Key ที่ได้ นำไปใส่ในไฟล์ `.env` ที่ตัวแปร `DTRACK_API_KEY`:
   ```bash
   DTRACK_API_KEY=odt_xxxxxxxxxxxxxxxxxxxx
   ```

### ขั้นตอนที่ 4: Build Image ตัวอย่างและสั่งสแกน

คุณสามารถสั่งบิลด์และสแกนได้สะดวก 2 วิธี:

**วิธีที่ 1 (อัตโนมัติในคำสั่งเดียว):**
```bash
./scan-local-image.sh --sample
```
*(สคริปต์จะตรวจสอบว่ามี Image หรือไม่ หากยังไม่มีจะเรียก `build-sample-image.sh` มาบิลด์ให้ทันทีก่อนเริ่มสแกน)*

**วิธีที่ 2 (แยกคำสั่ง):**
```bash
# 1. บิลด์ Image ตัวอย่าง
./build-sample-image.sh ecommerce-prod/payment-service:v1.0.0

# 2. สั่งสแกน
./scan-local-image.sh ecommerce-prod/payment-service:v1.0.0
```

สคริปต์จะทำการ:
1. สกัด `ecommerce-prod` เป็น Parent Application
2. สกัด `payment-service` เป็น Child Microservice (Version `v1.0.0`)
3. สั่ง Ephemeral Container `custom-trivy-scanner` สแกนผ่าน Docker Socket
4. ส่ง CycloneDX JSON เข้าสู่ Dependency-Track ผ่าน REST API
5. Poll ตรวจสอบสถานะการ Import และ Indexing จนเสร็จสิ้น

### ขั้นตอนที่ 6: ตรวจสอบผลลัพธ์ใน Dependency-Track UI
เปิดไปที่ `http://localhost:8080/projects` จะพบ:
* โปรเจกต์แม่: **`ecommerce-prod`**
* โปรเจกต์ลูกย่อย: **`payment-service (v1.0.0)`**
* รายการส่วนประกอบ (OS Packages + NPM Packages)
* รายการ CVE ช่องโหว่ความปลอดภัย และระดับความเสี่ยง (CVSS, EPSS)
