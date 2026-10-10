# Test Sample Application

แอปพลิเคชัน Node.js ตัวอย่าง สำหรับใช้ Build เป็น Image เพื่อทดสอบสแกนหา SBOM และช่องโหว่ความปลอดภัย

## วิธี Build Image ทดสอบ:
```bash
# จากโฟลเดอร์ root ของโปรเจกต์
docker build -t ecommerce-prod/payment-service:v1.0.0 phase1-local-poc/test-samples/
```

จากนั้นสามารถสั่งสแกนด้วย:
```bash
cd phase1-local-poc
./scan-local-image.sh ecommerce-prod/payment-service:v1.0.0
```
ระบบจะสกัด:
* Parent App: `ecommerce-prod`
* Child Project: `payment-service`
* Version: `v1.0.0`
