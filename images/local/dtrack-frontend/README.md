# Dependency-Track Frontend Image

Image สำหรับ Dependency-Track Web UI ที่ปรับแต่งให้รันภายใต้ **OpenShift Restricted SCC**:

## จุดเด่น
1. **Unprivileged Nginx:** รันบน Port 8080 และเขียนไฟล์ชั่วคราว/PID ไปที่ `/tmp` เพื่อหลีกเลี่ยงข้อจำกัดการเขียนไฟล์ Root Filesystem
2. **OpenShift Arbitrary UID Compliant:** ให้สิทธิ์ Directory ต่างๆ กับ Group 0
3. **Security Headers:** ใส่ Security Headers สำหรับ Web Interface (X-Frame-Options, X-Content-Type-Options)

## การตั้งค่า API URL ใน Frontend
ในขณะรัน สามารถส่งค่า Environment Variable:
* `API_BASE_URL`: URL ของ Dependency-Track API Server ที่ Browser เข้าถึงได้ (เช่น `http://localhost:8081` สำหรับ PoC หรือ Route URL บน OpenShift)
