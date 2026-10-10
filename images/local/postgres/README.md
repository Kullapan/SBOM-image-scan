# PostgreSQL Image (Hardened for OpenShift)

Image ฐานข้อมูล PostgreSQL 15 ที่ปรับแต่งสำหรับการรันบน OpenShift ภายใต้ **Restricted SCC**:

## จุดเด่น
1. **OpenShift Arbitrary UID Compliant:** ให้สิทธิ์ Group 0 (`root` group) บน `/var/run/postgresql` และ `/var/lib/postgresql/data` เพื่อให้ Container สามารถรันได้ด้วย Random UID ตามข้อกำหนดของ OpenShift
2. **Performance Tuning:** ปรับแต่ง `postgresql.conf` สำหรับเวิร์กโหลดการทำ Indexing และ Query ช่องโหว่ของ Dependency-Track
3. **Database Initialization:** บรรจุ `init-dtrack-db.sql` เพื่อเปิดใช้งาน UUID extension

## การ Build และทดสอบในเครื่อง
```bash
docker build -t custom-postgres:15-dtrack .
docker run --rm -p 5432:5432 -e POSTGRES_PASSWORD=secret custom-postgres:15-dtrack
```
