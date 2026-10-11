# PostgreSQL Image (Hardened for OpenShift)

Image ฐานข้อมูล PostgreSQL 15 ที่ปรับแต่งสำหรับการรันบน OpenShift ภายใต้ **Restricted SCC**:

## จุดเด่น
1. **Base Image:** พัฒนาบนฐาน `quay.io/sclorg/postgresql-15-c9s` (Software Collections CentOS Stream 9) ซึ่งเป็น Open Source Image ที่ดูแลโดยทีม Red Hat โดยตรง (หรือใช้ `registry.redhat.io/rhel9/postgresql-15` สำหรับองค์กรที่มี OpenShift Subscription)
2. **License & Cost:** **ฟรี 100% ไม่มีค่าใช้จ่าย** (Open Source - Apache 2.0 / BSD)
3. **OpenShift Arbitrary UID Compliant:** มี `nss_wrapper` ในตัว และกำหนดสิทธิ์ Group 0 (`root` group) บน `/var/lib/pgsql/data` เพื่อให้ Container สามารถรันได้ด้วย Random UID ตามข้อกำหนด Restricted SCC
4. **Health Check ในตัว:** รองรับ Container Probe ผ่าน `/usr/libexec/check-container`
5. **Performance Tuning:** ปรับแต่ง `postgresql.conf` สำหรับเวิร์กโหลดการทำ Indexing และ Query ช่องโหว่ของ Dependency-Track ผ่าน `/opt/app-root/src/postgresql-cfg/`
6. **Database Initialization:** บรรจุ `init-dtrack-db.sql` ใน `/opt/app-root/src/postgresql-init/` เพื่อเปิดใช้งาน UUID extension

## การ Build และทดสอบในเครื่อง
```bash
docker build -t ocp-sim-postgres:latest .
docker run --rm --user 1000680000:0 --cap-drop ALL -p 5432:5432 \
  -e POSTGRESQL_USER=dtrack -e POSTGRESQL_PASSWORD=dtrackpassword -e POSTGRESQL_DATABASE=dtrack \
  ocp-sim-postgres:latest
```
