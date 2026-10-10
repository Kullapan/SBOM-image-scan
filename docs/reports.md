# คู่มือการสร้างและอ่านรายงาน (Reports Guide)

เอกสารนี้อธิบายขั้นตอนการ generate รายงานจาก Dependency-Track และความหมายของแต่ละไฟล์/คอลัมน์ ไฟล์ทั้งหมดถูกเขียนลงโฟลเดอร์ `reports/` (เปลี่ยนได้ด้วยอาร์กิวเมนต์แรก)

---

## 1. สิ่งที่ต้องมีก่อน

| รายการ | รายละเอียด |
|---|---|
| Dependency-Track ทำงานอยู่ | ค่าเริ่มต้น `http://localhost:8081` (ตั้งด้วย `API_BASE_URL` ใน `phase1-local-poc/.env` หรือ env `DTRACK_URL`) |
| API Key | `DTRACK_API_KEY` ใน `phase1-local-poc/.env` หรือ env เดียวกัน (ต้องมีสิทธิ์อ่าน project/component/vulnerability) |
| Python 3 | ใช้ standard library เท่านั้น ไม่ต้องติดตั้งแพ็กเกจเพิ่ม |
| สแกน image แล้ว | มี project ใน Dependency-Track (ดู README ขั้นตอนที่ 5) |
| (สำหรับรายงานช่องโหว่) ฐานข้อมูลช่องโหว่ sync แล้ว | และสั่ง **Reanalyze** แล้ว ไม่เช่นนั้นจะไม่มี finding (ดู README หัวข้อ "ตั้งค่า Vulnerability DB") |

### วิธีขอ API Key

1. เข้า UI ที่ `http://localhost:8080` แล้ว login ด้วยบัญชีผู้ดูแล (`admin`)
2. ไปที่ **Administration → Access Management → Teams**
3. เลือก team **Automation** (หรือสร้าง team ใหม่เช่น `Reporting`)
4. ที่ส่วน **API Keys** กดปุ่ม **+** เพื่อสร้าง key แล้วคัดลอกค่าที่ขึ้นต้นด้วย `odt_` ทันที
   (ควรคัดลอกเก็บไว้ทันที ในบางเวอร์ชัน key จะถูกซ่อนบางส่วนหลังสร้าง)
5. ที่ส่วน **Permissions** ของ team เดียวกัน ตรวจว่ามีสิทธิ์ตามตาราง:

| การใช้งาน | สิทธิ์ที่ต้องมี |
|---|---|
| รายงาน SBOM / Component / License | `VIEW_PORTFOLIO` |
| รายงานช่องโหว่ | `VIEW_PORTFOLIO`, `VIEW_VULNERABILITY` |
| สแกนและ upload BOM (scan-and-upload.sh) | `BOM_UPLOAD`, `PROJECT_CREATION_UPLOAD`, `PORTFOLIO_MANAGEMENT` (จำเป็นสำหรับสร้าง parent และตั้ง active/inactive ตาม version ล่าสุด) |
| ตั้งค่า Vulnerability Source / Analyzer ผ่าน API | `SYSTEM_CONFIGURATION` (หรือตั้งผ่าน UI ด้วยบัญชี admin แทน) |

6. นำ key ไปใส่ในไฟล์ `phase1-local-poc/.env`:
   ```bash
   DTRACK_API_KEY=odt_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   API_BASE_URL=http://localhost:8081
   ```
   หรือส่งผ่าน environment variable ชั่วคราว:
   ```bash
   # bash
   export DTRACK_API_KEY=odt_xxxxxxxx
   # PowerShell
   $env:DTRACK_API_KEY = "odt_xxxxxxxx"
   ```
7. ทดสอบว่า key ใช้ได้ (ได้ HTTP 200 และรายการ project กลับมา):
   ```bash
   curl -H "X-Api-Key: $DTRACK_API_KEY" http://localhost:8081/api/v1/project
   ```
   * `401` = key ผิดหรือหมดอายุ
   * `403` = key ถูกแต่ team ไม่มีสิทธิ์ที่ต้องการ (ตรวจตารางด้านบน)

