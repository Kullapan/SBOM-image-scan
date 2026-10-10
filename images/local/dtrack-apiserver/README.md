# Dependency-Track API Server Image

Image สำหรับ Dependency-Track API Server ที่ปรับแต่งสำหรับรันบน OpenShift:

## จุดเด่น
1. **Restricted SCC & Arbitrary UID:** ไดเรกทอรี `/data` (สำหรับ Lucene search index) และ `/tmp` ถูกตั้งค่าสิทธิ์ให้เข้ากันได้กับ OpenShift Arbitrary UID
2. **Corporate Proxy Support:** รองรับการระบุ Java System Properties ผ่าน Environment Variable `EXTRA_JAVA_OPTIONS` เช่น:
   `-Dhttp.proxyHost=proxy.corp.local -Dhttp.proxyPort=8080 -Dhttps.proxyHost=proxy.corp.local -Dhttps.proxyPort=8080`
3. **Internal Registry Air-Gap:** สามารถ Build และ Push เข้า OpenShift Internal Registry ได้โดยไม่ต้องดึง Image ภายนอกซ้ำ

## Environment Variables สำคัญ
* `ALPINE_DATABASE_URL`: `jdbc:postgresql://<postgres-host>:5432/dtrack`
* `ALPINE_DATABASE_DRIVER`: `org.postgresql.Driver`
* `ALPINE_DATABASE_USERNAME`: `dtrack`
* `ALPINE_DATABASE_PASSWORD`: `<password>`
* `EXTRA_JAVA_OPTIONS`: JVM Options เพิ่มเติม (รวมถึง Proxy settings)
