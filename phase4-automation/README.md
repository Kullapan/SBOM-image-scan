# Phase 4: Automation & Reconciliation (Future Expansion)

เอกสารแนวทางการออกแบบและขยายผลระบบสู่การทำงานแบบอัตโนมัติ 100%:

## 1. Scheduled Reconciliation (CronJob)
* บรรจุไฟล์ `cronjob-weekly-audit.yaml` ที่ตั้งเวลาสแกนรายสัปดาห์ (Weekly Audit) ทุกวันอาทิตย์
* วัตถุประสงค์เพื่ออัปเดตสถานะของ Container Image ที่ไม่มีการบิลด์หรืออัปเดตใหม่ ให้สอดคล้องกับฐานข้อมูล CVE และ EPSS ที่อัปเดตรายวัน

## 2. Event-Driven Architecture (Event Receiver / Webhook)
เมื่อพร้อมเริ่มต้นพัฒนาโมดูลนี้ในอนาคต มีแนวทางหลัก 2 รูปแบบ:

### แนวทาง A: OpenShift Native Event Watcher
* พัฒนา Lightweight Controller (Go / Python) ติดตั้งใน Namespace `secops-sbom`
* ใช้ Kubernetes API Client ส่องดูการเปลี่ยนแปลงของ Resource `image.openshift.io/v1 ImageStreamTag` ข้าม Namespaces
* เมื่อพบ Tag ใหม่ ให้สั่งสร้าง `Job` ตามเทมเพลตใน Phase 3 โดยจำกัด Concurrency ไว้ที่ 3–5 Jobs พร้อมกัน (NFR-2.2)

### แนวทาง B: CI/CD Pipeline Webhook Receiver
* พัฒนา Webhook Receiver Endpoint สำหรับรับ HTTP POST จาก GitLab CI, Jenkins, หรือ Tekton Pipelines หลังจากที่มีการ Push Image สำเร็จ
* Endpoint จะนำ Image เข้าสู่คิวการสแกนอัตโนมัติ