> [!WARNING]
> API key เทียบเท่ารหัสผ่าน อย่า commit ไฟล์ `.env` ลง git และอย่าวาง key ในแชตหรือเอกสาร หากหลุดให้ลบ key ใน UI แล้วสร้างใหม่ ใน OpenShift ให้เก็บเป็น `Secret`

---

## 2. ขั้นตอนการ generate รายงาน

```bash
# 1) รายงาน SBOM / Component / License
python scripts/export-total-sbom.py            # หรือ scripts/export-total-sbom.sh

# 2) รายงานช่องโหว่ (Vulnerability)
python scripts/export-vulnerability-report.py                 # รวม project version ที่ inactive
python scripts/export-vulnerability-report.py --active-only   # เฉพาะ version ล่าสุด (active)

# เปลี่ยนโฟลเดอร์ปลายทาง (อาร์กิวเมนต์แรก)
python scripts/export-vulnerability-report.py ./my-reports --active-only
```

ลำดับที่แนะนำเมื่อต้องการรายงานช่องโหว่ล่าสุด:
1. สแกน image (`scan-local-image.sh <image>`)
2. ตรวจว่าฐานข้อมูลช่องโหว่ sync เสร็จ แล้ว Reanalyze project (หรือเรียก `portfolio/refresh`)
3. รัน `export-vulnerability-report.py`
4. เปิดไฟล์ CSV ด้วย Excel ได้ทันที (บันทึกเป็น UTF-8 with BOM)

---

## 3. รายงาน SBOM / Component / License (`export-total-sbom`)

| ไฟล์ | ระดับข้อมูล | ใช้ทำอะไร |
|---|---|---|
| `portfolio-inventory-summary.csv` | 1 แถวต่อ project version | ภาพรวมจำนวน component และช่องโหว่ต่อ project |
| `total-components-detail.csv` | 1 แถวต่อ (project × component) | รายการ component ทั้งหมดทุก project (รวมซ้ำข้าม project) |
| `total-unique-components.csv` | 1 แถวต่อ component ที่ไม่ซ้ำ | ดูว่า library ตัวไหนถูกใช้ในกี่ project |
| `<project>-<version>-cyclonedx.json` | 1 ไฟล์ต่อ project | SBOM มาตรฐาน CycloneDX สำหรับส่งต่อ/ตรวจสอบ |

### คอลัมน์ `portfolio-inventory-summary.csv`
`ProjectName`, `ProjectVersion`, `ParentApp`, `ComponentCount`, `Vulnerabilities` (จำนวนตาม metrics ณ รอบล่าสุด)

### คอลัมน์ `total-components-detail.csv`
| คอลัมน์ | ความหมาย |
|---|---|
| ParentApp | Parent project (Application) |
| ProjectName / ProjectVersion | Child project (ชื่อ image / tag) |
| Group, ComponentName, ComponentVersion | ข้อมูล component |
| PURL | Package URL (เช่น `pkg:npm/lodash@4.17.15`) |
| **License** | license ที่ระบุ (SPDX id) หรือ `Unspecified` ถ้าไม่ทราบ |
| Classifier | ประเภท (LIBRARY, OPERATING_SYSTEM ฯลฯ) |

### คอลัมน์ `total-unique-components.csv`
เหมือนด้านบน แต่เพิ่ม `ProjectsUsageCount` (จำนวน project ที่ใช้) และ `UsedInProjects` (รายชื่อ project คั่นด้วย `;`)

> **หมายเหตุ License:** ควรตรวจ license ประเภท copyleft (เช่น `GPL-*`) และรายการ `Unspecified` เป็นพิเศษ ถ้าต้องการบังคับนโยบาย ให้ใช้ **Policy** ของ Dependency-Track

---

## 4. รายงานช่องโหว่ (`export-vulnerability-report`)

| ไฟล์ | ระดับข้อมูล | ใช้ทำอะไร |
|---|---|---|
| `vulnerabilities-detail.csv` | 1 แถวต่อ finding (project × component × CVE) | รายการช่องโหว่ละเอียดทั้งหมด เรียงจากความรุนแรงสูงไปต่ำ แล้วตาม CVSS |
| `vulnerabilities-unique.csv` | 1 แถวต่อช่องโหว่ (Source + VulnId) | ดูว่าช่องโหว่ใดกระทบกี่ project/component |
| `vulnerabilities-summary.csv` | 1 แถวต่อ project version | จำนวนช่องโหว่ตาม Severity ของแต่ละ project |

### คอลัมน์ `vulnerabilities-detail.csv`
| คอลัมน์ | ความหมาย |
|---|---|
| ParentApp, ProjectName, ProjectVersion | ตำแหน่งใน portfolio |
| ProjectActive | `True` = version ล่าสุด (active), `False` = version เก่าที่ถูก deactivate |
| VulnId | รหัสช่องโหว่ (CVE-..., GHSA-...) |
| Source | แหล่งข้อมูล (NVD, GITHUB, OSV ฯลฯ) |
| Severity | CRITICAL / HIGH / MEDIUM / LOW / INFO / UNASSIGNED |
| CVSSv3, CVSSv2 | คะแนน CVSS (ว่างถ้าไม่มี) |
| EPSS | โอกาสถูกโจมตีจริง (0–1) ถ้ามีข้อมูล |
| CWE | ประเภทจุดอ่อน เช่น `CWE-79` |
| Aliases | รหัสอื่นของช่องโหว่เดียวกัน (CVE/GHSA/OSV) |
| Component, ComponentVersion, PURL | component ที่ได้รับผลกระทบ |
| AnalysisState | สถานะการ triage (`NOT_SET`, `EXPLOITABLE`, `NOT_AFFECTED`, `FALSE_POSITIVE` ฯลฯ) |
| Suppressed | `True` = ถูกซ่อนจากการ triage (ไม่ถูกนับใน summary) |
| Analyzer | ตัววิเคราะห์ที่พบ (เช่น internal, OSS Index) |
| Title, Published | หัวข้อและวันที่เผยแพร่ช่องโหว่ |

### คอลัมน์ `vulnerabilities-unique.csv`
`VulnId`, `Source`, `Severity`, `CVSSv3`, `CWE`, `Aliases`, `Title`, `AffectedProjectCount`, `AffectedComponentCount`, `AffectedProjects`, `AffectedComponents`

### คอลัมน์ `vulnerabilities-summary.csv`
`ParentApp`, `ProjectName`, `ProjectVersion`, `ProjectActive`, `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `INFO`, `UNASSIGNED`, `TotalUnsuppressed`, `TotalFindings`
(`TotalUnsuppressed` ไม่รวมรายการ suppressed ส่วน `TotalFindings` รวมทั้งหมด)

### กรณีไม่มีข้อมูล
ถ้ายังไม่มี finding จะได้ไฟล์ที่มีเฉพาะหัวคอลัมน์ และสคริปต์จะแจ้งให้ตรวจ 2 อย่าง คือ ฐานข้อมูลช่องโหว่ sync แล้วหรือยัง และ Reanalyze project แล้วหรือยัง

---

## 5. ข้อจำกัดที่ควรทราบ

* รายงานสะท้อนข้อมูล **ณ ขณะที่รัน** ใน Dependency-Track ถ้า sync/analyze ยังไม่เสร็จ ตัวเลขจะไม่ครบ
* รายงานช่องโหว่ **ยังไม่มีคอลัมน์ license, EOL และ deprecated** (license ดูได้จากรายงาน component, ส่วน EOL/deprecated ยังไม่ได้พัฒนา)
* ส่วนแปลง finding เป็นแถว CSV ของรายงานช่องโหว่ ยังไม่ได้ทดสอบกับข้อมูลจริง (ทดสอบแล้วเฉพาะกรณีไม่มี finding) หากชื่อ field ไม่ตรงอาจต้องปรับเล็กน้อย
* Project ที่ inactive ไม่ถูกนับใน Dashboard แต่จะอยู่ในรายงานตามค่าเริ่มต้น ใช้ `--active-only` เพื่อตัดออก
* ห้าม commit ไฟล์ใน `reports/` ที่มีข้อมูลองค์กรลง git สาธารณะ
